// Virtual ProDOS block-mode storage card for one Apple /// slot.
//
// The card follows the AppleWin hard-disk controller that the Apple II
// MiSTer core also uses: a 256-byte $Cnxx firmware with the ProDOS block
// device signature and entry point, and a register file in the slot's
// $C0nx aperture through which the firmware runs status, read, write and
// format commands. Two images from Main's block-device assignments appear
// as drives 1 and 2 of the card. A read or write moves one 512-byte block
// between the card's buffer and Main over the MiSTer SD interface while the
// card holds the CPU with the slot's RDY line, so the firmware sees the
// command complete in a single register read.
//
// Registers, offsets within the device-select aperture:
//   0  read   execute the command; returns the ProDOS error code, 0 = ok
//   1  read   last error code
//   2  r/w    command: 0 status, 1 read, 2 write, 3 format
//   3  r/w    unit, bit 7 selects drive 2
//   4  r/w    block number low byte
//   5  r/w    block number high byte
//   6  read   block count of the selected drive, low byte
//   7  read   block count of the selected drive, high byte
//   8  read   buffer byte at the pointer; the read advances the pointer
//   9  write  buffer byte at the pointer; the write advances the pointer
// Writing the command register or completing a command rewinds the pointer.
// The firmware never reads offset 9 or writes offset 8, so the 6502's
// indexed-store dummy read cannot move the pointer. Error codes follow the
// ProDOS 8 conventions: $27 I/O error for a block beyond the image, $28 no
// device connected for an empty drive, $2B write protected.
`timescale 1ns / 1ps
module apple3_block_card #(
	parameter FIRMWARE_FILE = "rtl/cards/apple3_block_firmware.hex"
) (
	input logic clk,
	input logic reset,
	input logic cycle,

	// Slot bus (docs/SLOTS.md); the card decodes only the page offset.
	input  logic [7:0] addr,
	input  logic       cpu_read,
	input  logic [7:0] data_in,
	input  logic       device_select,
	input  logic       io_select,
	output logic [7:0] data_out,
	output logic       data_oe,
	output logic       ready,
	output logic       activity,

	// Host images: drive 1 is index 0, drive 2 is index 1.
	input  logic [ 1:0] image_change,
	input  logic [63:0] image_size,
	input  logic        image_readonly,
	output logic [31:0] sd_lba,
	output logic [ 1:0] sd_rd,
	output logic [ 1:0] sd_wr,
	input  logic [ 1:0] sd_ack,
	input  logic [ 8:0] sd_buff_addr,
	input  logic [ 7:0] sd_buff_dout,
	output logic [ 7:0] sd_buff_din,
	input  logic        sd_buff_wr
);
	localparam logic [7:0] COMMAND_STATUS  = 8'h00;
	localparam logic [7:0] COMMAND_READ    = 8'h01;
	localparam logic [7:0] COMMAND_WRITE   = 8'h02;
	localparam logic [7:0] COMMAND_FORMAT  = 8'h03;
	localparam logic [7:0] ERROR_IO        = 8'h27;
	localparam logic [7:0] ERROR_NO_DEVICE = 8'h28;
	localparam logic [7:0] ERROR_PROTECTED = 8'h2b;

	typedef enum logic [2:0] {
		IDLE,
		REQUEST,
		TRANSFER,
		DONE,
		RELEASE
	} state_t;

	// Mount state survives reset, like a drive keeps its disk.
	logic [1:0]       mounted = 2'b00;
	logic [1:0]       readonly = 2'b11;
	logic [1:0][15:0] blocks = '0;
	logic [7:0] command, unit, error;
	logic [15:0] block;
	logic [ 8:0] pointer;
	logic [ 7:0] rom     [256];
	logic [ 7:0] buffer  [512];
	logic [7:0] rom_q, buffer_q;
	logic   [15:0] drive_blocks;
	state_t        state;
	logic drive, busy, execute_select, data_read, data_write, buffer_we;
	logic [8:0] buffer_addr;
	logic [7:0] buffer_din;

	initial $readmemh(FIRMWARE_FILE, rom);

	assign drive          = unit[7];
	assign drive_blocks   = drive ? blocks[1] : blocks[0];
	assign busy           = (state == REQUEST) || (state == TRANSFER);
	assign activity       = busy;
	assign execute_select = device_select && cpu_read && (addr[3:0] == 4'h0);
	assign data_read      = cycle && device_select && cpu_read && (addr[3:0] == 4'h8);
	assign data_write     = cycle && device_select && !cpu_read && (addr[3:0] == 4'h9);
	// The firmware's execute read waits from the moment the address is
	// decoded until the result is ready; the completion edge then clears it.
	assign ready          = reset || !(execute_select && (state == IDLE || busy));
	assign sd_lba         = {16'd0, block};
	assign sd_buff_din    = buffer_q;

	// One buffer serves both sides: the CPU only touches it while no host
	// transfer is running, because the execute read holds the CPU meanwhile.
	assign buffer_we   = busy ? (sd_buff_wr && sd_ack[drive]) : data_write;
	assign buffer_addr = busy ? sd_buff_addr : pointer;
	assign buffer_din  = busy ? sd_buff_dout : data_in;

	always_ff @(posedge clk) begin
		if (buffer_we) buffer[buffer_addr] <= buffer_din;
		buffer_q <= buffer[buffer_addr];
		rom_q    <= rom[addr];
	end

	always_comb begin
		data_oe  = !reset && cpu_read && (device_select || io_select);
		data_out = 8'hff;
		if (io_select) data_out = rom_q;
		else begin
			case (addr[3:0])
				4'h0, 4'h1: data_out = error;
				4'h2:       data_out = command;
				4'h3:       data_out = unit;
				4'h4:       data_out = block[7:0];
				4'h5:       data_out = block[15:8];
				4'h6:       data_out = drive_blocks[7:0];
				4'h7:       data_out = drive_blocks[15:8];
				4'h8:       data_out = buffer_q;
				default:    data_out = 8'hff;
			endcase
		end
	end

	always_ff @(posedge clk) begin
		for (int i = 0; i < 2; i++) begin
			if (image_change[i]) begin
				mounted[i]  <= image_size != 64'd0;
				readonly[i] <= image_readonly;
				// ProDOS and SOS address at most 65,535 blocks.
				blocks[i]   <= (image_size[63:25] != 0) ? 16'hffff : image_size[24:9];
			end
		end

		if (reset) begin
			state   <= IDLE;
			sd_rd   <= 2'b00;
			sd_wr   <= 2'b00;
			command <= 8'h00;
			unit    <= 8'h00;
			block   <= 16'h0000;
			error   <= 8'h00;
			pointer <= 9'd0;
		end else begin
			if (cycle && device_select && !cpu_read) begin
				case (addr[3:0])
					4'h2: begin
						command <= data_in;
						pointer <= 9'd0;
					end
					4'h3:    unit <= data_in;
					4'h4:    block[7:0] <= data_in;
					4'h5:    block[15:8] <= data_in;
					4'h9:    pointer <= pointer + 9'd1;
					default: ;
				endcase
			end
			if (data_read) pointer <= pointer + 9'd1;

			case (state)
				IDLE: begin
					if (execute_select) begin
						if (!mounted[drive]) begin
							error <= ERROR_NO_DEVICE;
							state <= DONE;
						end else if (command == COMMAND_STATUS) begin
							error <= 8'h00;
							state <= DONE;
						end else if (command == COMMAND_FORMAT) begin
							error <= readonly[drive] ? ERROR_PROTECTED : 8'h00;
							state <= DONE;
						end else if ((command != COMMAND_READ) && (command != COMMAND_WRITE)) begin
							error <= ERROR_IO;
							state <= DONE;
						end else if (block >= drive_blocks) begin
							error <= ERROR_IO;
							state <= DONE;
						end else if ((command == COMMAND_WRITE) && readonly[drive]) begin
							error <= ERROR_PROTECTED;
							state <= DONE;
						end else if (!sd_ack[drive]) begin
							// Wait out a transfer that a reset abandoned.
							sd_rd[drive] <= command == COMMAND_READ;
							sd_wr[drive] <= command == COMMAND_WRITE;
							state        <= REQUEST;
						end
					end
				end
				REQUEST: begin
					if (sd_ack[drive]) begin
						sd_rd <= 2'b00;
						sd_wr <= 2'b00;
						state <= TRANSFER;
					end
				end
				TRANSFER: begin
					if (!sd_ack[drive]) begin
						error   <= 8'h00;
						pointer <= 9'd0;
						state   <= DONE;
					end
				end
				DONE: begin
					if (cycle && execute_select) begin
						pointer <= 9'd0;
						state   <= RELEASE;
					end
				end
				RELEASE: begin
					if (!execute_select) state <= IDLE;
				end
				default: state <= IDLE;
			endcase
		end
	end
endmodule
