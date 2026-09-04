module core_tb (
	input  logic clk,
	input  logic reset,
	input  logic [10:0] ps2_key,
	input  logic [17:0] probe_addr,
	output logic [15:0] probe_word,
	input  logic disk_present,
	input  logic buffered_disk,
	input  logic [7:0] direct_track1_dout,
	input  logic image_change,
	input  logic image_mount,
	output logic [31:0] sd_lba,
	output logic sd_rd,
	output logic sd_wr,
	input  logic sd_ack,
	input  logic [8:0] sd_buff_addr,
	input  logic [7:0] sd_buff_dout,
	output logic [7:0] sd_buff_din,
	input  logic sd_buff_wr,
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
	output logic [7:0] sp,
	output logic [7:0] p,
	output logic [18:0] ram_byte_addr,
	output logic ram_write,
	output logic vblank,
	output logic disk_activity,
	output logic [5:0] track1,
	output logic [12:0] track1_addr
);

	logic [5:0] track2;
	logic [12:0] track2_addr;
	logic [7:0] track1_din, track2_din;
	logic track1_we, track2_we;
	logic [7:0] buffered_track1_dout;
	logic buffered_ready, buffered_busy;
	logic [7:0] video_r, video_g, video_b;
	logic hblank, hsync, vsync;
	logic signed [15:0] audio;
	logic disk1_active_internal;

	floppy_track buffered_image (
		.clk, .reset, .sd_lba, .sd_rd, .sd_wr, .sd_ack,
		.sd_buff_addr, .sd_buff_dout, .sd_buff_din, .sd_buff_wr,
		.change(image_change), .mount(image_mount), .track(track1),
		.ready(buffered_ready), .active(disk1_active_internal), .ram_addr(track1_addr),
		.ram_do(buffered_track1_dout), .ram_di(track1_din),
		.ram_we(track1_we), .busy(buffered_busy)
	);

	wire [7:0] core_track1_dout = buffered_disk ? buffered_track1_dout :
	                                                 direct_track1_dout;
	wire core_track1_busy = buffered_disk ? buffered_busy : 1'b0;
	wire core_disk_ready = disk_present && (!buffered_disk || buffered_ready);

	apple3_core #(
		.ROM_INIT_FILE("sim/gen/apple3.rom.hex"),
		.ROM_INIT_START(4096)
	) dut (
		.clk_14m(clk), .reset, .ps2_key(ps2_key), .host_rtc(65'd0),
		.joy_a_x(8'h80), .joy_a_y(8'h80), .joy_b_x(8'h80), .joy_b_y(8'h80),
		.joy_buttons(4'h0), .rom_we(1'b0), .rom_host_addr(13'd0),
		.rom_host_data(8'd0), .disk_ready({1'b0, core_disk_ready}),
		.disk_write_protect(2'b11),
		.track1, .track1_addr, .track1_din, .track1_dout(core_track1_dout),
		.track1_we, .track1_busy(core_track1_busy), .track2, .track2_addr,
		.track2_din, .track2_dout(8'h00), .track2_we, .track2_busy(1'b0),
		.video_r, .video_g, .video_b, .video_hblank(hblank),
		.video_vblank(vblank), .video_hsync(hsync), .video_vsync(vsync),
		.audio, .disk_activity, .disk1_active(disk1_active_internal),
		.disk2_active(),
		.debug_pc(pc), .debug_cpu_addr(cpu_addr),
		.debug_environment(environment), .debug_zero_page(zero_page),
		.debug_bank(bank), .debug_video_mode(video_mode),
		.debug_cpu_enable(cpu_enable), .debug_cpu_sync(cpu_sync),
		.debug_cpu_rwn(cpu_rwn), .debug_cpu_din(cpu_din),
		.debug_cpu_dout(cpu_dout), .debug_e_pa_o(e_pa_o),
		.debug_e_pa_ddr(e_pa_ddr), .debug_a(a), .debug_x(x), .debug_y(y),
		.debug_sp(sp), .debug_p(p), .debug_ram_byte_addr(ram_byte_addr),
		.debug_ram_write(ram_write)
	);

	// Simulation probe into the sister-byte RAM so the harness can decode the
	// text page after injecting keystrokes.
	assign probe_word = dut.ram.mem[probe_addr];

endmodule
