//============================================================================
// Apple /// for MiSTer
//
// MiSTer platform wrapper around the Apple /// motherboard implementation.
// The machine logic lives in rtl/apple3_core.sv; this file only adapts clocks,
// video, controllers, ROM downloads, and MiSTer's block-device interface.
//============================================================================

module emu (
	`include "sys/emu_ports.vh"
);

	assign USER_OUT = '1;
	assign ADC_BUS = 'Z;
	assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
	assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE,
			SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS,
			SDRAM_nRAS, SDRAM_nCS} = 'Z;
	assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

`ifdef MISTER_DUAL_SDRAM
	assign {SDRAM2_CLK, SDRAM2_A, SDRAM2_BA, SDRAM2_DQ, SDRAM2_nCS, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nWE} = 'Z;
`endif

	assign LED_POWER      = 2'b00;
	assign LED_DISK       = 2'b00;
	assign BUTTONS        = 2'b00;
	assign VGA_F1         = 1'b0;
	assign VGA_SCALER     = 1'b0;
	assign VGA_DISABLE    = 1'b0;
	assign HDMI_FREEZE    = 1'b0;
	assign HDMI_BLACKOUT  = 1'b0;
	assign HDMI_BOB_DEINT = 1'b0;

	`include "build_id.v"
	localparam CONF_STR = {
		"Apple-III;UART19200:9600:4800:2400:1200:600:300:150:110:75:50;",
		"-;",
		"S0,WOZDSKDO PO NIB2MG,Mount Drive 1;",
		"S1,WOZDSKDO PO NIB2MG,Mount Drive 2;",
		"F2,ROMBIN,Load Boot ROM;",
		"-;",
		"O2,Aspect ratio,4:3,16:9;",
		"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
		"O67,Write Protect,None,Drive 1,Drive 2,Both;",
		"O8,Keyboard,Apple ///,/// Plus;",
		"O9,Serial CTS,Always ready,Host RTS;",
		"OA,Joystick 1 on,Port B,Port A;",
		"-;",
		"R0,Reset;",
		"J,Button,Switch;",
		"jn,A,B;",
		"jp,Y,B;",
		"V,v",
		`BUILD_DATE
	};

	// The Apple /// master clock is 14.318181 MHz.  A phase-related 4x clock
	// feeds MiSTer's video pipeline while the machine and HPS bridge share the
	// native clock domain.
	wire clk_14m;
	wire pll_locked;
	pll pll (
		.refclk  (CLK_50M),
		.rst     (1'b0),
		.outclk_0(CLK_VIDEO),
		.outclk_1(clk_14m),
		.locked  (pll_locked)
	);

	logic [1:0] pixel_divider = 2'd0;
	always_ff @(posedge CLK_VIDEO) pixel_divider <= pixel_divider + 1'b1;
	wire ce_pix = &pixel_divider;

	// MiSTer HPS interface.
	wire [127:0] status;
	wire [  1:0] hps_buttons;
	wire         forced_scandoubler;
	wire [ 21:0] gamma_bus;
	wire [ 31:0] joystick_0;
	wire [ 31:0] joystick_1;
	wire [ 15:0] joystick_analog_0;
	wire [ 15:0] joystick_analog_1;
	wire [ 10:0] ps2_key;
	wire [ 64:0] host_rtc;

	wire [ 1:0] img_mounted;
	wire        img_readonly;
	wire [63:0] img_size;
	wire [31:0] sd_lba       [2];
	wire [ 5:0] sd_blk_cnt   [2];
	wire [ 1:0] sd_rd;
	wire [ 1:0] sd_wr;
	wire [ 1:0] sd_ack;
	wire [13:0] sd_buff_addr;
	wire [ 7:0] sd_buff_dout;
	wire [ 7:0] sd_buff_din  [2];
	wire        sd_buff_wr;

	wire        ioctl_download;
	wire [15:0] ioctl_index;
	wire        ioctl_wr;
	wire [26:0] ioctl_addr;
	wire [ 7:0] ioctl_dout;

	tri [35:0] ext_bus;
	assign ext_bus[32] = 1'b0;

	// F12 is the Apple /// RESET key (Ctrl+F12 = reset, F12 alone = NMI), so
	// the framework menu moves to the MiSTer convention of Win+F12.
	hps_io #(
		.CONF_STR (CONF_STR),
		.VDNUM    (2),
		.F12KEYMOD(1)
	) hps_io_inst (
		.clk_sys           (clk_14m),
		.HPS_BUS           (HPS_BUS),
		.buttons           (hps_buttons),
		.forced_scandoubler(forced_scandoubler),
		.video_rotated     (1'b0),
		.new_vmode         (1'b0),
		.gamma_bus         (gamma_bus),
		.status            (status),
		.status_in         (status),
		.status_set        (1'b0),
		.status_menumask   (16'd0),
		.info_req          (1'b0),
		.info              (8'd0),

		.joystick_0         (joystick_0),
		.joystick_1         (joystick_1),
		.joystick_l_analog_0(joystick_analog_0),
		.joystick_l_analog_1(joystick_analog_1),
		.joystick_0_rumble  (16'd0),
		.joystick_1_rumble  (16'd0),
		.joystick_2_rumble  (16'd0),
		.joystick_3_rumble  (16'd0),
		.joystick_4_rumble  (16'd0),
		.joystick_5_rumble  (16'd0),
		.ps2_key            (ps2_key),
		.ps2_kbd_led_status (3'd0),
		.ps2_kbd_led_use    (3'd0),

		.img_mounted (img_mounted),
		.img_readonly(img_readonly),
		.img_size    (img_size),
		.sd_lba      (sd_lba),
		.sd_blk_cnt  (sd_blk_cnt),
		.sd_rd       (sd_rd),
		.sd_wr       (sd_wr),
		.sd_ack      (sd_ack),
		.sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din (sd_buff_din),
		.sd_buff_wr  (sd_buff_wr),

		.ioctl_download    (ioctl_download),
		.ioctl_index       (ioctl_index),
		.ioctl_wr          (ioctl_wr),
		.ioctl_addr        (ioctl_addr),
		.ioctl_dout        (ioctl_dout),
		.ioctl_upload_req  (1'b0),
		.ioctl_upload_index(8'd0),
		.ioctl_din         (8'd0),
		.ioctl_wait        (1'b0),
		.RTC               (host_rtc),
		.EXT_BUS           (ext_bus)
	);

	function automatic [7:0] controller_axis(input logic [7:0] analog_value, input logic negative,
											 input logic positive);
		if (negative) controller_axis = 8'h00;
		else if (positive) controller_axis = 8'hff;
		else controller_axis = analog_value ^ 8'h80;
	endfunction

	// An Apple /// joystick has two axes, a pushbutton and a toggle switch.
	// Controller 1 plugs into port B, which SOS and Business BASIC read as
	// joystick 0, or into port A with the "Joystick 1 on" option; controller 2
	// takes the other port.  Y reads higher toward the top, the direction of
	// the graphics driver's Y axis.  Button 2 flips the switch, which keeps its
	// position through a reset.
	wire [7:0] stick_x[2], stick_y[2];
	assign stick_x[0] = controller_axis(joystick_analog_0[7:0], joystick_0[1], joystick_0[0]);
	assign stick_y[0] = ~controller_axis(joystick_analog_0[15:8], joystick_0[3], joystick_0[2]);
	assign stick_x[1] = controller_axis(joystick_analog_1[7:0], joystick_1[1], joystick_1[0]);
	assign stick_y[1] = ~controller_axis(joystick_analog_1[15:8], joystick_1[3], joystick_1[2]);
	wire  [1:0] stick_button = {joystick_1[4], joystick_0[4]};
	wire  [1:0] switch_button = {joystick_1[5], joystick_0[5]};
	logic [1:0] switch_button_q = 2'b00;
	logic [1:0] stick_switch = 2'b00;
	always_ff @(posedge clk_14m) begin
		switch_button_q <= switch_button;
		stick_switch    <= stick_switch ^ (switch_button & ~switch_button_q);
	end
	wire port_b = status[10];  // the controller in port B

	// The boot ROM is not part of the bitstream.  MiSTer sends
	// games/Apple-III/boot.rom with index 0 when the core starts, and the OSD
	// "Load Boot ROM" entry (F2) can replace it at run time.  The machine is
	// held in reset, with the picture blanked, until an image has arrived.
	wire  rom_download = ioctl_download && ((ioctl_index == 16'd0) || (ioctl_index[5:0] == 6'd2));
	wire  rom_write = rom_download && ioctl_wr && (ioctl_addr < 27'd8192);
	logic rom_loaded = 1'b0;
	logic rom_download_q = 1'b0;
	always_ff @(posedge clk_14m) begin
		rom_download_q <= rom_download;
		if (rom_download_q && !rom_download) rom_loaded <= 1'b1;
	end
	wire core_reset = RESET || status[0] || hps_buttons[1] || !pll_locked || rom_download || !rom_loaded;

	// Main is the only image-format backend: all floppy mounts arrive as
	// native or converted WOZ. Converted sources are always write-protected.
	wire [1:0] disk_ready, disk_write_protect, disk_flux, disk_motors;
	wire [3:0] disk_phases;
	wire disk_write_mode, disk_write_bit, disk_write_strobe;
	wire disk_activity, disk1_active, disk2_active;

	wire        [ 7:0] core_r;
	wire        [ 7:0] core_g;
	wire        [ 7:0] core_b;
	wire               core_hblank;
	wire               core_vblank;
	wire               core_hsync;
	wire               core_vsync;
	wire signed [15:0] core_audio;

	genvar drive;
	generate
		for (drive = 0; drive < 2; drive = drive + 1) begin : woz_drives
			apple3_woz_drive woz (
				.clk           (clk_14m),
				.reset         (core_reset),
				.change        (img_mounted[drive]),
				.enabled       (1'b1),
				.image_size    (img_size),
				.image_readonly(img_readonly),
				.protect       (status[6+drive]),
				.active        (drive == 0 ? disk1_active : disk2_active),
				.motor_on      (disk_motors[drive]),
				.phases        (disk_phases),
				.write_mode    (disk_write_mode),
				.write_bit     (disk_write_bit),
				.write_strobe  (disk_write_strobe),
				.flux          (disk_flux[drive]),
				.ready         (disk_ready[drive]),
				.write_protect (disk_write_protect[drive]),
				.sd_lba        (sd_lba[drive]),
				.sd_blk_cnt    (sd_blk_cnt[drive]),
				.sd_rd         (sd_rd[drive]),
				.sd_wr         (sd_wr[drive]),
				.sd_ack        (sd_ack[drive]),
				.sd_buff_addr,
				.sd_buff_dout,
				.sd_buff_din   (sd_buff_din[drive]),
				.sd_buff_wr
			);
		end
	endgenerate

	apple3_core machine (
		.clk_14m           (clk_14m),
		.reset             (core_reset),
		.ps2_key           (ps2_key),
		// The Apple /// Plus keyboard adds a DELETE key; the rest of the
		// encoder output is the same on both machines.
		.plus_keymap       (status[8]),
		// An unopened HPS UART deasserts RTS. The stock ROM requires CTS
		// ready during its ACIA test, as with the unplugged motherboard port.
		.serial_rx         (UART_RXD),
		.serial_cts_n      (status[9] && UART_CTS),
		.serial_dsr_n      (UART_DSR),
		.serial_tx         (UART_TXD),
		.serial_rts_n      (UART_RTS),
		.serial_dtr_n      (UART_DTR),
		.host_rtc          (host_rtc),
		.joy_a_x           (stick_x[!port_b]),
		.joy_a_y           (stick_y[!port_b]),
		.joy_b_x           (stick_x[port_b]),
		.joy_b_y           (stick_y[port_b]),
		.joy_a_button      (stick_button[!port_b]),
		.joy_a_switch      (stick_switch[!port_b]),
		.joy_b_button      (stick_button[port_b]),
		.joy_b_switch      (stick_switch[port_b]),
		.rom_we            (rom_write),
		.rom_host_addr     (ioctl_addr[12:0]),
		.rom_host_data     (ioctl_dout),
		.disk_ready        (disk_ready),
		.disk_write_protect(disk_write_protect),
		.disk_flux,
		.disk_media_change (img_mounted),
		.disk_motors,
		.disk_phases,
		.disk_write_mode,
		.disk_write_bit,
		.disk_write_strobe,
		.video_r           (core_r),
		.video_g           (core_g),
		.video_b           (core_b),
		.video_hblank      (core_hblank),
		.video_vblank      (core_vblank),
		.video_hsync       (core_hsync),
		.video_vsync       (core_vsync),
		.audio             (core_audio),
		.disk_activity     (disk_activity),
		.disk1_active      (disk1_active),
		.disk2_active      (disk2_active)
	);

	// Register the video outputs in the machine-clock domain.  video_mixer
	// samples them from CLK_VIDEO on ce_pix, and the phase of the free-running
	// pixel divider relative to clk_14m is not controlled, so the crossing has
	// to close within one 57.27 MHz cycle for every phase.  Only a
	// register-to-register path can do that; the combinational pixel path was
	// measured at 34 ns.
	logic [7:0] core_r_q, core_g_q, core_b_q;
	logic core_hblank_q, core_vblank_q, core_hsync_q, core_vsync_q;
	always_ff @(posedge clk_14m) begin
		{core_r_q, core_g_q, core_b_q} <= rom_loaded ? {core_r, core_g, core_b} : 24'd0;
		{core_hblank_q, core_vblank_q, core_hsync_q, core_vsync_q} <= {
			core_hblank, core_vblank, core_hsync, core_vsync
		};
	end

	assign LED_USER  = disk_activity;
	assign AUDIO_L   = core_audio;
	assign AUDIO_R   = core_audio;
	assign AUDIO_S   = 1'b1;
	assign AUDIO_MIX = 2'b00;

	wire [2:0] video_effect = status[5:3];
	wire [2:0] scanline_level = video_effect ? video_effect - 1'b1 : 3'd0;
	wire       use_scandoubler = forced_scandoubler || (video_effect != 0);
	assign VGA_SL    = scanline_level[1:0];
	assign VIDEO_ARX = status[2] ? 13'd16 : 13'd4;
	assign VIDEO_ARY = status[2] ? 13'd9 : 13'd3;

	video_mixer #(
		.LINE_LENGTH(560),
		.GAMMA      (1)
	) video_out (
		.CLK_VIDEO  (CLK_VIDEO),
		.CE_PIXEL   (CE_PIXEL),
		.ce_pix     (ce_pix),
		.scandoubler(use_scandoubler),
		.hq2x       (video_effect == 3'd1),
		.gamma_bus  (gamma_bus),
		.R          (core_r_q),
		.G          (core_g_q),
		.B          (core_b_q),
		.HSync      (core_hsync_q),
		.VSync      (core_vsync_q),
		.HBlank     (core_hblank_q),
		.VBlank     (core_vblank_q),
		.HDMI_FREEZE(HDMI_FREEZE),
		.freeze_sync(),
		.VGA_R      (VGA_R),
		.VGA_G      (VGA_G),
		.VGA_B      (VGA_B),
		.VGA_VS     (VGA_VS),
		.VGA_HS     (VGA_HS),
		.VGA_DE     (VGA_DE)
	);

endmodule
