// Apple /// computer core: CPU, MMU, RAM/ROM, VIAs, motherboard I/O, video,
// keyboard, clock, sound, and floppy-controller integration.

module apple3_core #(
	parameter         ROM_INIT_FILE  = "",
	parameter integer ROM_INIT_START = 4096,
	parameter integer RAM_BANKS      = 8
) (
	input logic        clk_14m,
	input logic        reset,
	input logic [10:0] ps2_key,
	input logic        plus_keymap,
	input logic [64:0] host_rtc,
	input logic [ 7:0] joy_a_x,
	input logic [ 7:0] joy_a_y,
	input logic [ 7:0] joy_b_x,
	input logic [ 7:0] joy_b_y,
	input logic        joy_a_button,
	input logic        joy_a_switch,
	input logic        joy_b_button,
	input logic        joy_b_switch,

	input  logic serial_rx,
	input  logic serial_cts_n,
	input  logic serial_dsr_n,
	output wire  serial_tx,
	output wire  serial_rts_n,
	output wire  serial_dtr_n,

	input logic        rom_we,
	input logic [12:0] rom_host_addr,
	input logic [ 7:0] rom_host_data,

	input  logic [1:0] disk_ready,
	input  logic [1:0] disk_write_protect,
	input  logic [1:0] disk_flux,
	input  logic [1:0] disk_media_change,
	output wire  [3:0] disk_phases,
	output wire        disk_write_mode,
	disk_write_bit,
	disk_write_strobe,
	output wire  [1:0] disk_motors,

	output logic        [ 7:0] video_r,
	output logic        [ 7:0] video_g,
	output logic        [ 7:0] video_b,
	output logic               video_hblank,
	output logic               video_vblank,
	output logic               video_hsync,
	output logic               video_vsync,
	output logic signed [15:0] audio,
	output logic               disk_activity,
	output logic               disk1_active,
	output logic               disk2_active,

	output logic [15:0] debug_pc,
	output logic [15:0] debug_cpu_addr,
	output logic [ 7:0] debug_environment,
	output logic [ 7:0] debug_zero_page,
	output logic [ 7:0] debug_bank,
	output logic [ 3:0] debug_video_mode,
	output logic        debug_cpu_enable,
	output logic        debug_cpu_sync,
	output logic        debug_cpu_rwn,
	output logic [ 7:0] debug_cpu_din,
	output logic [ 7:0] debug_cpu_dout,
	output logic [ 7:0] debug_e_pa_o,
	output logic [ 7:0] debug_e_pa_ddr,
	output logic [ 7:0] debug_a,
	output logic [ 7:0] debug_x,
	output logic [ 7:0] debug_y,
	output logic [ 7:0] debug_sp,
	output logic [ 7:0] debug_p,
	output logic [18:0] debug_ram_byte_addr,
	output logic        debug_ram_write
);

	logic        machine_reset;
	logic        cpu_rwn;
	logic        cpu_sync;
	logic [15:0] cpu_addr;
	logic [ 7:0] cpu_din;
	logic [ 7:0] cpu_dout;
	logic [63:0] cpu_regs;
	logic        cpu_enable;
	logic        cpu_irq_n;
	logic        cpu_nmi_n;

	logic [7:0] d_pa_o, d_pa_ddr, d_pa_i;
	logic [7:0] d_pb_o, d_pb_ddr, d_pb_i;
	logic [7:0] e_pa_o, e_pa_ddr, e_pa_i;
	logic [7:0] e_pb_o, e_pb_ddr, e_pb_i;
	logic [7:0] via_d_data, via_e_data;
	logic via_d_irq, via_e_irq;
	logic via_d_cb1_out, via_d_cb1_drive, via_d_cb2_out, via_d_cb2_drive;
	logic margin_switch, serial_clock;
	logic via_rising, via_falling;
	logic native_mode;
	logic [7:0] environment, zero_page, bank_register;
	logic [7:0] e_pa_external;

	logic [18:0] ram_byte_addr;
	logic [17:0] ram_word_addr;
	logic ram_lane, ram_select, ram_read, ram_write_allowed;
	logic [15:0] ram_q;
	logic [7:0] ram_cpu_data, sister_data;
	logic [17:0] video_ram_addr;
	logic [15:0] video_ram_q;
	logic        rom_read;
	logic [12:0] rom_addr;
	logic [ 7:0] rom_q;
	logic io_select, via_d_select, via_e_select;
	logic       extended_active;
	logic [7:0] extended_bank;

	logic [9:0] h_count;
	logic [8:0] v_count;
	logic [6:0] h_state;
	logic [3:0] state_dot;
	logic frame_tick, timing_hblank, timing_vblank;
	logic display_slot, refresh_slot, character_slot, pixel_enable;
	logic peripheral_cycle;

	logic [7:0] key_code;
	logic key_strobe, any_key_down, shift_key, control_key, alpha_lock;
	logic open_apple, solid_apple, reset_key, keyboard_data_ready;
	logic clear_key_strobe;

	logic [7:0] io_data, rtc_data, disk_data, acia_data;
	logic [3:0] video_mode;
	logic smooth_scroll, character_write;
	logic external_select, serial_enable;
	logic [2:0] analog_select;
	logic       speaker;
	logic rtc_read, rtc_write, rtc_irq;
	logic [4:0] rtc_addr;
	logic disk_strobe, acia_read, acia_write, acia_irq;

	logic [3:0] motor_phase;
	logic       side_two;
	logic d1_active, d2_active, d1_motor_on, d2_motor_on;
	logic d1_io_active, d2_io_active;
	logic       clk_2m;
	logic       phase_zero;
	logic [5:0] dac_value;

	// The VIA's PA read path samples its input pins even for output bits.  Feed
	// the resolved pin level back to the VIA so read/modify/write instructions
	// (the boot ROM uses INC $FFEF to select RAM banks) see driven outputs.
	assign d_pb_i      = 8'hff;
	assign environment = (d_pa_o & d_pa_ddr) | ~d_pa_ddr;
	assign d_pa_i      = environment;
	assign zero_page   = (d_pb_o & d_pb_ddr) | ~d_pb_ddr;

	assign native_mode   = !(e_pa_ddr[6] && !e_pa_o[6]);
	assign e_pa_external = {cpu_irq_n, !solid_apple, 2'b11, 4'hf};
	assign e_pb_i        = {1'b1, (timing_hblank || timing_vblank), 6'h3f};
	assign bank_register = (e_pa_o & e_pa_ddr) | (e_pa_external & ~e_pa_ddr);
	assign e_pa_i        = bank_register;

	assign machine_reset = reset || (environment[4] && reset_key && control_key);
	assign cpu_irq_n = !(via_d_irq || via_e_irq || acia_irq);
	assign cpu_nmi_n = !(environment[4] && reset_key && !control_key);
	assign peripheral_cycle = via_d_select || via_e_select ||
		(io_select && ((cpu_addr[7:4] == 4'h7) ||
					   ((cpu_addr[7:0] >= 8'hf0) && (cpu_addr[7:0] <= 8'hf3))));

	assign ram_cpu_data = ram_lane ? ram_q[15:8] : ram_q[7:0];
	assign sister_data  = ram_lane ? ram_q[7:0] : ram_q[15:8];

	always_comb begin
		if (!cpu_rwn) cpu_din = cpu_dout;
		else if (via_d_select) cpu_din = via_d_data;
		else if (via_e_select) cpu_din = via_e_data;
		else if (io_select) cpu_din = io_data;
		else if (rom_read) cpu_din = rom_q;
		else if (ram_read) cpu_din = ram_cpu_data;
		else cpu_din = 8'hff;

		dac_value = (e_pb_o[5:0] & e_pb_ddr[5:0]) | (6'h20 & ~e_pb_ddr[5:0]);
		audio     = $signed({1'b0, dac_value, 9'b000000000}) - 16'sd16384 + (speaker ? 16'sd4096 : 16'sd0);
	end

	assign phase_zero = (state_dot >= 4'd7);

	t65_wrapper cpu (
		.clk        (clk_14m),
		.reset_n    (!machine_reset),
		.enable     (cpu_enable),
		.irq_n      (cpu_irq_n),
		.nmi_n      (cpu_nmi_n),
		.data_in    (cpu_din),
		.data_out   (cpu_dout),
		.address    (cpu_addr),
		.read_nwrite(cpu_rwn),
		.sync       (cpu_sync),
		.regs       (cpu_regs)
	);

	apple3_timing timing (
		.clk_14m,
		.slow_mode    (environment[7]),
		.screen_enable(environment[5]),
		.peripheral_cycle,
		.ram_cycle    (ram_select),
		.cpu_enable,
		.via_rising,
		.via_falling,
		.q3           (clk_2m),
		.pixel_enable,
		.hblank       (timing_hblank),
		.vblank       (timing_vblank),
		.display_slot,
		.refresh_slot,
		.character_slot,
		.h_count,
		.v_count,
		.h_state,
		.state_dot,
		.frame_tick
	);

	apple3_mmu #(
		.RAM_BANKS(RAM_BANKS)
	) mmu (
		.cpu_addr,
		.cpu_read(cpu_rwn),
		.environment,
		.zero_page,
		.bank_register,
		.native_mode,
		.extended_active,
		.extended_bank,
		.ram_byte_addr,
		.ram_word_addr,
		.ram_lane,
		.ram_select,
		.ram_read,
		.ram_write_allowed,
		.rom_read,
		.rom_addr,
		.io_select,
		.via_d_select,
		.via_e_select
	);

	apple3_ram #(
		.WORD_ADDRESS_BITS(14 + $clog2(RAM_BANKS))
	) ram (
		.clk       (clk_14m),
		.cpu_addr  (ram_word_addr),
		.cpu_lane  (ram_lane),
		.cpu_we    (cpu_enable && ram_write_allowed),
		.cpu_din   (cpu_dout),
		.cpu_q     (ram_q),
		.video_addr(video_ram_addr),
		.video_q   (video_ram_q)
	);

	apple3_rom #(
		.INIT_FILE (ROM_INIT_FILE),
		.INIT_START(ROM_INIT_START)
	) rom (
		.clk      (clk_14m),
		.addr     (rom_addr),
		.q        (rom_q),
		.host_we  (rom_we),
		.host_addr(rom_host_addr),
		.host_data(rom_host_data)
	);

	apple3_extaddr extended_addressing (
		.clk         (clk_14m),
		.reset       (machine_reset),
		.cycle_strobe(cpu_enable),
		.sync        (cpu_sync),
		.cpu_read    (cpu_rwn),
		.cpu_addr,
		.zero_page,
		.sister_data,
		.active      (extended_active),
		.bank        (extended_bank)
	);

	via6522 via_d (
		.clock   (clk_14m),
		.rising  (via_rising),
		.falling (via_falling),
		.reset   (machine_reset),
		.addr    (cpu_addr[3:0]),
		.wen     (via_d_select && !cpu_rwn),
		.ren     (via_d_select && cpu_rwn),
		.data_in (cpu_dout),
		.data_out(via_d_data),
		.phi2_ref(),
		.port_a_o(d_pa_o),
		.port_a_t(d_pa_ddr),
		.port_a_i(d_pa_i),
		.port_b_o(d_pb_o),
		.port_b_t(d_pb_ddr),
		.port_b_i(d_pb_i),
		.ca1_i   (1'b1),
		.ca2_o   (),
		.ca2_i   (margin_switch),
		.ca2_t   (),
		.cb1_o   (via_d_cb1_out),
		.cb1_i   (serial_clock),
		.cb1_t   (via_d_cb1_drive),
		.cb2_o   (via_d_cb2_out),
		.cb2_i   (1'b1),
		.cb2_t   (via_d_cb2_drive),
		.irq     (via_d_irq)
	);

	via6522 via_e (
		.clock   (clk_14m),
		.rising  (via_rising),
		.falling (via_falling),
		.reset   (machine_reset),
		.addr    (cpu_addr[3:0]),
		.wen     (via_e_select && !cpu_rwn),
		.ren     (via_e_select && cpu_rwn),
		.data_in (cpu_dout),
		.data_out(via_e_data),
		.phi2_ref(),
		.port_a_o(e_pa_o),
		.port_a_t(e_pa_ddr),
		.port_a_i(e_pa_i),
		.port_b_o(e_pb_o),
		.port_b_t(e_pb_ddr),
		.port_b_i(e_pb_i),
		.ca1_i   (!rtc_irq),
		.ca2_o   (),
		.ca2_i   (!keyboard_data_ready),
		.ca2_t   (),
		.cb1_o   (),
		.cb1_i   (timing_vblank),
		.cb1_t   (),
		.cb2_o   (),
		.cb2_i   (timing_vblank),
		.cb2_t   (),
		.irq     (via_e_irq)
	);

	apple3_keyboard keyboard (
		.clk         (clk_14m),
		.reset       (reset),
		.ps2_key,
		.clear_strobe(clear_key_strobe),
		.plus_keymap,
		.key_code,
		.strobe      (key_strobe),
		.any_key_down,
		.shift       (shift_key),
		.control     (control_key),
		.alpha_lock,
		.open_apple,
		.solid_apple,
		.reset_key,
		.data_ready  (keyboard_data_ready)
	);

	apple3_io io (
		.clk          (clk_14m),
		.reset        (machine_reset),
		.cycle_strobe (cpu_enable),
		.select       (io_select),
		.cpu_read     (cpu_rwn),
		.addr         (cpu_addr[7:0]),
		.rtc_register (zero_page[4:0]),
		.key_code,
		.key_strobe,
		.any_key_down,
		.shift        (shift_key),
		.control_key,
		.alpha_lock,
		.open_apple,
		.solid_apple,
		.clear_key_strobe,
		.joy_a_x,
		.joy_a_y,
		.joy_b_x,
		.joy_b_y,
		.joy_a_button,
		.joy_a_switch,
		.joy_b_button,
		.joy_b_switch,
		.via_cb1_drive(via_d_cb1_drive),
		.via_cb1_out  (via_d_cb1_out),
		.via_cb2_drive(via_d_cb2_drive),
		.via_cb2_out  (via_d_cb2_out),
		.slot1_irq_n  (1'b1),
		.slot2_irq_n  (1'b1),
		.rtc_data,
		.disk_data,
		.acia_data,
		.rtc_read,
		.rtc_write,
		.rtc_addr,
		.disk_strobe,
		.acia_read,
		.acia_write,
		.data_out     (io_data),
		.video_mode,
		.smooth_scroll,
		.character_write,
		.external_select,
		.serial_enable,
		.analog_select,
		.margin_switch,
		.serial_clock,
		.speaker
	);

	apple3_rtc rtc (
		.clk         (clk_14m),
		.reset       (machine_reset),
		.host_rtc,
		.read_strobe (rtc_read),
		.write_strobe(rtc_write),
		.addr        (rtc_addr),
		.data_in     (cpu_dout),
		.data_out    (rtc_data),
		.irq         (rtc_irq)
	);

	apple3_acia acia (
		.clk         (clk_14m),
		.reset       (machine_reset),
		.read_strobe (acia_read),
		.write_strobe(acia_write),
		.addr        (cpu_addr[1:0]),
		.data_in     (cpu_dout),
		.rx          (serial_rx),
		.cts_n       (serial_cts_n),
		.dsr_n       (serial_dsr_n),
		// MiSTer's HPS UART has no separate carrier input; the link is local.
		.dcd_n       (1'b0),
		.data_out    (acia_data),
		.tx          (serial_tx),
		.rts_n       (serial_rts_n),
		.dtr_n       (serial_dtr_n),
		.irq         (acia_irq)
	);

	assign disk_phases = motor_phase;
	apple3_disk disk (
		.clk_14m,
		.clk_2m,
		.phase_zero,
		.reset         (machine_reset),
		.select        (io_select && ((cpu_addr[7:4] == 4'hd) || (cpu_addr[7:4] == 4'he))),
		.cycle_strobe  (disk_strobe),
		.cpu_read      (cpu_rwn),
		.addr          (cpu_addr[7:0]),
		.data_in       (cpu_dout),
		.disk_ready,
		.write_protect (disk_write_protect),
		.bitstream_flux(disk_flux),
		.media_change  (disk_media_change),
		.native_mode,
		.write_mode    (disk_write_mode),
		.write_bit     (disk_write_bit),
		.write_strobe  (disk_write_strobe),
		.data_out      (disk_data),
		.motor_phase,
		.side_two,
		.d1_active,
		.d2_active,
		.d1_motor_on,
		.d2_motor_on,
		.d1_io_active,
		.d2_io_active
	);

	apple3_video video (
		.clk          (clk_14m),
		.reset        (machine_reset),
		.h_count,
		.v_count,
		.h_state,
		.state_dot,
		.frame_tick,
		.screen_enable(environment[5]),
		.native_mode,
		.video_mode,
		.smooth_enable(smooth_scroll),
		.smooth_offset(motor_phase[2:0]),
		.character_write,
		.character_slot,
		.ram_addr     (video_ram_addr),
		.ram_q        (video_ram_q),
		.red          (video_r),
		.green        (video_g),
		.blue         (video_b),
		.hblank       (video_hblank),
		.vblank       (video_vblank),
		.hsync        (video_hsync),
		.vsync        (video_vsync)
	);

	assign disk_activity       = d1_active || d2_active;
	assign disk_motors         = {d2_motor_on, d1_motor_on};
	assign disk1_active        = d1_active;
	assign disk2_active        = d2_active;
	assign debug_pc            = cpu_regs[63:48];
	assign debug_cpu_addr      = cpu_addr;
	assign debug_environment   = environment;
	assign debug_zero_page     = zero_page;
	assign debug_bank          = bank_register;
	assign debug_video_mode    = video_mode;
	assign debug_cpu_enable    = cpu_enable;
	assign debug_cpu_sync      = cpu_sync;
	assign debug_cpu_rwn       = cpu_rwn;
	assign debug_cpu_din       = cpu_din;
	assign debug_cpu_dout      = cpu_dout;
	assign debug_e_pa_o        = e_pa_o;
	assign debug_e_pa_ddr      = e_pa_ddr;
	assign debug_a             = cpu_regs[7:0];
	assign debug_x             = cpu_regs[15:8];
	assign debug_y             = cpu_regs[23:16];
	assign debug_p             = cpu_regs[31:24];
	assign debug_sp            = cpu_regs[39:32];
	assign debug_ram_byte_addr = ram_byte_addr;
	assign debug_ram_write     = cpu_enable && ram_write_allowed;

endmodule
