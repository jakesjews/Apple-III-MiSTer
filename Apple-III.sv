//============================================================================
// Apple /// for MiSTer
//
// MiSTer platform wrapper around the Apple /// motherboard implementation.
// The machine logic lives in rtl/apple3_core.sv; this file only adapts clocks,
// video, controllers, ROM downloads, and MiSTer's block-device interface.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

	assign USER_OUT = '1;
	assign ADC_BUS = 'Z;
	assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
	assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE,
	        SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS,
	        SDRAM_nRAS, SDRAM_nCS} = 'Z;
	assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN,
	        DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

`ifdef MISTER_DUAL_SDRAM
	assign {SDRAM2_CLK, SDRAM2_A, SDRAM2_BA, SDRAM2_DQ,
	        SDRAM2_nCS, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nWE} = 'Z;
`endif

	assign LED_POWER = 2'b00;
	assign LED_DISK = 2'b00;
	assign BUTTONS = 2'b00;
	assign VGA_F1 = 1'b0;
	assign VGA_SCALER = 1'b0;
	assign VGA_DISABLE = 1'b0;
	assign HDMI_FREEZE = 1'b0;
	assign HDMI_BLACKOUT = 1'b0;
	assign HDMI_BOB_DEINT = 1'b0;
	assign UART_RTS = 1'b0;
	assign UART_TXD = 1'b1;
	assign UART_DTR = 1'b0;

	`include "build_id.v"
	localparam CONF_STR = {
		"Apple-III;;",
		"-;",
		"S0,NIB,Mount Drive 1;",
		"S1,NIB,Mount Drive 2;",
		"F2,BIN,Load Boot ROM;",
		"-;",
		"O2,Aspect ratio,4:3,16:9;",
		"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
		"O67,Write Protect,None,Drive 1,Drive 2,Both;",
		"-;",
		"R0,Reset;",
		"J1,Button 1,Button 2;",
		"J2,Button 1,Button 2;",
		"V,v",`BUILD_DATE
	};

	// The Apple /// master clock is 14.318181 MHz.  A phase-related 4x clock
	// feeds MiSTer's video pipeline while the machine and HPS bridge share the
	// native clock domain.
	wire clk_14m;
	wire pll_locked;
	pll pll
	(
		.refclk(CLK_50M),
		.rst(1'b0),
		.outclk_0(CLK_VIDEO),
		.outclk_1(clk_14m),
		.locked(pll_locked)
	);

	logic [1:0] pixel_divider = 2'd0;
	always_ff @(posedge CLK_VIDEO) pixel_divider <= pixel_divider + 1'b1;
	wire ce_pix = &pixel_divider;

	// MiSTer HPS interface.
	wire [127:0] status;
	wire [1:0] hps_buttons;
	wire forced_scandoubler;
	wire [21:0] gamma_bus;
	wire [31:0] joystick_0;
	wire [31:0] joystick_1;
	wire [15:0] joystick_analog_0;
	wire [15:0] joystick_analog_1;
	wire [10:0] ps2_key;
	wire [64:0] host_rtc;

	wire [1:0] img_mounted;
	wire img_readonly;
	wire [63:0] img_size;
	wire [31:0] sd_lba [2];
	wire [5:0] sd_blk_cnt [2];
	wire [1:0] sd_rd;
	wire [1:0] sd_wr;
	wire [1:0] sd_ack;
	wire [13:0] sd_buff_addr;
	wire [7:0] sd_buff_dout;
	wire [7:0] sd_buff_din [2];
	wire sd_buff_wr;

	wire ioctl_download;
	wire [15:0] ioctl_index;
	wire ioctl_wr;
	wire [26:0] ioctl_addr;
	wire [7:0] ioctl_dout;

	tri [35:0] ext_bus;
	assign ext_bus[32] = 1'b0;
	assign sd_blk_cnt[0] = 6'd0;
	assign sd_blk_cnt[1] = 6'd0;

	hps_io #(.CONF_STR(CONF_STR), .VDNUM(2)) hps_io_inst
	(
		.clk_sys(clk_14m),
		.HPS_BUS(HPS_BUS),
		.buttons(hps_buttons),
		.forced_scandoubler(forced_scandoubler),
		.video_rotated(1'b0),
		.new_vmode(1'b0),
		.gamma_bus(gamma_bus),
		.status(status),
		.status_in(status),
		.status_set(1'b0),
		.status_menumask(16'd0),
		.info_req(1'b0),
		.info(8'd0),

		.joystick_0(joystick_0),
		.joystick_1(joystick_1),
		.joystick_l_analog_0(joystick_analog_0),
		.joystick_l_analog_1(joystick_analog_1),
		.joystick_0_rumble(16'd0),
		.joystick_1_rumble(16'd0),
		.joystick_2_rumble(16'd0),
		.joystick_3_rumble(16'd0),
		.joystick_4_rumble(16'd0),
		.joystick_5_rumble(16'd0),
		.ps2_key(ps2_key),
		.ps2_kbd_led_status(3'd0),
		.ps2_kbd_led_use(3'd0),

		.img_mounted(img_mounted),
		.img_readonly(img_readonly),
		.img_size(img_size),
		.sd_lba(sd_lba),
		.sd_blk_cnt(sd_blk_cnt),
		.sd_rd(sd_rd),
		.sd_wr(sd_wr),
		.sd_ack(sd_ack),
		.sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din(sd_buff_din),
		.sd_buff_wr(sd_buff_wr),

		.ioctl_download(ioctl_download),
		.ioctl_index(ioctl_index),
		.ioctl_wr(ioctl_wr),
		.ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_dout),
		.ioctl_upload_req(1'b0),
		.ioctl_upload_index(8'd0),
		.ioctl_din(8'd0),
		.ioctl_wait(1'b0),
		.RTC(host_rtc),
		.EXT_BUS(ext_bus)
	);

	function automatic [7:0] controller_axis
	(
		input logic [7:0] analog_value,
		input logic negative,
		input logic positive
	);
		if (negative) controller_axis = 8'h00;
		else if (positive) controller_axis = 8'hff;
		else controller_axis = analog_value ^ 8'h80;
	endfunction

	wire [7:0] joy_a_x = controller_axis(
		joystick_analog_0[7:0], joystick_0[1], joystick_0[0]);
	wire [7:0] joy_a_y = controller_axis(
		joystick_analog_0[15:8], joystick_0[3], joystick_0[2]);
	wire [7:0] joy_b_x = controller_axis(
		joystick_analog_1[7:0], joystick_1[1], joystick_1[0]);
	wire [7:0] joy_b_y = controller_axis(
		joystick_analog_1[15:8], joystick_1[3], joystick_1[2]);

	// Apple /// SW0..SW3 are physically split across the two joystick ports.
	wire [3:0] joy_buttons = {
		joystick_0[5], joystick_0[4], joystick_1[4], joystick_1[5]
	};

	wire rom_write = ioctl_download && ioctl_wr && (ioctl_index == 16'd2) &&
	                 (ioctl_addr < 27'd8192);
	wire core_reset = RESET || status[0] || hps_buttons[1] || !pll_locked ||
	                  (ioctl_download && (ioctl_index == 16'd2));

	logic [1:0] disk_mount = 2'b00;
	logic [1:0] disk_change = 2'b00;
	logic [1:0] disk_readonly = 2'b00;

	always_ff @(posedge clk_14m) begin
		// A pulse guarantees a fresh rising edge for every insertion/removal.
		disk_change <= img_mounted;
		if (img_mounted[0]) begin
			disk_mount[0] <= (img_size != 0);
			disk_readonly[0] <= img_readonly;
		end
		if (img_mounted[1]) begin
			disk_mount[1] <= (img_size != 0);
			disk_readonly[1] <= img_readonly;
		end
	end

	wire [1:0] disk_ready;
	wire [1:0] disk_write_protect = disk_readonly | status[7:6];
	wire disk_activity;
	wire disk1_active;
	wire disk2_active;

	wire [5:0] track1;
	wire [12:0] track1_addr;
	wire [7:0] track1_din;
	wire [7:0] track1_dout;
	wire track1_we;
	wire track1_busy;
	wire [5:0] track2;
	wire [12:0] track2_addr;
	wire [7:0] track2_din;
	wire [7:0] track2_dout;
	wire track2_we;
	wire track2_busy;

	floppy_track drive1_image
	(
		.clk(clk_14m), .reset(core_reset),
		.sd_lba(sd_lba[0]), .sd_rd(sd_rd[0]), .sd_wr(sd_wr[0]),
		.sd_ack(sd_ack[0]), .sd_buff_addr(sd_buff_addr[8:0]),
		.sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din[0]),
		.sd_buff_wr(sd_buff_wr), .change(disk_change[0]),
		.mount(disk_mount[0]), .track(track1), .ready(disk_ready[0]),
		.active(disk1_active), .ram_addr(track1_addr), .ram_do(track1_dout),
		.ram_di(track1_din), .ram_we(track1_we), .busy(track1_busy)
	);

	floppy_track drive2_image
	(
		.clk(clk_14m), .reset(core_reset),
		.sd_lba(sd_lba[1]), .sd_rd(sd_rd[1]), .sd_wr(sd_wr[1]),
		.sd_ack(sd_ack[1]), .sd_buff_addr(sd_buff_addr[8:0]),
		.sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din[1]),
		.sd_buff_wr(sd_buff_wr), .change(disk_change[1]),
		.mount(disk_mount[1]), .track(track2), .ready(disk_ready[1]),
		.active(disk2_active), .ram_addr(track2_addr), .ram_do(track2_dout),
		.ram_di(track2_din), .ram_we(track2_we), .busy(track2_busy)
	);

	wire [7:0] core_r;
	wire [7:0] core_g;
	wire [7:0] core_b;
	wire core_hblank;
	wire core_vblank;
	wire core_hsync;
	wire core_vsync;
	wire signed [15:0] core_audio;

	apple3_core #(
		.ROM_INIT_FILE("rtl/rom/apple3.rom.hex"),
		.ROM_INIT_START(0),
		.ROM_INIT_LOW_FILE("rtl/rom/apple3-low.mif"),
		.ROM_INIT_HIGH_FILE("rtl/rom/apple3-high.mif")
	) machine (
		.clk_14m(clk_14m), .reset(core_reset), .ps2_key(ps2_key),
		.host_rtc(host_rtc), .joy_a_x(joy_a_x), .joy_a_y(joy_a_y),
		.joy_b_x(joy_b_x), .joy_b_y(joy_b_y), .joy_buttons(joy_buttons),
		.rom_we(rom_write), .rom_host_addr(ioctl_addr[12:0]),
		.rom_host_data(ioctl_dout), .disk_ready(disk_ready),
		.disk_write_protect(disk_write_protect),
		.track1(track1), .track1_addr(track1_addr), .track1_din(track1_din),
		.track1_dout(track1_dout), .track1_we(track1_we),
		.track1_busy(track1_busy), .track2(track2), .track2_addr(track2_addr),
		.track2_din(track2_din), .track2_dout(track2_dout),
		.track2_we(track2_we), .track2_busy(track2_busy),
		.video_r(core_r), .video_g(core_g), .video_b(core_b),
		.video_hblank(core_hblank), .video_vblank(core_vblank),
		.video_hsync(core_hsync), .video_vsync(core_vsync),
		.audio(core_audio), .disk_activity(disk_activity),
		.disk1_active(disk1_active), .disk2_active(disk2_active)
	);

	assign LED_USER = disk_activity;
	assign AUDIO_L = core_audio;
	assign AUDIO_R = core_audio;
	assign AUDIO_S = 1'b1;
	assign AUDIO_MIX = 2'b00;

	wire [2:0] video_effect = status[5:3];
	wire [2:0] scanline_level = video_effect ? video_effect - 1'b1 : 3'd0;
	wire use_scandoubler = forced_scandoubler || (video_effect != 0);
	assign VGA_SL = scanline_level[1:0];
	assign VIDEO_ARX = status[2] ? 13'd16 : 13'd4;
	assign VIDEO_ARY = status[2] ? 13'd9 : 13'd3;

	video_mixer #(.LINE_LENGTH(560), .GAMMA(1)) video_out
	(
		.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL), .ce_pix(ce_pix),
		.scandoubler(use_scandoubler), .hq2x(video_effect == 3'd1),
		.gamma_bus(gamma_bus), .R(core_r), .G(core_g), .B(core_b),
		.HSync(core_hsync), .VSync(core_vsync),
		.HBlank(core_hblank), .VBlank(core_vblank),
		.HDMI_FREEZE(HDMI_FREEZE), .freeze_sync(),
		.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
		.VGA_VS(VGA_VS), .VGA_HS(VGA_HS), .VGA_DE(VGA_DE)
	);

endmodule
