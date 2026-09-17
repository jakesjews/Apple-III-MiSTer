module core_tb #(
	parameter ROM_FILE = "sim/gen/apple3.rom.hex"
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        serial_rx,
	input  logic        serial_cts_n,
	input  logic        serial_dsr_n,
	output wire         serial_tx,
	output wire         serial_rts_n,
	output wire         serial_dtr_n,
	input  logic [10:0] ps2_key,
	input  logic [64:0] host_rtc,
	input  logic [17:0] probe_addr,
	output logic [15:0] probe_word,
	input  logic [ 1:0] image_change,
	input  logic [63:0] image_size,
	input  logic        image_readonly,
	output wire  [31:0] sd_lba        [2],
	output wire  [ 5:0] sd_blk_cnt    [2],
	output wire  [ 1:0] sd_rd,
	sd_wr,
	input  logic [ 1:0] sd_ack,
	input  logic [13:0] sd_buff_addr,
	input  logic [ 7:0] sd_buff_dout,
	output wire  [ 7:0] sd_buff_din   [2],
	input  logic        sd_buff_wr,
	output logic [15:0] cpu_addr,
	output logic [15:0] pc,
	output logic [ 7:0] environment,
	output logic [ 7:0] zero_page,
	output logic [ 7:0] bank,
	output logic [ 3:0] video_mode,
	output logic        cpu_enable,
	output logic        cpu_sync,
	output logic        cpu_rwn,
	output logic [ 7:0] cpu_din,
	output logic [ 7:0] cpu_dout,
	output logic [ 7:0] e_pa_o,
	output logic [ 7:0] e_pa_ddr,
	output logic [ 7:0] a,
	output logic [ 7:0] x,
	output logic [ 7:0] y,
	output logic [ 7:0] sp,
	output logic [ 7:0] p,
	output logic [18:0] ram_byte_addr,
	output logic        ram_write,
	output logic        vblank,
	output logic        disk_activity,
	output logic [ 5:0] track1,
	output logic [12:0] track1_addr,
	output logic [ 7:0] qtrack1,
	output logic        valid1
);

	wire [7:0] video_r, video_g, video_b;
	wire hblank, hsync, vsync;
	wire signed [15:0] audio;
	wire [1:0] disk_active, disk_motors, disk_ready, disk_wp, disk_flux;
	wire [3:0] disk_phases;
	wire disk_write_mode, disk_write_bit, disk_write_strobe;
	for (genvar i = 0; i < 2; i++) begin : drives
		apple3_woz_drive woz (
			.clk,
			.reset,
			.change       (image_change[i]),
			.enabled      (1'b1),
			.image_size,
			.image_readonly,
			.protect      (1'b0),
			.active       (disk_active[i]),
			.motor_on     (disk_motors[i]),
			.phases       (disk_phases),
			.write_mode   (disk_write_mode),
			.write_bit    (disk_write_bit),
			.write_strobe (disk_write_strobe),
			.flux         (disk_flux[i]),
			.ready        (disk_ready[i]),
			.write_protect(disk_wp[i]),
			.sd_lba       (sd_lba[i]),
			.sd_blk_cnt   (sd_blk_cnt[i]),
			.sd_rd        (sd_rd[i]),
			.sd_wr        (sd_wr[i]),
			.sd_ack       (sd_ack[i]),
			.sd_buff_addr,
			.sd_buff_dout,
			.sd_buff_din  (sd_buff_din[i]),
			.sd_buff_wr
		);
	end
	assign track1      = drives[0].woz.track_id[7:2];
	assign track1_addr = drives[0].woz.bit_addr[12:0];
	assign qtrack1     = drives[0].woz.track_id;
	assign valid1      = drives[0].woz.valid && drives[0].woz.ready && (drives[0].woz.bit_count != 0);

	apple3_core #(
		.ROM_INIT_FILE (ROM_FILE),
		.ROM_INIT_START(4096)
	) dut (
		.clk_14m            (clk),
		.reset,
		.ps2_key            (ps2_key),
		.host_rtc,
		.serial_rx,
		.serial_cts_n,
		.serial_dsr_n,
		.serial_tx,
		.serial_rts_n,
		.serial_dtr_n,
		.joy_a_x            (8'h80),
		.joy_a_y            (8'h80),
		.joy_b_x            (8'h80),
		.joy_b_y            (8'h80),
		.joy_buttons        (4'h0),
		.rom_we             (1'b0),
		.rom_host_addr      (13'd0),
		.rom_host_data      (8'd0),
		.disk_ready         (disk_ready),
		.disk_write_protect (disk_wp),
		.disk_flux,
		.disk_media_change  (image_change),
		.disk_motors,
		.disk_phases,
		.disk_write_mode,
		.disk_write_bit,
		.disk_write_strobe,
		.video_r,
		.video_g,
		.video_b,
		.video_hblank       (hblank),
		.video_vblank       (vblank),
		.video_hsync        (hsync),
		.video_vsync        (vsync),
		.audio,
		.disk_activity,
		.disk1_active       (disk_active[0]),
		.disk2_active       (disk_active[1]),
		.debug_pc           (pc),
		.debug_cpu_addr     (cpu_addr),
		.debug_environment  (environment),
		.debug_zero_page    (zero_page),
		.debug_bank         (bank),
		.debug_video_mode   (video_mode),
		.debug_cpu_enable   (cpu_enable),
		.debug_cpu_sync     (cpu_sync),
		.debug_cpu_rwn      (cpu_rwn),
		.debug_cpu_din      (cpu_din),
		.debug_cpu_dout     (cpu_dout),
		.debug_e_pa_o       (e_pa_o),
		.debug_e_pa_ddr     (e_pa_ddr),
		.debug_a            (a),
		.debug_x            (x),
		.debug_y            (y),
		.debug_sp           (sp),
		.debug_p            (p),
		.debug_ram_byte_addr(ram_byte_addr),
		.debug_ram_write    (ram_write)
	);

	// Simulation probe into the sister-byte RAM so the harness can decode the
	// text page after injecting keystrokes.
	assign probe_word = dut.ram.mem[probe_addr];

endmodule
