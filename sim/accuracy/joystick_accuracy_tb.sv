`timescale 1ns / 1ps

// Joystick A/D converter and switches against the 9708/MB4053 data sheet and
// the motherboard schematic (050-0039-H sheets 5 and 8).  Times are in master
// clocks; sim/joystick checks the software methods on the whole machine.
module joystick_accuracy_tb;
	// C15 = 0.01 uF discharged by (12 V - 2.264 V) / 1.2 Mohm: 17,648 clocks per volt.
	localparam integer CLOCKS_PER_VOLT = 17648;
	localparam integer GROUND          = 430;
	localparam integer REFERENCE       = GROUND + 39959;  // VREF, 2.264 V
	localparam integer CLAMP           = GROUND + 52944;  // VCC - 2 V
	localparam integer CHARGE_RATE     = 20;
	localparam integer FLOOR           = -7942;
	localparam integer CHARGE_500US    = 7159;            // the Service Reference Manual's minimum charge

	logic clk = 0, reset = 1, cycle_strobe = 0, select = 1, cpu_read = 1;
	logic [7:0] addr = 0;
	logic [4:0] rtc_register = 0;
	logic [7:0] key_code = 0;
	logic key_strobe = 0, any_key_down = 0, shift = 0, control_key = 0;
	logic alpha_lock = 0, open_apple = 0, solid_apple = 0;
	logic [7:0] joy_a_x = 0, joy_a_y = 0, joy_b_x = 0, joy_b_y = 0;
	logic joy_a_button = 0, joy_a_switch = 0, joy_b_button = 0, joy_b_switch = 0;
	logic via_cb1_drive = 0, via_cb1_out = 0, via_cb2_drive = 0, via_cb2_out = 0;
	logic slot1_irq_n = 1, slot2_irq_n = 1;
	logic [7:0] rtc_data = 0, disk_data = 0, acia_data = 0;
	wire clear_key_strobe, rtc_read, rtc_write, disk_strobe, acia_read, acia_write;
	wire [4:0] rtc_addr;
	wire [7:0] data_out;
	wire [3:0] video_mode;
	wire smooth_scroll, character_write, external_select, serial_enable, speaker;
	wire margin_switch, serial_clock;
	wire    [2:0] analog_select;
	integer       failures = 0;

	apple3_io dut (.*);
	always #35 clk = ~clk;

	task automatic access (input logic [7:0] a);
		begin
			addr         = a;
			cycle_strobe = 1;
			@(posedge clk);
			#1;
			cycle_strobe = 0;
		end
	endtask

	task automatic expect_bit7(input logic [7:0] a, input logic want, input string what);
		begin
			addr = a;
			#1;
			if (data_out[7] !== want) begin
				$display("FAIL %s: $C0%02x bit 7 = %b", what, a, data_out[7]);
				failures = failures + 1;
			end
		end
	endtask

	task automatic select_channel(input integer channel);
		begin
			access (channel[0] ? 8'h59 : 8'h58);
			access (channel[1] ? 8'h5f : 8'h5e);
			access (channel[2] ? 8'h5b : 8'h5a);
		end
	endtask

	task automatic wait_clocks(input integer n);
		begin
			repeat (n) @(posedge clk);
			#1;
		end
	endtask

	// Count clocks from the access that sets PDLEN until RAMP STOP falls.
	task automatic count_ramp(input integer start, output integer clocks);
		begin
			addr = 8'h66;
			#1 clocks = start;
			while (data_out[7] && clocks < 200000) begin
				@(posedge clk);
				#1 clocks = clocks + 1;
			end
		end
	endtask

	task automatic convert(input integer channel, input integer charge, output integer clocks);
		begin
			select_channel(channel);
			access (8'h5c);
			wait_clocks(charge);
			access (8'h5d);
			count_ramp(1, clocks);
		end
	endtask

	task automatic expect_near(input string what, input integer got, input integer want, input integer slack);
		if (got < want - slack || got > want + slack) begin
			$display("FAIL %s: %0d clocks, expected %0d +/- %0d", what, got, want, slack);
			failures = failures + 1;
		end
	endtask

	// 8 D VIA ticks of 912/65 clocks per step: 112.25 clocks.
	function automatic integer stick_clocks(input integer position);
		stick_clocks = position * 112 + position / 4;
	endfunction

	integer t, t0, full, p;
	initial begin
		repeat (2) @(posedge clk);
		#1 reset = 0;

		// Reset leaves PDLEN low with ground selected, so a discharged C15 charges
		// past the comparator threshold within about 28 us.
		expect_bit7(8'h66, 1'b0, "RAMP STOP with C15 discharged");
		wait_clocks((-FLOOR) / CHARGE_RATE + 2);
		expect_bit7(8'h66, 1'b1, "RAMP STOP after charging ground");

		// Full conversions of the fixed inputs.
		convert(0, CHARGE_500US, t);
		expect_near("ground", t, GROUND, 1);
		convert(7, CHARGE_500US, t);
		expect_near("reference", t, REFERENCE, 1);
		expect_near("reference in mV", (t - GROUND) * 1000 / CLOCKS_PER_VOLT, 2264, 1);
		convert(5, CHARGE_500US, t);
		expect_near("clock battery", t, CLAMP, 1);
		convert(6, CHARGE_500US, t);
		expect_near("no connection", t, CLAMP, 1);

		// Joystick positions are linear, 8 VIA ticks per step, from 354 ticks:
		// SOS's 360-tick offset less its timer start and polling delays.
		convert(1, CHARGE_500US, t0);
		expect_near("joystick window start", t0, 354 * 912 / 65, 14);
		for (p = 0; p < 256; p = p + 17) begin
			joy_b_x = p[7:0];
			convert(1, CHARGE_500US, t);
			expect_near($sformatf("port B X at %0d", p), t - t0, stick_clocks(p), 1);
		end
		joy_b_x = 8'h10;
		joy_b_y = 8'h40;
		joy_a_x = 8'h80;
		joy_a_y = 8'hf0;
		convert(1, CHARGE_500US, t);
		expect_near("channel 1 is port B X", t - t0, stick_clocks(8'h10), 1);
		convert(2, CHARGE_500US, t);
		expect_near("channel 2 is port B Y", t - t0, stick_clocks(8'h40), 1);
		convert(3, CHARGE_500US, t);
		expect_near("channel 3 is port A X", t - t0, stick_clocks(8'h80), 1);
		convert(4, CHARGE_500US, t);
		expect_near("channel 4 is port A Y", t - t0, stick_clocks(8'hf0), 1);

		// A short charge from a discharged capacitor reads low.  Acquisition is
		// about twenty times as fast as the ramp, so 155 us reaches full scale.
		joy_b_x = 8'hff;
		convert(1, CHARGE_500US, full);
		wait_clocks(40000);
		convert(1, 700, t);
		expect_near("700-clock charge", t, FLOOR + 700 * CHARGE_RATE, 25);
		wait_clocks(40000);
		convert(1, 1400, t);
		expect_near("1400-clock charge", t, FLOOR + 1400 * CHARGE_RATE, 25);
		wait_clocks(40000);
		convert(1, 2220, t);
		expect_near("155 us charge", t, full, 1);

		// The input is sampled only while PDLEN is low: a channel change after
		// the ramp starts has no effect.
		joy_b_x = 8'hc0;
		joy_b_y = 8'h20;
		select_channel(1);
		access (8'h5c);
		wait_clocks(CHARGE_500US);
		access (8'h5d);
		select_channel(2);
		count_ramp(4, t);
		expect_near("channel change during the ramp", t - t0, stick_clocks(8'hc0), 1);

		// A lower input during the charge: C15 falls only at the ramp rate.
		joy_b_x = 8'hff;
		convert(1, CHARGE_500US, full);
		select_channel(1);
		access (8'h5c);
		wait_clocks(CHARGE_500US);
		select_channel(0);
		wait_clocks(CHARGE_500US);
		access (8'h5d);
		count_ramp(1, t);
		expect_near("settling down to ground", t, full - CHARGE_500US - 3, 1);

		// RAMP STOP is high through the charge and the ramp and low afterwards.
		select_channel(3);
		access (8'h5c);
		wait_clocks(CHARGE_500US);
		expect_bit7(8'h66, 1'b1, "RAMP STOP while charged");
		access (8'h5d);
		count_ramp(1, t);
		wait_clocks(100);
		expect_bit7(8'h66, 1'b0, "RAMP STOP after the ramp");

		// Reset clears PDLEN and the channel latch but not the capacitor.
		select_channel(7);
		access (8'h5c);
		wait_clocks(CHARGE_500US);
		reset = 1;
		wait_clocks(2);
		reset = 0;
		if (analog_select !== 3'd0) begin
			$display("FAIL reset kept channel %0d", analog_select);
			failures = failures + 1;
		end
		access (8'h5d);
		count_ramp(1, t);
		expect_near("reference charge through a reset", t, REFERENCE - 2, 1);

		// Port B's switch and button at $C060 and $C062; port A's button at $C061
		// and the D VIA's CA2, its switch at $C063 and CB1.
		joy_a_button = 1;
		joy_a_switch = 0;
		joy_b_button = 0;
		joy_b_switch = 1;
		expect_bit7(8'h60, 1, "port B switch");
		expect_bit7(8'h61, 1, "port A button");
		expect_bit7(8'h62, 0, "port B button");
		expect_bit7(8'h63, 0, "port A switch");
		if (margin_switch !== 1 || serial_clock !== 0) begin
			$display("FAIL CA2/CB1 lines");
			failures = failures + 1;
		end
		joy_a_button = 0;
		joy_a_switch = 1;
		joy_b_button = 1;
		joy_b_switch = 0;
		expect_bit7(8'h68, 0, "port B switch at $C068");
		expect_bit7(8'h69, 0, "port A button at $C069");
		expect_bit7(8'h6a, 1, "port B button at $C06A");
		expect_bit7(8'h6b, 1, "port A switch at $C06B");
		if (margin_switch !== 0 || serial_clock !== 1) begin
			$display("FAIL CA2/CB1 lines released");
			failures = failures + 1;
		end

		// ENSEL cuts port A's switch off SW3/SCO and drives AXCO onto Y1/XCO.
		joy_a_switch = 0;
		access (8'hdd);
		expect_bit7(8'h63, 1, "SW3/SCO floating with ENSEL");
		via_cb1_drive = 1;
		via_cb1_out   = 0;
		expect_bit7(8'h63, 0, "SW3/SCO driven by CB1");
		via_cb1_drive = 0;
		convert(4, CHARGE_500US, t);
		expect_near("port A Y with ENSEL", t, GROUND, 1);
		access (8'hdc);

		// ENSIO sends the VIA's serial data out on X1/SER.
		access (8'hdf);
		via_cb2_drive = 1;
		via_cb2_out   = 0;
		convert(3, CHARGE_500US, t);
		expect_near("port A X with SER low", t, GROUND, 1);
		via_cb2_out = 1;
		convert(3, CHARGE_500US, t);
		expect_near("port A X with SER high", t, CLAMP, 1);
		access (8'hde);
		via_cb2_drive = 0;
		convert(3, CHARGE_500US, t);
		expect_near("port A X restored", t - t0, stick_clocks(8'h80), 1);

		if (failures == 0) $display("PASS joystick A/D converter and switches");
		else $display("FAIL joystick: %0d checks", failures);
		$finish;
	end
endmodule
