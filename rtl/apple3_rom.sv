// Two 4 KiB Apple /// boot-ROM banks.  The image is deliberately not part of
// the repository: build.sh converts a user-supplied 4K/8K ROM to the generated
// hex file, while MiSTer can also load one through ioctl at run time.

module apple3_rom #(
	parameter INIT_FILE = "",
	parameter integer INIT_START = 0,
	parameter INIT_LOW_FILE = "",
	parameter INIT_HIGH_FILE = ""
)(
	input  logic        clk,
	input  logic [12:0] addr,
	output logic [7:0]  q,
	input  logic        host_we,
	input  logic [12:0] host_addr,
	input  logic [7:0]  host_data
);

`ifdef APPLE3_USE_ALTSYNCRAM
	wire [7:0] low_q;
	wire [7:0] high_q;
	logic bank_select_d;

	// Separate physical banks allow one host write to mirror into both banks
	// without creating a two-write-port memory.  Upper-half writes only replace
	// the high bank, so both 4 KiB and 8 KiB uploads have the expected layout.
	apple3_rom_bank #(.INIT_FILE(INIT_LOW_FILE)) low_bank (
		.clk, .addr(addr[11:0]), .q(low_q), .host_addr(host_addr[11:0]),
		.host_data, .host_we(host_we && !host_addr[12])
	);
	apple3_rom_bank #(.INIT_FILE(INIT_HIGH_FILE)) high_bank (
		.clk, .addr(addr[11:0]), .q(high_q), .host_addr(host_addr[11:0]),
		.host_data, .host_we(host_we)
	);

	always_ff @(posedge clk) bank_select_d <= addr[12];
	always_comb q = bank_select_d ? high_q : low_q;
`else
	(* ramstyle = "M10K" *) logic [7:0] mem [0:8191];

	initial begin
		if (INIT_FILE != "") $readmemh(INIT_FILE, mem, INIT_START);
	end

	always_ff @(posedge clk) begin
		q <= mem[addr];
		if (host_we) begin
			mem[host_addr] <= host_data;
			// The stock ROM is 4 KiB and is selected in either of the two
			// motherboard ROM banks.  Mirror a 4 KiB MiSTer upload into the
			// upper bank; for an 8 KiB image the later upper-half writes replace
			// that mirror with the image's distinct second bank.
			if (!host_addr[12]) mem[{1'b1, host_addr[11:0]}] <= host_data;
		end
	end
`endif

endmodule

`ifdef APPLE3_USE_ALTSYNCRAM
module apple3_rom_bank #(
	parameter INIT_FILE = ""
)(
	input  logic        clk,
	input  logic [11:0] addr,
	output wire  [7:0]  q,
	input  logic [11:0] host_addr,
	input  logic [7:0]  host_data,
	input  logic        host_we
);

	altsyncram memory
	(
		.clock0(clk), .address_a(addr), .data_a(8'd0),
		.wren_a(1'b0), .q_a(q),
		.clock1(clk), .address_b(host_addr), .data_b(host_data),
		.wren_b(host_we), .q_b(),
		.aclr0(1'b0), .aclr1(1'b0),
		.addressstall_a(1'b0), .addressstall_b(1'b0),
		.byteena_a(1'b1), .byteena_b(1'b1),
		.clocken0(1'b1), .clocken1(1'b1),
		.clocken2(1'b1), .clocken3(1'b1),
		.eccstatus(), .rden_a(1'b1), .rden_b(1'b1)
	);
	defparam
		memory.numwords_a = 4096,
		memory.widthad_a = 12,
		memory.width_a = 8,
		memory.numwords_b = 4096,
		memory.widthad_b = 12,
		memory.width_b = 8,
		memory.address_reg_b = "CLOCK1",
		memory.clock_enable_input_a = "BYPASS",
		memory.clock_enable_input_b = "BYPASS",
		memory.clock_enable_output_a = "BYPASS",
		memory.clock_enable_output_b = "BYPASS",
		memory.indata_reg_b = "CLOCK1",
		memory.init_file = INIT_FILE,
		memory.intended_device_family = "Cyclone V",
		memory.lpm_type = "altsyncram",
		memory.operation_mode = "BIDIR_DUAL_PORT",
		memory.outdata_aclr_a = "NONE",
		memory.outdata_aclr_b = "NONE",
		memory.outdata_reg_a = "UNREGISTERED",
		memory.outdata_reg_b = "UNREGISTERED",
		memory.power_up_uninitialized = "FALSE",
		memory.ram_block_type = "M10K",
		memory.read_during_write_mode_mixed_ports = "DONT_CARE",
		memory.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
		memory.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
		memory.width_byteena_a = 1,
		memory.width_byteena_b = 1,
		memory.wrcontrol_wraddress_reg_b = "CLOCK1";

endmodule
`endif
