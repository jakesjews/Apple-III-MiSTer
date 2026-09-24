module core_tb #(
	parameter ROM_FILE = "sim/gen/apple3.rom.hex"
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        serial_rx,
	input  logic        serial_cts_n,
	input  logic        serial_dsr_n,
	input  logic        serial_dcd_n,
	output wire         serial_tx,
	output wire         serial_rts_n,
	output wire         serial_dtr_n,
	input  logic [10:0] ps2_key,
	// The mouse card in slot 4, with --mouse-card, and MiSTer's mouse report.
	input  logic        mouse_card_installed,
	input  logic [24:0] ps2_mouse,
	input  logic        plus_keymap,
	input  logic        ram_128k,
	// The OSD's Boot ROM option: Rob Justice's soshdboot ROM.
	input  logic        soshdboot,
	// The Apple /// Plus text interlace switch, and the field it is showing.
	input  logic        interlace,
	// A Euro system's 50 Hz scan PROM.
	input  logic        euro,
	output wire         field,
	// The OSD's Video option: 0 RGB, 1 colour composite, 2 mono composite,
	// and its Display option for the composite ones: 0 RGB Monitor,
	// 1 Monitor /// Green, 2 Amber, 3 Color TV.
	input  logic [ 1:0] video_source,
	input  logic [ 1:0] video_monitor,
	input  logic [64:0] host_rtc,
	input  logic [ 7:0] joy_a_x,
	input  logic [ 7:0] joy_a_y,
	input  logic [ 7:0] joy_b_x,
	input  logic [ 7:0] joy_b_y,
	input  logic        joy_a_button,
	input  logic        joy_a_switch,
	input  logic        joy_b_button,
	input  logic        joy_b_switch,
	input  logic [17:0] probe_addr,
	output logic [15:0] probe_word,
	input  logic [ 9:0] probe_font_addr,
	output logic [ 7:0] probe_font,
	// Images 0-3 are the Disk III drives; 4 and 5 are the block card's.
	input  logic [ 5:0] image_change,
	input  logic [63:0] image_size,
	input  logic        image_readonly,
	output wire  [31:0] sd_lba              [6],
	output wire  [ 5:0] sd_blk_cnt          [6],
	output wire  [ 5:0] sd_rd,
	sd_wr,
	input  logic [ 5:0] sd_ack,
	input  logic [13:0] sd_buff_addr,
	input  logic [ 7:0] sd_buff_dout,
	output wire  [ 7:0] sd_buff_din         [6],
	input  logic        sd_buff_wr,
	output wire         block_activity,
	// Rendered picture for --frame-out.
	output wire  [ 7:0] frame_r,
	frame_g,
	frame_b,
	output wire         frame_hblank,
	// Drive 1's write-protect terms for --wp-trace: host read-only, WOZ INFO
	// flag, not ready, flux track, and no track data.
	output wire  [ 4:0] wp_terms1,
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
	output logic        valid1,
	output logic        write_mode1,
	// The core's audio output for --audio-out.
	output wire signed [15:0] audio
);

	wire [7:0] video_r, video_g, video_b;
	wire [3:0] video_colour;
	wire [1:0] video_colour_phase;
	wire       video_colour_burst;
	wire hblank, hsync, vsync;
	wire [3:0] disk_active, disk_motors, disk_ready, disk_wp, disk_flux;
	wire [3:0] disk_phases;
	wire disk_write_mode, disk_write_bit, disk_write_strobe;
	for (genvar i = 0; i < 4; i++) begin : drives
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
	assign wp_terms1 = {
		drives[0].woz.readonly,
		drives[0].woz.info_wp,
		!drives[0].woz.ready,
		drives[0].woz.is_flux,
		drives[0].woz.bit_count == 0
	};
	apple3_composite monitor (
		.clk         (clk),
		.source      (video_source),
		.monitor     (video_monitor),
		.colour      (video_colour),
		.colour_phase(video_colour_phase),
		.colour_burst(video_colour_burst),
		.rgb_in      ({video_r, video_g, video_b}),
		.hblank_in   (hblank),
		.vblank_in   (vblank),
		.hsync_in    (hsync),
		.vsync_in    (vsync),
		.red         (frame_r),
		.green       (frame_g),
		.blue        (frame_b),
		.hblank      (frame_hblank),
		.vblank      (),
		.hsync       (),
		.vsync       ()
	);
	assign track1      = drives[0].woz.track_id[7:2];
	assign track1_addr = drives[0].woz.bit_addr[12:0];
	assign qtrack1     = drives[0].woz.track_id;
	assign write_mode1 = disk_write_mode && disk_active[0];
	assign valid1      = drives[0].woz.valid && drives[0].woz.ready && (drives[0].woz.bit_count != 0);

	// The block card sits in slot 1, as in the MiSTer top.
	wire [15:0] slot_addr;
	wire [7:0] slot_data_out, block_data, block_din;
	wire slot_cpu_read, slot_cycle, slot_reset, block_oe, block_ready;
	wire [3:0] slot_device_select, slot_io_select;
	wire [31:0] block_lba;
	wire [1:0] block_rd, block_wr;
	apple3_block_card block_card (
		.clk,
		.reset        (slot_reset),
		.cycle        (slot_cycle),
		.addr         (slot_addr[7:0]),
		.cpu_read     (slot_cpu_read),
		.data_in      (slot_data_out),
		.device_select(slot_device_select[0]),
		.io_select    (slot_io_select[0]),
		.data_out     (block_data),
		.data_oe      (block_oe),
		.ready        (block_ready),
		.activity     (block_activity),
		.image_change (image_change[5:4]),
		.image_size,
		.image_readonly,
		.sd_lba       (block_lba),
		.sd_rd        (block_rd),
		.sd_wr        (block_wr),
		.sd_ack       (sd_ack[5:4]),
		.sd_buff_addr (sd_buff_addr[8:0]),
		.sd_buff_dout,
		.sd_buff_din  (block_din),
		.sd_buff_wr
	);
	assign sd_lba[4]      = block_lba;
	assign sd_lba[5]      = block_lba;
	assign sd_blk_cnt[4]  = 6'd0;
	assign sd_blk_cnt[5]  = 6'd0;
	assign sd_rd[5:4]     = block_rd;
	assign sd_wr[5:4]     = block_wr;
	assign sd_buff_din[4] = block_din;
	assign sd_buff_din[5] = block_din;

	// The mouse card sits in slot 4, as in the MiSTer top.
	wire [7:0] mouse_data;
	wire mouse_oe, mouse_irq_n;
	apple3_mouse_card mouse_card (
		.clk,
		.reset        (slot_reset || !mouse_card_installed),
		.cycle        (slot_cycle),
		.addr         (slot_addr[7:0]),
		.cpu_read     (slot_cpu_read),
		.data_in      (slot_data_out),
		.device_select(slot_device_select[3]),
		.io_select    (slot_io_select[3]),
		.data_out     (mouse_data),
		.data_oe      (mouse_oe),
		.irq_n        (mouse_irq_n),
		.ps2_mouse,
		.speed        (2'd3)
	);

	apple3_core #(
		.ROM_INIT_FILE (ROM_FILE),
		.ROM_INIT_START(4096)
	) dut (
		.clk_14m            (clk),
		.reset,
		.ps2_key            (ps2_key),
		.plus_keymap        (plus_keymap),
		.ram_128k           (ram_128k),
		.soshdboot          (soshdboot),
		.interlace,
		.euro,
		.host_rtc,
		.serial_rx,
		.serial_cts_n,
		.serial_dsr_n,
		.serial_dcd_n,
		.serial_tx,
		.serial_rts_n,
		.serial_dtr_n,
		.joy_a_x,
		.joy_a_y,
		.joy_b_x,
		.joy_b_y,
		.joy_a_button,
		.joy_a_switch,
		.joy_b_button,
		.joy_b_switch,
		.slot_data_in       ({mouse_data, 16'hffff, block_data}),
		.slot_data_oe       ({mouse_oe, 2'b00, block_oe}),
		.slot_irq_n         ({mouse_irq_n, 3'b111}),
		.slot_nmi_n         (4'b1111),
		.slot_ready         ({3'b111, block_ready}),
		.slot_addr          (slot_addr),
		.slot_data_out      (slot_data_out),
		.slot_cpu_read      (slot_cpu_read),
		.slot_cycle         (slot_cycle),
		.slot_reset         (slot_reset),
		.slot_device_select (slot_device_select),
		.slot_io_select     (slot_io_select),
		.slot_io_strobe     (),
		.slot_rom_deselect  (),
		.slot_bus_conflict  (),
		.rom_we             (1'b0),
		.rom_host_addr      (13'd0),
		.rom_host_data      (8'd0),
		.disk_ready         (disk_ready),
		.disk_write_protect (disk_wp),
		.disk_flux,
		.disk_media_change  (image_change[3:0]),
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
		.video_field        (field),
		.video_colour,
		.video_colour_phase,
		.video_colour_burst,
		.audio,
		.disk_activity,
		.disk_active,
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
	// text page after injecting keystrokes, and into the character generator so
	// it can compare the downloaded font with the set SOS keeps at $0C00.
	assign probe_word = dut.ram.mem[probe_addr];
	assign probe_font = dut.video.character_ram[probe_font_addr];

endmodule
