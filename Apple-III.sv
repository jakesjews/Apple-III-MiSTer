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

	assign LED_POWER     = 2'b00;
	assign LED_DISK      = 2'b00;
	assign BUTTONS       = 2'b00;
	assign VGA_SCALER    = 1'b0;
	assign VGA_DISABLE   = 1'b0;
	assign HDMI_FREEZE   = 1'b0;
	assign HDMI_BLACKOUT = 1'b0;

	// Status Bit Map:
	//              Upper                          Lower
	// 0         1         2         3          4         5         6
	// 01234567890123456789012345678901 23456789012345678901234567890123
	// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
	// X  XXXXXXXXXXXXXXXXXXXXXXXX
	//
	// Aspect ratio is status[122:121], where the Template keeps it.

	`include "build_id.v"
	localparam CONF_STR = {
		"Apple-III;UART19200:9600:4800:2400:1200:600:300:150:110:75:50;",
		"-;",
		"S0,WOZDSKDO PO NIB2MG,Mount Drive 1;",
		"S1,WOZDSKDO PO NIB2MG,Mount Drive 2;",
		"S2,WOZDSKDO PO NIB2MG,Mount Drive 3;",
		"S3,WOZDSKDO PO NIB2MG,Mount Drive 4;",
		"O6,Write Protect 1,Off,On;",
		"O7,Write Protect 2,Off,On;",
		"OB,Write Protect 3,Off,On;",
		"OC,Write Protect 4,Off,On;",
		"-;",
		"S4,PO HDV2MG,Mount Hard Disk 1;",
		"S5,PO HDV2MG,Mount Hard Disk 2;",
		"-;",
		"O8,Model,Apple ///,/// Plus;",
		"h0OF,Text Interlace,Off,On;",
		"ODE,Video,RGB,Color Composite,Mono Composite;",
		"H1OGH,Display,RGB Monitor,Monitor /// Green,Amber,Color TV;",
		"-;",
		"P1,System & ROM;",
		"P1-;",
		"P1OI,Memory,256K,128K;",
		"P1OJ,Video Standard,NTSC,PAL;",
		"P1-;",
		"P1O[26],Boot ROM,Apple,soshdboot;",
		"P1F2,ROMBIN,Load Boot ROM;",
		"P2,Scaling & Filters;",
		"P2-;",
		"P2O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
		"P2O[21:20],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
		"P2-;",
		"P2O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
		"h2P2O[22],Deinterlacing,Weave,Bob;",
		"P3,Hardware;",
		"P3-;",
		"P3O[23],Mouse Card,On,Off;",
		"P3O[25:24],Mouse Speed,Normal,Fast,Faster,Fastest;",
		"P3-;",
		"P3OA,Joystick 1 on,Port B,Port A;",
		"P3O9,Serial CTS,Always ready,Host RTS;",
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
	wire [ 24:0] ps2_mouse;
	wire [ 64:0] host_rtc;

	// "Video Standard" PAL is Apple's Euro system: the 50 Hz scan PROM,
	// 341-0060, at G9.  Its 14.25045 MHz crystal is not modelled; the machine
	// keeps the 14.318 MHz clock and makes 50.6 fields a second.
	wire euro = status[19];

	// The Apple /// Plus differs in its keyboard and its text interlace
	// switch, which the menu offers with that model.  The interlace PROM is a
	// 60 Hz part and no Euro version of it is known, so the switch goes with
	// NTSC.
	wire plus_model = status[8];
	wire interlace = plus_model && status[15] && !euro;

	// "Display" is the monitor on a composite output.  The XRGB pins take an
	// RGB monitor only, so the menu offers it with the other two sources.
	wire [1:0] video_source = status[14:13];
	wire       composite_source = (video_source == 2'd1) || (video_source == 2'd2);

	// S0-S3 are the Disk III drives; S4 and S5 are the block card's images.
	wire [ 5:0] img_mounted;
	wire        img_readonly;
	wire [63:0] img_size;
	wire [31:0] sd_lba       [6];
	wire [ 5:0] sd_blk_cnt   [6];
	wire [ 5:0] sd_rd;
	wire [ 5:0] sd_wr;
	wire [ 5:0] sd_ack;
	wire [13:0] sd_buff_addr;
	wire [ 7:0] sd_buff_dout;
	wire [ 7:0] sd_buff_din  [6];
	wire        sd_buff_wr;

	wire        ioctl_download;
	wire [15:0] ioctl_index;
	wire        ioctl_wr;
	wire [26:0] ioctl_addr;
	wire [ 7:0] ioctl_dout;

	tri [35:0] ext_bus;
	assign ext_bus[32] = 1'b0;

	// F12 stays the framework menu key; F2 is the Apple /// RESET key
	// (Ctrl+F2 = reset, F2 alone = NMI).
	hps_io #(
		.CONF_STR(CONF_STR),
		.VDNUM   (6)
	) hps_io_inst (
		.clk_sys           (clk_14m),
		.HPS_BUS           (HPS_BUS),
		.buttons           (hps_buttons),
		.forced_scandoubler(forced_scandoubler),
		.video_rotated     (1'b0),
		// The picture's size is the same at 50 Hz; only the frame time moves.
		.new_vmode         (euro),
		.gamma_bus         (gamma_bus),
		.status            (status),
		.status_in         (status),
		.status_set        (1'b0),
		.status_menumask   ({13'd0, interlace, !composite_source, plus_model && !euro}),
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
		.ps2_mouse          (ps2_mouse),
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

	// Apple's boot ROM and the soshdboot ROM that "Boot ROM" selects are built
	// in.  games/Apple-III/boot.rom, which MiSTer sends with index 0 when the
	// core starts, and the OSD "Load Boot ROM" entry (F2) replace Apple's until
	// the core is loaded again; the machine is held in reset while one arrives.
	wire rom_download = ioctl_download && ((ioctl_index == 16'd0) || (ioctl_index[5:0] == 6'd2));
	wire rom_write = rom_download && ioctl_wr && (ioctl_addr < 27'd8192);
	wire core_reset = RESET || status[0] || hps_buttons[1] || !pll_locked || rom_download;

	// Main is the only image-format backend: all floppy mounts arrive as
	// native or converted WOZ, with independent mount and write-protect state.
	wire [3:0] disk_ready, disk_write_protect, disk_flux, disk_motors, disk_active;
	wire [3:0] disk_protect = {status[12:11], status[7:6]};
	wire [3:0] disk_phases;
	wire disk_write_mode, disk_write_bit, disk_write_strobe;
	wire disk_activity;

	wire        [ 7:0] core_r;
	wire        [ 7:0] core_g;
	wire        [ 7:0] core_b;
	wire               core_hblank;
	wire               core_vblank;
	wire               core_hsync;
	wire               core_vsync;
	wire               core_field;
	wire        [ 3:0] core_colour;
	wire        [ 1:0] core_colour_phase;
	wire               core_colour_burst;
	wire signed [15:0] core_audio;

	genvar drive;
	generate
		for (drive = 0; drive < 4; drive = drive + 1) begin : woz_drives
			apple3_woz_drive woz (
				.clk           (clk_14m),
				.reset         (core_reset),
				.change        (img_mounted[drive]),
				.enabled       (1'b1),
				.image_size    (img_size),
				.image_readonly(img_readonly),
				.protect       (disk_protect[drive]),
				.active        (disk_active[drive]),
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

	// Slot 1 holds the virtual block-storage card, a ProDOS block-mode
	// device that SOS reaches through the Problock3 driver or the soshdboot
	// ROM. Its two drives are the hard-disk images on S4 and S5. Slot 4 holds
	// the Apple II Mouse Interface card, where SOS's mouse driver is usually
	// configured to find it. Slots 2 and 3 are empty.
	/* verilator lint_off UNUSEDSIGNAL */
	wire [15:0] slot_addr;  // the cards decode the page offset only
	wire [3:0] slot_device_select, slot_io_select;  // slots 2 and 3 are empty
	/* verilator lint_on UNUSEDSIGNAL */
	wire [7:0] slot_data_out;
	wire slot_cpu_read, slot_cycle, slot_reset;
	wire [7:0] block_data;
	wire block_oe, block_ready, block_activity;
	wire [31:0] block_lba;
	wire [1:0] block_rd, block_wr;
	wire [7:0] block_din;

	apple3_block_card block_card (
		.clk           (clk_14m),
		.reset         (slot_reset),
		.cycle         (slot_cycle),
		.addr          (slot_addr[7:0]),
		.cpu_read      (slot_cpu_read),
		.data_in       (slot_data_out),
		.device_select (slot_device_select[0]),
		.io_select     (slot_io_select[0]),
		.data_out      (block_data),
		.data_oe       (block_oe),
		.ready         (block_ready),
		.activity      (block_activity),
		.image_change  (img_mounted[5:4]),
		.image_size    (img_size),
		.image_readonly(img_readonly),
		.sd_lba        (block_lba),
		.sd_rd         (block_rd),
		.sd_wr         (block_wr),
		.sd_ack        (sd_ack[5:4]),
		.sd_buff_addr  (sd_buff_addr[8:0]),
		.sd_buff_dout,
		.sd_buff_din   (block_din),
		.sd_buff_wr
	);
	// One request is outstanding at a time, so both images share the card's
	// block number and buffer.
	assign sd_lba[4]      = block_lba;
	assign sd_lba[5]      = block_lba;
	assign sd_blk_cnt[4]  = 6'd0;
	assign sd_blk_cnt[5]  = 6'd0;
	assign sd_rd[5:4]     = block_rd;
	assign sd_wr[5:4]     = block_wr;
	assign sd_buff_din[4] = block_din;
	assign sd_buff_din[5] = block_din;

	// Like any card, the mouse card goes in or comes out with the machine
	// off: the "Mouse Card" option takes effect at the next reset.
	wire [7:0] mouse_data;
	wire mouse_oe, mouse_irq_n;
	logic mouse_installed = 1'b0;
	always_ff @(posedge clk_14m) if (slot_reset) mouse_installed <= !status[23];

	apple3_mouse_card mouse_card (
		.clk          (clk_14m),
		.reset        (slot_reset || !mouse_installed),
		.cycle        (slot_cycle),
		.addr         (slot_addr[7:0]),
		.cpu_read     (slot_cpu_read),
		.data_in      (slot_data_out),
		.device_select(slot_device_select[3]),
		.io_select    (slot_io_select[3]),
		.data_out     (mouse_data),
		.data_oe      (mouse_oe),
		.irq_n        (mouse_irq_n),
		.ps2_mouse    (ps2_mouse),
		.speed        (status[25:24])
	);

	apple3_core machine (
		.clk_14m           (clk_14m),
		.reset             (core_reset),
		.ps2_key           (ps2_key),
		// The Apple /// Plus keyboard adds a DELETE key; the rest of the
		// encoder output is the same on both machines.
		.plus_keymap       (plus_model),
		.ram_128k          (status[18]),
		.soshdboot         (status[26]),
		.interlace         (interlace),
		.euro              (euro),
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
		.slot_data_in      ({mouse_data, 16'hffff, block_data}),
		.slot_data_oe      ({mouse_oe, 2'b00, block_oe}),
		.slot_irq_n        ({mouse_irq_n, 3'b111}),
		.slot_nmi_n        (4'b1111),
		.slot_ready        ({3'b111, block_ready}),
		.slot_addr         (slot_addr),
		.slot_data_out     (slot_data_out),
		.slot_cpu_read     (slot_cpu_read),
		.slot_cycle        (slot_cycle),
		.slot_reset        (slot_reset),
		.slot_device_select(slot_device_select),
		.slot_io_select    (slot_io_select),
		.slot_io_strobe    (),
		.slot_rom_deselect (),
		.slot_bus_conflict (),
		.rom_we            (rom_write),
		.rom_host_addr     (ioctl_addr[12:0]),
		.rom_host_data     (ioctl_dout),
		.disk_ready        (disk_ready),
		.disk_write_protect(disk_write_protect),
		.disk_flux,
		.disk_media_change (img_mounted[3:0]),
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
		.video_field       (core_field),
		.video_colour      (core_colour),
		.video_colour_phase(core_colour_phase),
		.video_colour_burst(core_colour_burst),
		.audio             (core_audio),
		.disk_activity     (disk_activity),
		.disk_active
	);

	// The "Video" option chooses the monitor: the XRGB lines, the NTSC colour
	// output or the B/W jack.  A reserved value shows RGB.  "Display" chooses
	// what a composite output is plugged into.
	//
	// The monitor's outputs are registers in the machine-clock domain.
	// video_mixer samples them from CLK_VIDEO on ce_pix, and the phase of the
	// free-running pixel divider relative to clk_14m is not controlled, so the
	// crossing has to close within one 57.27 MHz cycle for every phase.  Only a
	// register-to-register path can do that; the combinational pixel path was
	// measured at 34 ns.
	wire [7:0] core_r_q, core_g_q, core_b_q;
	wire core_hblank_q, core_vblank_q, core_hsync_q, core_vsync_q;
	apple3_composite monitor (
		.clk         (clk_14m),
		.source      (video_source),
		.monitor     (status[17:16]),
		.colour      (core_colour),
		.colour_phase(core_colour_phase),
		.colour_burst(core_colour_burst),
		.rgb_in      ({core_r, core_g, core_b}),
		.hblank_in   (core_hblank),
		.vblank_in   (core_vblank),
		.hsync_in    (core_hsync),
		.vsync_in    (core_vsync),
		.red         (core_r_q),
		.green       (core_g_q),
		.blue        (core_b_q),
		.hblank      (core_hblank_q),
		.vblank      (core_vblank_q),
		.hsync       (core_hsync_q),
		.vsync       (core_vsync_q)
	);

	// The field changes as vertical blanking begins, so the scaler finds it
	// settled at each field's first line.  F1 marks the lower field, the one
	// whose sync comes half a line late and whose lines the scaler weaves
	// into the odd rows; with the switch off the flag rests low and the
	// picture is progressive.
	logic field_q = 1'b0;
	always_ff @(posedge clk_14m) field_q <= interlace && !core_field;
	assign VGA_F1 = field_q;

	// "Deinterlacing" is the scaler's.  Weave shows the two fields as one
	// 384-line frame; Bob shows each as it arrives, its lines doubled and the
	// lower field half a line down, so merged pages 1 and 2 alternate as they
	// do on a tube instead of combining.  The menu offers it while the switch
	// is on, and it changes nothing on the analog output.
	assign HDMI_BOB_DEINT = status[22];

	assign LED_USER  = disk_activity || block_activity;
	assign AUDIO_L   = core_audio;
	assign AUDIO_R   = core_audio;
	assign AUDIO_S   = 1'b1;
	assign AUDIO_MIX = 2'b00;

	wire [2:0] video_effect = status[5:3];
	wire [2:0] scanline_level = video_effect ? video_effect - 1'b1 : 3'd0;
	wire       use_scandoubler = forced_scandoubler || (video_effect != 0);
	assign VGA_SL = scanline_level[1:0];

	// Aspect ratio and integer scaling are the framework's.  video_freak
	// sizes the picture by the lines between vertical syncs, which is one
	// field; the scaler makes 384 lines of two of them, woven or bobbed, so
	// with the interlace switch on it is shown one sync in two and scales the
	// frame.
	wire [1:0] aspect = status[122:121];
	wire       mixer_de;
	video_freak video_freak (
		.CLK_VIDEO  (CLK_VIDEO),
		.CE_PIXEL   (CE_PIXEL),
		.VGA_VS     (VGA_VS && !VGA_F1),
		.HDMI_WIDTH (HDMI_WIDTH),
		.HDMI_HEIGHT(HDMI_HEIGHT),
		.VGA_DE     (VGA_DE),
		.VIDEO_ARX  (VIDEO_ARX),
		.VIDEO_ARY  (VIDEO_ARY),
		.VGA_DE_IN  (mixer_de),
		.ARX        ((aspect == 2'd0) ? 12'd4 : {10'd0, aspect - 2'd1}),
		.ARY        ((aspect == 2'd0) ? 12'd3 : 12'd0),
		.CROP_SIZE  (12'd0),
		.CROP_OFF   (5'd0),
		.SCALE      ({1'b0, status[21:20]})
	);

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
		.VGA_DE     (mixer_de)
	);

endmodule
