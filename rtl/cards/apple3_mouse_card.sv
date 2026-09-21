// Apple II Mouse Interface card (670-0030) for one Apple /// slot.
//
// The card is a 6821 PIA, a 68705P3 microcontroller and a 2 KiB firmware
// EPROM. The PIA sits in the slot's $C0nx aperture. Port A is the byte path
// to the microcontroller's port A, PB4-PB7 are the handshake lines on its
// port C, and PB1-PB3 choose which 256-byte page of the EPROM shows at
// $Cn00. The microcontroller counts the mouse's quadrature pulses on its
// port B, keeps the position and clamps, and pulls the slot's IRQ with PB6.
//
// SOS's mouse driver never calls the EPROM: it checks two signature bytes
// there and then runs the microcontroller's command protocol through the
// PIA itself. The EPROM's 6502 code is for Apple II programs, which find it
// in Apple II emulation mode.
//
// Both ROMs are built in, as they are in the Apple II MiSTer core: the EPROM
// (341-0270-C) and the microcontroller's program (341-0269). The wiring
// follows that core's card by Gyorgy Szombathelyi and MAME's
// a2bus/mouse.cpp.
`timescale 1ns / 1ps
module apple3_mouse_card #(
	parameter EPROM_FILE = "rtl/cards/apple3_mouse_eprom.hex",
	parameter MCU_FILE   = "rtl/cards/apple3_mouse_mcu.hex"
) (
	input logic clk,
	input logic reset,
	input logic cycle,

	// Slot bus (docs/SLOTS.md); the card decodes only the page offset.
	input  logic [7:0] addr,
	input  logic       cpu_read,
	input  logic [7:0] data_in,
	input  logic       device_select,
	input  logic       io_select,
	output logic [7:0] data_out,
	output logic       data_oe,
	output logic       irq_n,

	// MiSTer's mouse report: bit 24 toggles with each one, [15:8] and
	// [23:16] are the X and Y movement with their signs in bits 4 and 5, and
	// bit 0 is the left button. Y counts upward.
	input logic [24:0] ps2_mouse,
	// Counts for eight units of host movement: 0 one, 1 two, 2 four, 3 eight.
	input logic [ 1:0] speed
);
	// Most of a report's movement that can wait for the microcontroller.
	localparam logic signed [10:0] BACKLOG_MAX = 11'sd255;
	localparam logic signed [10:0] BACKLOG_MIN = -11'sd256;

	(* ramstyle = "M10K" *)logic [7:0] rom    [2048];
	(* ramstyle = "M10K" *)logic [7:0] mcu_rom[2048];
	logic [7:0] rom_q, mcu_rom_q;
	logic [10:0] mcu_rom_addr;

	logic [7:0] pia_data, pia_pa_out, pia_pb_out;
	logic [7:0] mcu_pa_out, mcu_pb_in, mcu_pb_out;
	logic [ 3:0] mcu_pc_out;
	logic [12:0] mcu_addr;
	logic        mcu_wr;

	initial begin
		$readmemh(EPROM_FILE, rom);
		$readmemh(MCU_FILE, mcu_rom);
	end

	always_ff @(posedge clk) begin
		rom_q     <= rom[{pia_pb_out[3:1], addr}];
		mcu_rom_q <= mcu_rom[mcu_rom_addr];
	end

	assign data_oe  = !reset && cpu_read && (device_select || io_select);
	assign data_out = device_select ? pia_data : rom_q;
	assign irq_n    = mcu_pb_out[6];

	// CA1, CA2, CB1 and CB2 are not connected. PB0 is the latch the EPROM's
	// Apple II code samples to find vertical blanking; it reads low here.
	pia6821 pia (
		.clk,
		.rst     (reset),
		.cs      (device_select && cycle),
		.rw      (cpu_read),
		.addr    (addr[1:0]),
		.data_in,
		.data_out(pia_data),
		.irqa    (),
		.irqb    (),
		.pa_i    (mcu_pa_out),
		.pa_o    (pia_pa_out),
		.pa_oe   (),
		.ca1     (1'b1),
		.ca2_i   (1'b1),
		.ca2_o   (),
		.ca2_oe  (),
		.pb_i    ({mcu_pc_out, 4'b1110}),
		.pb_o    (pia_pb_out),
		.pb_oe   (),
		.cb1     (1'b1),
		.cb2_i   (1'b1),
		.cb2_o   (),
		.cb2_oe  ()
	);

	// The card's 2.0436 MHz oscillator; a seventh of 14.318 MHz is 2.0455.
	logic [2:0] mcu_divider = 3'd0;
	logic       mcu_enable = 1'b0;
	always_ff @(posedge clk) begin
		mcu_enable  <= mcu_divider == 3'd6;
		mcu_divider <= (mcu_divider == 3'd6) ? 3'd0 : mcu_divider + 3'd1;
	end

	jtframe_6805mcu mcu (
		.clk,
		.rst     (reset),
		.cen     (mcu_enable),
		.wr      (mcu_wr),
		.addr    (mcu_addr),
		.dout    (),
		.irq     (1'b0),
		.timer   (1'b1),
		.pa_in   (pia_pa_out),
		.pa_out  (mcu_pa_out),
		.pb_in   (mcu_pb_in),
		.pb_out  (mcu_pb_out),
		.pc_in   (pia_pb_out[7:4]),
		.pc_out  (mcu_pc_out),
		.rom_addr(mcu_rom_addr),
		.rom_data(mcu_rom_q),
		.rom_cs  ()
	);

	// The mouse sends each axis as a gate and a direction line, and the
	// microcontroller's main loop polls them: every gate edge is one count,
	// up or down by the direction line. Movement waits in a backlog and
	// leaves one edge at a time.
	//
	// Apple's mouse gave about 90 counts to the inch and a host mouse gives
	// ten times that, which is more than programs of the time allow for:
	// ON THREE's driver keeps three bits of a sixtieth of a second's
	// movement. So `speed` takes an eighth, a quarter, a half or all of the
	// host's movement, and the remainder waits for the next report.
	//
	// The program also reads port B for the button, in its read command and
	// in its 60 Hz timer interrupt, and those reads pass the movement lines
	// by. An edge that came and went between two polls of the main loop would
	// be lost, and its partner with it, so the lines hold each state until
	// port B has been read LOOKS times: more than can fall between two polls.
	//
	// jt6805 holds a read's address for more than one enable and takes the
	// byte on the last, so a read is over when the address moves on. Setting
	// or clearing PB6, the interrupt request, reads the port as well and
	// writes it two enables later; a read counts once READ_SETTLE enables
	// have passed without that write.
	localparam logic [1:0] LOOKS       = 2'd3;
	localparam logic [2:0] READ_SETTLE = 3'd4;

	logic signed [8:0] backlog_x, backlog_y;
	logic [2:0] eighths_x, eighths_y;
	logic button, report_q;
	logic x_gate, x_right, y_gate, y_down;
	logic       [1:0] looks;
	wire signed [8:0] report_x = {ps2_mouse[4], ps2_mouse[15:8]};
	wire signed [8:0] report_y = {ps2_mouse[5], ps2_mouse[23:16]};
	wire              port_b_access = (mcu_addr == 13'd1) && !mcu_wr;
	wire              port_b_write = (mcu_addr == 13'd1) && mcu_wr;
	logic             port_b_access_q;
	logic       [2:0] read_settle;
	wire              port_b_read = mcu_enable && (read_settle == 3'd1) && !port_b_write;
	wire              step = port_b_read && (looks == LOOKS - 2'd1);

	function automatic logic signed [8:0] toward_zero(input logic signed [8:0] value);
		if (value < 0) toward_zero = value + 9'sd1;
		else if (value > 0) toward_zero = value - 9'sd1;
		else toward_zero = value;
	endfunction

	// A report's movement in eighths of a count, with the eighths left over
	// from the last one. The shift rounds down, so they are never negative.
	function automatic logic signed [12:0] scaled(input logic signed [8:0] movement, input logic [2:0] eighths);
		scaled = (13'(movement) <<< speed) + 13'(eighths);
	endfunction

	function automatic logic signed [8:0] add_report(input logic signed [8:0] backlog,
													 input logic signed [9:0] movement);
		logic signed [10:0] sum;
		sum = 11'(backlog) + 11'(movement);
		if (sum > BACKLOG_MAX) add_report = BACKLOG_MAX[8:0];
		else if (sum < BACKLOG_MIN) add_report = BACKLOG_MIN[8:0];
		else add_report = sum[8:0];
	endfunction

	wire signed [12:0] scaled_x = scaled(report_x, eighths_x);
	wire signed [12:0] scaled_y = scaled(report_y, eighths_y);

	assign mcu_pb_in = {!button, 3'b111, y_gate, y_down, x_gate, x_right};

	always_ff @(posedge clk) begin
		report_q <= ps2_mouse[24];
		if (mcu_enable) begin
			port_b_access_q <= port_b_access;
			if (port_b_write) read_settle <= 3'd0;
			else if (port_b_access_q && !port_b_access) read_settle <= READ_SETTLE;
			else if (read_settle != 3'd0) read_settle <= read_settle - 3'd1;
		end
		if (reset) begin
			read_settle <= 3'd0;
			backlog_x   <= 9'sd0;
			backlog_y   <= 9'sd0;
			eighths_x   <= 3'd0;
			eighths_y   <= 3'd0;
			button      <= 1'b0;
			x_gate      <= 1'b0;
			x_right     <= 1'b0;
			y_gate      <= 1'b0;
			y_down      <= 1'b0;
			looks       <= 2'd0;
		end else begin
			logic signed [8:0] next_x, next_y;
			next_x = backlog_x;
			next_y = backlog_y;
			if (step) begin
				if (backlog_x != 0) begin
					x_gate  <= !x_gate;
					x_right <= backlog_x > 0;
				end
				if (backlog_y != 0) begin
					y_gate <= !y_gate;
					y_down <= backlog_y < 0;
				end
				if ((backlog_x != 0) || (backlog_y != 0)) looks <= 2'd0;
				next_x = toward_zero(backlog_x);
				next_y = toward_zero(backlog_y);
			end else if (port_b_read) looks <= looks + 2'd1;
			if (ps2_mouse[24] != report_q) begin
				button <= ps2_mouse[0];
				next_x = add_report(next_x, scaled_x[12:3]);
				next_y = add_report(next_y, scaled_y[12:3]);
				eighths_x <= scaled_x[2:0];
				eighths_y <= scaled_y[2:0];
			end
			backlog_x <= next_x;
			backlog_y <= next_y;
		end
	end
endmodule
