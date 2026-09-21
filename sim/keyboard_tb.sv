`timescale 1ns / 1ps

module keyboard_tb;
	logic clk = 0, reset = 1, clear_strobe = 0, plus_keymap = 0;
	logic [10:0] ps2_key = 0;
	wire  [ 7:0] key_code;
	wire strobe, any_key_down, shift, control, alpha_lock;
	wire open_apple, solid_apple, reset_key, data_ready;
	logic toggle = 0;

	apple3_keyboard dut (.*);
	always #5 clk = ~clk;

	task automatic key_event(input [7:0] code, input ext, input pressed);
		begin
			toggle  = ~toggle;
			ps2_key = {toggle, pressed, ext, code};
			@(posedge clk);
			#1;
		end
	endtask

	initial begin
		repeat (2) @(posedge clk);
		reset = 0;
		key_event(8'h1c, 0, 1);  // A
		if (!strobe || !any_key_down || key_code !== 8'h41 || !data_ready) $fatal(1, "A make");
		key_event(8'h1c, 0, 0);
		if (any_key_down || !strobe) $fatal(1, "A break/strobe persistence");
		clear_strobe = 1;
		@(posedge clk);
		#1;
		clear_strobe = 0;
		if (strobe) $fatal(1, "strobe clear");

		key_event(8'h14, 0, 1);  // Control
		key_event(8'h1c, 0, 1);  // Ctrl-A
		if (!control || key_code !== 8'h01) $fatal(1, "control translation=%02x", key_code);
		key_event(8'h1c, 0, 0);
		key_event(8'h14, 0, 0);

		key_event(8'h75, 1, 1);  // Up arrow
		if (key_code !== 8'h8b) $fatal(1, "up arrow=%02x", key_code);
		key_event(8'h75, 1, 0);

		key_event(8'h58, 0, 1);
		if (!alpha_lock) $fatal(1, "alpha lock did not toggle");
		key_event(8'h58, 0, 0);
		key_event(8'h06, 0, 1);  // F2
		if (!reset_key) $fatal(1, "reset key make");
		key_event(8'h06, 0, 0);
		if (reset_key) $fatal(1, "reset key break");
		key_event(8'h07, 0, 1);  // F12 belongs to the MiSTer menu
		if (reset_key) $fatal(1, "F12 must not reach the machine");
		key_event(8'h07, 0, 0);

		key_event(8'h71, 1, 1);  // Delete on the original keyboard: keypad period
		if (key_code !== 8'hae) $fatal(1, "delete without the /// Plus keymap=%02x", key_code);
		key_event(8'h71, 1, 0);
		plus_keymap = 1;
		key_event(8'h71, 1, 1);  // The /// Plus DELETE key, special-code flag set
		if (key_code !== 8'hff) $fatal(1, "/// Plus delete=%02x", key_code);
		key_event(8'h71, 1, 0);
		key_event(8'h71, 0, 1);  // Keypad period is unchanged by the keymap
		if (key_code !== 8'hae) $fatal(1, "/// Plus keypad period=%02x", key_code);
		key_event(8'h71, 0, 0);
		plus_keymap = 0;

		$display("PASS apple3_keyboard");
		$finish;
	end
endmodule
