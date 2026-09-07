// PS/2 to Apple /// KB3600-compatible keyboard encoder.
//
// The translation table follows the Apple service-manual matrix and mask-ROM
// output table, checked against MAME's independently transcribed key_remap and
// the Apple-iii-Keyboard-Encoder hardware replacement project.

module apple3_keyboard (
	input  logic        clk,
	input  logic        reset,
	input  logic [10:0] ps2_key,       // {toggle, pressed, extended, set-2 code}
	input  logic        clear_strobe,

	output logic [7:0]  key_code,
	output logic        strobe,
	output logic        any_key_down,
	output logic        shift,
	output logic        control,
	output logic        alpha_lock,
	output logic        open_apple,
	output logic        solid_apple,
	output logic        reset_key,
	output logic        data_ready
);

	logic old_toggle;
	logic [8:0] held_key;
	logic [23:0] repeat_count;
	logic [8:0] translated, repeat_translation;
	logic event_key;
	logic [511:0] keys_down;
	logic held_key_valid;
	logic [8:0] scan_key;
	logic [1:0] shift_down, control_down, apple_down, alt_down;
	logic caps_down;

	assign any_key_down = |keys_down;
	assign shift = |shift_down;
	assign control = |control_down;
	assign open_apple = |apple_down;
	assign solid_apple = |alt_down;

	function automatic [8:0] translate_key(
		input logic [8:0] key,
		input logic shift_down,
		input logic control_down
	);
		logic [1:0] mod_bits;
		begin
			mod_bits = {control_down, shift_down};
			translate_key = 9'h000;
			case (key)
				// Letters are uppercase on the original encoder; Control produces
				// the conventional C0 control range.
				9'h01c: translate_key = control_down ? 9'h101 : 9'h141; // A
				9'h032: translate_key = control_down ? 9'h102 : 9'h142; // B
				9'h021: translate_key = control_down ? 9'h103 : 9'h143; // C
				9'h023: translate_key = control_down ? 9'h104 : 9'h144; // D
				9'h024: translate_key = control_down ? 9'h105 : 9'h145; // E
				9'h02b: translate_key = control_down ? 9'h106 : 9'h146; // F
				9'h034: translate_key = control_down ? 9'h107 : 9'h147; // G
				9'h033: translate_key = control_down ? 9'h108 : 9'h148; // H
				9'h043: translate_key = control_down ? 9'h109 : 9'h149; // I
				9'h03b: translate_key = control_down ? 9'h10a : 9'h14a; // J
				9'h042: translate_key = control_down ? 9'h10b : 9'h14b; // K
				9'h04b: translate_key = control_down ? 9'h10c : 9'h14c; // L
				9'h03a: translate_key = control_down ? 9'h10d : 9'h14d; // M
				9'h031: translate_key = control_down ? 9'h10e : 9'h14e; // N
				9'h044: translate_key = control_down ? 9'h10f : 9'h14f; // O
				9'h04d: translate_key = control_down ? 9'h110 : 9'h150; // P
				9'h015: translate_key = control_down ? 9'h111 : 9'h151; // Q
				9'h02d: translate_key = control_down ? 9'h112 : 9'h152; // R
				9'h01b: translate_key = control_down ? 9'h113 : 9'h153; // S
				9'h02c: translate_key = control_down ? 9'h114 : 9'h154; // T
				9'h03c: translate_key = control_down ? 9'h115 : 9'h155; // U
				9'h02a: translate_key = control_down ? 9'h116 : 9'h156; // V
				9'h01d: translate_key = control_down ? 9'h117 : 9'h157; // W
				9'h022: translate_key = control_down ? 9'h118 : 9'h158; // X
				9'h035: translate_key = control_down ? 9'h119 : 9'h159; // Y
				9'h01a: translate_key = control_down ? 9'h11a : 9'h15a; // Z

				9'h016: case (mod_bits) 2'b00: translate_key=9'h131; 2'b01: translate_key=9'h121; default: translate_key=9'h131; endcase
				9'h01e: case (mod_bits) 2'b00: translate_key=9'h132; 2'b01: translate_key=9'h140; 2'b10: translate_key=9'h132; default: translate_key=9'h100; endcase
				9'h026: translate_key = shift_down ? 9'h123 : 9'h133;
				9'h025: translate_key = shift_down ? 9'h124 : 9'h134;
				9'h02e: translate_key = shift_down ? 9'h125 : 9'h135;
				9'h036: case (mod_bits) 2'b00: translate_key=9'h136; 2'b01: translate_key=9'h15e; 2'b10: translate_key=9'h135; default: translate_key=9'h153; endcase
				9'h03d: translate_key = shift_down ? 9'h126 : 9'h137;
				9'h03e: translate_key = shift_down ? 9'h12a : 9'h138;
				9'h046: translate_key = shift_down ? 9'h128 : 9'h139;
				9'h045: translate_key = shift_down ? 9'h129 : 9'h130;

				9'h04e: translate_key = control_down && shift_down ? 9'h11f : (shift_down ? 9'h15f : 9'h12d);
				9'h055: translate_key = shift_down ? 9'h12b : 9'h13d;
				9'h054: translate_key = control_down ? 9'h11b : (shift_down ? 9'h17b : 9'h15b);
				9'h05b: translate_key = control_down ? 9'h11d : (shift_down ? 9'h17d : 9'h15d);
				9'h05d: case (mod_bits) 2'b00: translate_key=9'h15c; 2'b01: translate_key=9'h17c; 2'b10: translate_key=9'h17f; default: translate_key=9'h11c; endcase
				9'h04c: translate_key = shift_down ? 9'h13a : 9'h13b;
				9'h052: translate_key = shift_down ? 9'h122 : 9'h127;
				9'h041: translate_key = shift_down ? 9'h13c : 9'h12c;
				9'h049: translate_key = shift_down ? 9'h13e : 9'h12e;
				9'h04a: translate_key = shift_down ? 9'h13f : 9'h12f;
				9'h00e: translate_key = shift_down ? 9'h17e : 9'h160;

				9'h076: translate_key = 9'h19b; // Escape
				9'h00d: translate_key = 9'h189; // Tab
				9'h05a: translate_key = 9'h10d; // Return
				9'h029: translate_key = 9'h1a0; // Space (special-code flag set)
				9'h066: translate_key = 9'h188; // Backspace/left
				9'h175: translate_key = 9'h18b; // Up
				9'h172: translate_key = 9'h18a; // Down
				9'h16b: translate_key = 9'h188; // Left
				9'h174: translate_key = 9'h195; // Right
				9'h171: translate_key = 9'h1ae; // Delete/keypad period
				9'h15a: translate_key = 9'h18d; // Keypad Enter

				9'h070: translate_key = 9'h1b0;
				9'h069: translate_key = 9'h1b1;
				9'h072: translate_key = 9'h1b2;
				9'h07a: translate_key = 9'h1b3;
				9'h06b: translate_key = 9'h1b4;
				9'h073: translate_key = 9'h1b5;
				9'h074: translate_key = 9'h1b6;
				9'h06c: translate_key = 9'h1b7;
				9'h075: translate_key = 9'h1b8;
				9'h07d: translate_key = 9'h1b9;
				9'h071: translate_key = 9'h1ae;
				9'h07b: translate_key = 9'h1ad;
				default: translate_key = 9'h000;
			endcase
		end
	endfunction

	always_comb begin
		translated = translate_key(ps2_key[8:0], shift, control);
		event_key = translated[8];
		repeat_translation = translate_key(held_key, shift, control);
	end

	always_ff @(posedge clk) begin
		data_ready <= 1'b0;
		if (reset) begin
			old_toggle    <= ps2_key[10];
			key_code      <= 8'h00;
			strobe        <= 1'b0;
			shift_down    <= 2'b00;
			control_down  <= 2'b00;
			apple_down    <= 2'b00;
			alt_down      <= 2'b00;
			alpha_lock    <= 1'b0;
			caps_down     <= 1'b0;
			reset_key     <= 1'b0;
			keys_down     <= '0;
			held_key      <= 9'h000;
			held_key_valid <= 1'b0;
			scan_key      <= 9'h000;
			repeat_count  <= 24'd0;
		end
		else begin
			if (clear_strobe) strobe <= 1'b0;

			if (ps2_key[10] != old_toggle) begin
				old_toggle <= ps2_key[10];
				case (ps2_key[8:0])
					9'h012: shift_down[0] <= ps2_key[9];
					9'h059: shift_down[1] <= ps2_key[9];
					9'h014: control_down[0] <= ps2_key[9];
					9'h114: control_down[1] <= ps2_key[9];
					9'h11f: apple_down[0] <= ps2_key[9];
					9'h127: apple_down[1] <= ps2_key[9];
					9'h011: alt_down[0] <= ps2_key[9];
					9'h111: alt_down[1] <= ps2_key[9];
					9'h058: begin
						if (ps2_key[9] && !caps_down) alpha_lock <= ~alpha_lock;
						caps_down <= ps2_key[9];
					end
					9'h007: reset_key <= ps2_key[9]; // F12
					default: if (event_key) begin
						keys_down[ps2_key[8:0]] <= ps2_key[9];
						if (ps2_key[9] && !keys_down[ps2_key[8:0]]) begin
							key_code      <= translated[7:0];
							strobe        <= 1'b1;
							data_ready    <= 1'b1;
							held_key      <= ps2_key[8:0];
							held_key_valid <= 1'b1;
							repeat_count  <= 24'd7159090; // 0.5 s at 14.31818 MHz
						end
						else if (!ps2_key[9] && (ps2_key[8:0] == held_key)) begin
							held_key_valid <= 1'b0;
							repeat_count <= 24'd7159090;
						end
					end
				endcase
			end
			else if (!held_key_valid) begin
				// Rescan after the newest key is released. A serial scan avoids
				// a large priority encoder; even a full scan takes only 36 us.
				scan_key <= scan_key + 1'b1;
				if (keys_down[scan_key]) begin
					held_key <= scan_key;
					held_key_valid <= 1'b1;
				end
			end
			else if (repeat_count != 0) repeat_count <= repeat_count - 1'b1;
			else begin
				key_code    <= repeat_translation[7:0];
				strobe      <= 1'b1;
				data_ready  <= 1'b1;
				repeat_count <= solid_apple ? 24'd477272 : 24'd1431818;
			end
		end
	end

endmodule
