module core_tb (
	input  logic clk,
	input  logic reset,
	output logic [15:0] cpu_addr,
	output logic [15:0] pc,
	output logic [7:0] environment,
	output logic [7:0] zero_page,
	output logic [7:0] bank,
	output logic [3:0] video_mode,
	output logic cpu_enable,
	output logic cpu_sync,
	output logic cpu_rwn,
	output logic [7:0] cpu_din,
	output logic [7:0] cpu_dout,
	output logic [7:0] e_pa_o,
	output logic [7:0] e_pa_ddr,
	output logic [7:0] a,
	output logic [7:0] x,
	output logic [7:0] y,
	output logic vblank,
	output logic disk_activity
);

	logic [5:0] track1, track2;
	logic [12:0] track1_addr, track2_addr;
	logic [7:0] track1_din, track2_din;
	logic track1_we, track2_we;
	logic [7:0] video_r, video_g, video_b;
	logic hblank, hsync, vsync;
	logic signed [15:0] audio;

	apple3_core #(
		.ROM_INIT_FILE("sim/gen/apple3.rom.hex"),
		.ROM_INIT_START(4096)
	) dut (
		.clk_14m(clk), .reset, .ps2_key(11'd0), .host_rtc(65'd0),
		.joy_a_x(8'h80), .joy_a_y(8'h80), .joy_b_x(8'h80), .joy_b_y(8'h80),
		.joy_buttons(4'h0), .rom_we(1'b0), .rom_host_addr(13'd0),
		.rom_host_data(8'd0), .disk_ready(2'b00), .disk_write_protect(2'b11),
		.track1, .track1_addr, .track1_din, .track1_dout(8'h00),
		.track1_we, .track1_busy(1'b0), .track2, .track2_addr,
		.track2_din, .track2_dout(8'h00), .track2_we, .track2_busy(1'b0),
		.video_r, .video_g, .video_b, .video_hblank(hblank),
		.video_vblank(vblank), .video_hsync(hsync), .video_vsync(vsync),
		.audio, .disk_activity, .debug_pc(pc), .debug_cpu_addr(cpu_addr),
		.debug_environment(environment), .debug_zero_page(zero_page),
		.debug_bank(bank), .debug_video_mode(video_mode),
		.debug_cpu_enable(cpu_enable), .debug_cpu_sync(cpu_sync),
		.debug_cpu_rwn(cpu_rwn), .debug_cpu_din(cpu_din),
		.debug_cpu_dout(cpu_dout), .debug_e_pa_o(e_pa_o),
		.debug_e_pa_ddr(e_pa_ddr), .debug_a(a), .debug_x(x), .debug_y(y)
	);

endmodule
