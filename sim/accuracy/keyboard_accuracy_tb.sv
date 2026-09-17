`timescale 1ns / 1ps
// SRM ch.8 explicitly assigns NUL to Control-Shift-2.
module keyboard_accuracy_tb;
	logic clk = 0, reset = 1, clear_strobe = 0, plus_keymap = 0;
	always #5 clk = ~clk;
	logic [10:0] ps2_key = 0;
	wire  [ 7:0] key_code;
	wire strobe, any_key_down, shift, control, alpha_lock, open_apple, solid_apple, reset_key, data_ready;
	apple3_keyboard dut (.*);
	integer failures = 0;
	task automatic event_key(input logic pressed, input logic [8:0] scan);
		@(negedge clk);
		ps2_key = {!ps2_key[10], pressed, scan};
		@(negedge clk);
	endtask
	task automatic check(input logic ok, input string message);
		if (ok !== 1'b1) begin
			failures++;
			$display("FAIL: %s", message);
		end else $display("PASS: %s", message);
	endtask
	initial begin
		repeat (3) @(negedge clk);
		reset = 0;
		event_key(1, 9'h014);
		event_key(1, 9'h012);
		event_key(1, 9'h01e);
		check(strobe && any_key_down && key_code == 0, "Control-Shift-2 emits a strobed NUL");
		event_key(0, 9'h01e);
		event_key(0, 9'h014);
		event_key(0, 9'h012);
		// The physical SHIFT wire remains active while either shift switch is held.
		event_key(1, 9'h012);
		event_key(1, 9'h059);
		event_key(0, 9'h012);
		check(shift, "releasing left Shift preserves held right Shift");
		event_key(0, 9'h059);
		// AK is the encoder's ANY-key signal, not a last-key latch.
		event_key(1, 9'h01c);
		event_key(1, 9'h032);
		event_key(0, 9'h032);
		check(any_key_down, "releasing B while A is held preserves any-key-down");
		event_key(0, 9'h01c);
		check(!any_key_down, "all ordinary keys released clears AK");
		event_key(1, 9'h014);
		event_key(1, 9'h114);
		event_key(0, 9'h014);
		check(control, "right Control survives left Control release");
		event_key(0, 9'h114);
		event_key(1, 9'h011);
		event_key(1, 9'h111);
		event_key(0, 9'h011);
		check(solid_apple, "right Alt survives left Alt release");
		event_key(0, 9'h111);
		event_key(1, 9'h11f);
		event_key(1, 9'h127);
		event_key(0, 9'h11f);
		check(open_apple, "right GUI survives left GUI release");
		event_key(0, 9'h127);
		check(!any_key_down && !shift && !control && !solid_apple && !open_apple,
			  "modifier-only presses do not assert encoder AK");
		event_key(1, 9'h112);
		event_key(0, 9'h112);
		check(!shift && !any_key_down, "Print Screen extended Shift prefix is not a held key");
		event_key(1, 9'h014);
		event_key(1, 9'h012);
		event_key(1, 9'h01e);
		event_key(0, 9'h014);
		event_key(0, 9'h012);
		event_key(0, 9'h01e);
		check(!any_key_down, "NUL key release is recognized after modifier release");
		event_key(1, 9'h01c);
		@(negedge clk);
		clear_strobe = 1;
		@(negedge clk);
		clear_strobe = 0;
		event_key(1, 9'h01c);
		check(!strobe, "host typematic duplicate does not retrigger the hardware encoder");
		event_key(1, 9'h032);
		event_key(0, 9'h032);
		repeat (520) @(negedge clk);
		clear_strobe = 1;
		@(negedge clk);
		clear_strobe     = 0;
		// Accelerate only the delay, preserving key selection and emission logic.
		dut.repeat_count = 1;
		repeat (3) @(negedge clk);
		check(strobe && key_code == 8'h41, "repeat returns to A after the newer B is released");
		event_key(0, 9'h01c);
		repeat (520) @(negedge clk);
		clear_strobe = 1;
		@(negedge clk);
		clear_strobe     = 0;
		dut.repeat_count = 0;
		repeat (3) @(negedge clk);
		check(!strobe && !any_key_down, "no repeat remains after the last key is released");

		// Repeat ordering: the solid Apple line (Apple's Apple2) clocks the high-speed
		// flip-flop, so it has to close after the key it is to repeat.
		event_key(1, 9'h011);
		event_key(1, 9'h01c);
		clear_strobe = 1;
		@(negedge clk);
		clear_strobe     = 0;
		dut.repeat_count = 1;
		repeat (6) @(negedge clk);
		check(!strobe, "solid Apple held before a key sends a single character");
		event_key(0, 9'h011);
		event_key(1, 9'h011);
		repeat (2) @(negedge clk);
		check(dut.fast_repeat, "solid Apple closed after the key arms the high-speed repeat");
		clear_strobe = 1;
		@(negedge clk);
		clear_strobe     = 0;
		dut.repeat_count = 1;
		repeat (2) @(negedge clk);
		check(strobe && key_code == 8'h41 && dut.repeat_count == 24'd477272, "the armed key then repeats at 30 cps");
		event_key(0, 9'h011);
		clear_strobe = 1;
		@(negedge clk);
		clear_strobe     = 0;
		dut.repeat_count = 1;
		repeat (2) @(negedge clk);
		check(strobe && dut.repeat_count == 24'd1431818, "releasing solid Apple returns the held key to 10 cps");
		event_key(0, 9'h01c);

		// The cursor keys are two-contact switches whose second contact is
		// OR-wired into the solid Apple line, so the guest sees that key too.
		event_key(1, 9'h174);
		check(!solid_apple, "a cursor key's first contact leaves the solid Apple line alone");
		clear_strobe = 1;
		@(negedge clk);
		clear_strobe     = 0;
		dut.repeat_count = 1;
		repeat (2) @(negedge clk);
		check(strobe && key_code == 8'h95, "a held cursor key repeats");
		check(solid_apple, "the held cursor key's second contact drives the solid Apple line");
		repeat (2) @(negedge clk);
		check(dut.fast_repeat, "the cursor second contact raises that key to 30 cps");
		event_key(0, 9'h174);
		repeat (3) @(negedge clk);
		check(!solid_apple, "releasing the cursor key opens the second contact");

		// The Apple /// Plus DELETE key is a special key: the layout table never
		// redefines it, which needs the encoder's special-code flag.
		clear_strobe = 1;
		@(negedge clk);
		clear_strobe = 0;
		plus_keymap  = 1;
		event_key(1, 9'h171);
		check(strobe && key_code == 8'hff, "the /// Plus DELETE key sends a special-flagged DEL");
		event_key(0, 9'h171);
		plus_keymap = 0;

		$display("keyboard accuracy: %0d failed checks", failures);
		if (failures) $fatal(1, "keyboard accuracy discrepancies");
		$finish;
	end
endmodule
