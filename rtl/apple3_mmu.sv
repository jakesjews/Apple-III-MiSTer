// Apple /// address translation and overlay decode.
//
// This is kept combinational so the mapping can be tested independently of the
// CPU and RAM implementation.  The rules come from the Apple /// Level 2 Service
// Reference Manual (chapter 2), the 342-0043/0061/0063 PROM equations, SOS 1.3,
// Jeppson's "III BITS", and the July 1981 Apple "Funny Mode" memo.  MAME is used
// as a compatibility cross-check, not as the sole specification.

module apple3_mmu #(
	parameter integer RAM_BANKS = 16
)(
	input  logic [15:0] cpu_addr,
	input  logic        cpu_read,
	input  logic [7:0]  environment,
	input  logic [7:0]  zero_page,
	input  logic [7:0]  bank_register,
	input  logic        native_mode,
	input  logic        extended_active,
	input  logic [7:0]  extended_bank,

	output logic [18:0] ram_byte_addr,
	output logic [17:0] ram_word_addr,
	output logic        ram_lane,
	output logic        ram_read,
	output logic        ram_write_allowed,
	output logic        rom_read,
	output logic [12:0] rom_addr,
	output logic        io_select,
	output logic        via_d_select,
	output logic        via_e_select
);

	localparam logic [3:0] SYSTEM_BANK =
		(RAM_BANKS == 4) ? 4'd3 : (RAM_BANKS == 8) ? 4'd7 : 4'd15;
	localparam logic [3:0] BANK_MASK =
		(RAM_BANKS == 4) ? 4'h3 : (RAM_BANKS == 8) ? 4'h7 : 4'hf;

	logic [3:0] selected_bank;
	logic [3:0] mapped_bank;
	logic [7:0] mapped_page;
	logic [14:0] bank_offset;
	logic        high_protected;
	logic        extended_cycle;
	logic        extended_system_map;
	logic        io_window;
	logic        always_ram_window;
	logic [18:0] translated_addr;

	always_comb begin
		// Apple shipped power-of-two RAM configurations.  Selecting the physical
		// system bank through the window aliases bank 2 in all configurations.
		selected_bank = bank_register[3:0] & BANK_MASK;
		if (selected_bank == SYSTEM_BANK) selected_bank = 4'd2;

		extended_cycle      = extended_active && extended_bank[7] &&
		                      (cpu_addr >= 16'h0100);
		extended_system_map = extended_cycle && (extended_bank[3:0] == 4'hf);
		high_protected      = environment[3] && (cpu_addr >= 16'hc000);
		io_window           = environment[6] &&
		                      (((cpu_addr >= 16'hc000) && (cpu_addr < 16'hc500)) ||
		                       ((cpu_addr >= 16'hc800) && (cpu_addr < 16'hd000)));
		always_ram_window   = (cpu_addr >= 16'hc500) && (cpu_addr < 16'hc800);

		mapped_bank  = SYSTEM_BANK;
		bank_offset  = cpu_addr[14:0];
		mapped_page  = zero_page;

		if (extended_cycle && !extended_system_map) begin
			// X=$80+n supplies the high 32-K bank number.  A15 selects n/n+1.
			mapped_bank = (extended_bank[3:0] + {3'b000, cpu_addr[15]}) & BANK_MASK;
			bank_offset = cpu_addr[14:0];
		end
		else if (cpu_addr < 16'h0100) begin
			// The zero-page register is itself a logical page number and is fed
			// through the same fixed/window/fixed map as a normal CPU address.
			if (mapped_page < 8'h20) begin
				mapped_bank = SYSTEM_BANK;
				bank_offset = {2'b00, mapped_page[4:0], cpu_addr[7:0]};
			end
			else if (mapped_page < 8'ha0) begin
				mapped_bank = extended_system_map ? 4'd0 : selected_bank;
				bank_offset = {mapped_page[6:0] - 7'h20, cpu_addr[7:0]};
			end
			else begin
				mapped_bank = SYSTEM_BANK;
				bank_offset = {mapped_page[6:0], cpu_addr[7:0]};
			end
		end
		else if ((cpu_addr < 16'h0200) && !environment[2]) begin
			// With STACK1XX clear, $01xx follows the page adjacent to ZP.
			mapped_page = zero_page ^ 8'h01;
			if (mapped_page < 8'h20) begin
				mapped_bank = SYSTEM_BANK;
				bank_offset = {2'b00, mapped_page[4:0], cpu_addr[7:0]};
			end
			else if (mapped_page < 8'ha0) begin
				mapped_bank = extended_system_map ? 4'd0 : selected_bank;
				bank_offset = {mapped_page[6:0] - 7'h20, cpu_addr[7:0]};
			end
			else begin
				mapped_bank = SYSTEM_BANK;
				bank_offset = {mapped_page[6:0], cpu_addr[7:0]};
			end
		end
		else if (cpu_addr < 16'h2000) begin
			mapped_bank = SYSTEM_BANK;
			bank_offset = cpu_addr[14:0];
		end
		else if (cpu_addr < 16'ha000) begin
			mapped_bank = extended_system_map ? 4'd0 : selected_bank;
			bank_offset = cpu_addr[14:0] - 15'h2000;
		end
		else begin
			mapped_bank = SYSTEM_BANK;
			bank_offset = cpu_addr[14:0];
		end

		translated_addr = {mapped_bank, bank_offset};
		ram_byte_addr   = translated_addr;
		// The DRAM datapath fetches A and A xor $0c00 together.  Canonicalise
		// that pair into one 16-bit word; lane identifies the requested byte.
		ram_word_addr   = {translated_addr[18:12],
		                   translated_addr[10] ^ translated_addr[11],
		                   translated_addr[9:0]};
		ram_lane        = translated_addr[11];

		rom_addr          = {environment[1], cpu_addr[11:0]};
		rom_read          = 1'b0;
		io_select         = 1'b0;
		via_d_select      = 1'b0;
		via_e_select      = 1'b0;
		ram_read          = cpu_read;
		ram_write_allowed = !cpu_read && !high_protected;

		if (extended_cycle) begin
			// Both indexed modes bypass ROM, I/O and write protection.  $8f uses
			// the normal fixed-bank shape but forces bank 0 into the window.
			ram_read          = cpu_read;
			ram_write_allowed = !cpu_read;
		end
		else begin
			if (io_window && !always_ram_window) begin
				ram_read          = 1'b0;
				ram_write_allowed = 1'b0;
				io_select         = (cpu_addr < 16'hc100);
			end

			// The VIA apertures sit above the ROM/RAM overlay and disappear in
			// Apple II emulation ("funny") mode when E-VIA PA6 is driven low.
			if (native_mode && (cpu_addr >= 16'hffd0) &&
			    (cpu_addr < 16'hffe0)) begin
				ram_read          = 1'b0;
				ram_write_allowed = 1'b0;
				rom_read          = 1'b0;
				via_d_select      = 1'b1;
			end
			else if (native_mode && (cpu_addr >= 16'hffe0) &&
			         (cpu_addr < 16'hfff0)) begin
				ram_read          = 1'b0;
				ram_write_allowed = 1'b0;
				rom_read          = 1'b0;
				via_e_select      = 1'b1;
			end
			else if (cpu_read && environment[0] &&
			         (cpu_addr >= 16'hf000) &&
			         !((cpu_addr >= 16'hffc0) && (cpu_addr < 16'hffd0))) begin
				ram_read = 1'b0;
				rom_read = 1'b1;
			end
		end
	end

endmodule
