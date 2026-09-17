// Apple /// RAM arranged as sister-byte pairs.  The stock 256 KiB machine uses
// 128K words; the parameters also support the documented 128 KiB configuration
// and third-party 512 KiB expansion for simulation and future builds.
// Addresses which differ by $0c00 share a word.  This mirrors the two DRAM
// output buses described in Apple patent US4383296 and the service manual.
//
// Quartus 17 consumes tens of gigabytes while inferring this unusually large,
// byte-write, dual-read array.  The MiSTer build therefore uses two explicit
// altsyncram lanes.  Simulation keeps the concise behavioral model so
// the implementation remains portable and easy to test.

module apple3_ram #(
	parameter integer WORD_ADDRESS_BITS = 17
) (
	input logic clk,

	input  logic [17:0] cpu_addr,
	input  logic        cpu_lane,
	input  logic        cpu_we,
	input  logic [ 7:0] cpu_din,
	output logic [15:0] cpu_q,

	input  logic [17:0] video_addr,
	output logic [15:0] video_q
);

`ifdef APPLE3_USE_ALTSYNCRAM
	wire [7:0] cpu_low_q;
	wire [7:0] cpu_high_q;
	wire [7:0] video_low_q;
	wire [7:0] video_high_q;

	altsyncram ram_low (
		.clock0        (clk),
		.address_a     (cpu_addr[WORD_ADDRESS_BITS-1:0]),
		.data_a        (cpu_din),
		.wren_a        (cpu_we && !cpu_lane),
		.q_a           (cpu_low_q),
		.clock1        (clk),
		.address_b     (video_addr[WORD_ADDRESS_BITS-1:0]),
		.data_b        (8'd0),
		.wren_b        (1'b0),
		.q_b           (video_low_q),
		.aclr0         (1'b0),
		.aclr1         (1'b0),
		.addressstall_a(1'b0),
		.addressstall_b(1'b0),
		.byteena_a     (1'b1),
		.byteena_b     (1'b1),
		.clocken0      (1'b1),
		.clocken1      (1'b1),
		.clocken2      (1'b1),
		.clocken3      (1'b1),
		.eccstatus     (),
		.rden_a        (1'b1),
		.rden_b        (1'b1)
	);
	// Keep the Quartus parameter table; Verible exhausts its wrapping search here.
	// verilog_format: off
	defparam
		ram_low.numwords_a = (1 << WORD_ADDRESS_BITS),
		ram_low.widthad_a = WORD_ADDRESS_BITS,
		ram_low.width_a = 8,
		ram_low.numwords_b = (1 << WORD_ADDRESS_BITS),
		ram_low.widthad_b = WORD_ADDRESS_BITS,
		ram_low.width_b = 8,
		ram_low.address_reg_b = "CLOCK1",
		ram_low.clock_enable_input_a = "BYPASS",
		ram_low.clock_enable_input_b = "BYPASS",
		ram_low.clock_enable_output_a = "BYPASS",
		ram_low.clock_enable_output_b = "BYPASS",
		ram_low.indata_reg_b = "CLOCK1",
		ram_low.intended_device_family = "Cyclone V",
		ram_low.lpm_type = "altsyncram",
		ram_low.operation_mode = "BIDIR_DUAL_PORT",
		ram_low.outdata_aclr_a = "NONE",
		ram_low.outdata_aclr_b = "NONE",
		ram_low.outdata_reg_a = "UNREGISTERED",
		ram_low.outdata_reg_b = "UNREGISTERED",
		ram_low.power_up_uninitialized = "FALSE",
		ram_low.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
		ram_low.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
		ram_low.width_byteena_a = 1,
		ram_low.width_byteena_b = 1,
		ram_low.wrcontrol_wraddress_reg_b = "CLOCK1";
	// verilog_format: on

	altsyncram ram_high (
		.clock0        (clk),
		.address_a     (cpu_addr[WORD_ADDRESS_BITS-1:0]),
		.data_a        (cpu_din),
		.wren_a        (cpu_we && cpu_lane),
		.q_a           (cpu_high_q),
		.clock1        (clk),
		.address_b     (video_addr[WORD_ADDRESS_BITS-1:0]),
		.data_b        (8'd0),
		.wren_b        (1'b0),
		.q_b           (video_high_q),
		.aclr0         (1'b0),
		.aclr1         (1'b0),
		.addressstall_a(1'b0),
		.addressstall_b(1'b0),
		.byteena_a     (1'b1),
		.byteena_b     (1'b1),
		.clocken0      (1'b1),
		.clocken1      (1'b1),
		.clocken2      (1'b1),
		.clocken3      (1'b1),
		.eccstatus     (),
		.rden_a        (1'b1),
		.rden_b        (1'b1)
	);
	// verilog_format: off
	defparam
		ram_high.numwords_a = (1 << WORD_ADDRESS_BITS),
		ram_high.widthad_a = WORD_ADDRESS_BITS,
		ram_high.width_a = 8,
		ram_high.numwords_b = (1 << WORD_ADDRESS_BITS),
		ram_high.widthad_b = WORD_ADDRESS_BITS,
		ram_high.width_b = 8,
		ram_high.address_reg_b = "CLOCK1",
		ram_high.clock_enable_input_a = "BYPASS",
		ram_high.clock_enable_input_b = "BYPASS",
		ram_high.clock_enable_output_a = "BYPASS",
		ram_high.clock_enable_output_b = "BYPASS",
		ram_high.indata_reg_b = "CLOCK1",
		ram_high.intended_device_family = "Cyclone V",
		ram_high.lpm_type = "altsyncram",
		ram_high.operation_mode = "BIDIR_DUAL_PORT",
		ram_high.outdata_aclr_a = "NONE",
		ram_high.outdata_aclr_b = "NONE",
		ram_high.outdata_reg_a = "UNREGISTERED",
		ram_high.outdata_reg_b = "UNREGISTERED",
		ram_high.power_up_uninitialized = "FALSE",
		ram_high.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
		ram_high.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
		ram_high.width_byteena_a = 1,
		ram_high.width_byteena_b = 1,
		ram_high.wrcontrol_wraddress_reg_b = "CLOCK1";
	// verilog_format: on

	assign cpu_q   = {cpu_high_q, cpu_low_q};
	assign video_q = {video_high_q, video_low_q};
`else
	(* ramstyle = "M10K, no_rw_check" *) logic [15:0] mem[0:(1 << WORD_ADDRESS_BITS)-1];

	always_ff @(posedge clk) begin
		cpu_q   <= mem[cpu_addr[WORD_ADDRESS_BITS-1:0]];
		video_q <= mem[video_addr[WORD_ADDRESS_BITS-1:0]];

		if (cpu_we) begin
			if (cpu_lane) mem[cpu_addr[WORD_ADDRESS_BITS-1:0]][15:8] <= cpu_din;
			else mem[cpu_addr[WORD_ADDRESS_BITS-1:0]][7:0] <= cpu_din;
		end
	end
`endif

endmodule
