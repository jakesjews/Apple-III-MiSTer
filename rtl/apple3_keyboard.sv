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
	logic [7:0] translated;
	logic event_key;

	function automatic [7:0] translate_key(
		input logic [8:0] key,
		input logic shift_down,
		input logic control_down
	);
		logic [1:0] mod_bits;
		begin
			mod_bits = {control_down, shift_down};
			translate_key = 8'h00;
			case (key)
				// Letters are uppercase on the original encoder; Control produces
				// the conventional C0 control range.
				9'h01c: translate_key = control_down ? 8'h01 : 8'h41; // A
				9'h032: translate_key = control_down ? 8'h02 : 8'h42; // B
				9'h021: translate_key = control_down ? 8'h03 : 8'h43; // C
				9'h023: translate_key = control_down ? 8'h04 : 8'h44; // D
				9'h024: translate_key = control_down ? 8'h05 : 8'h45; // E
				9'h02b: translate_key = control_down ? 8'h06 : 8'h46; // F
				9'h034: translate_key = control_down ? 8'h07 : 8'h47; // G
				9'h033: translate_key = control_down ? 8'h08 : 8'h48; // H
				9'h043: translate_key = control_down ? 8'h09 : 8'h49; // I
				9'h03b: translate_key = control_down ? 8'h0a : 8'h4a; // J
				9'h042: translate_key = control_down ? 8'h0b : 8'h4b; // K
				9'h04b: translate_key = control_down ? 8'h0c : 8'h4c; // L
				9'h03a: translate_key = control_down ? 8'h0d : 8'h4d; // M
				9'h031: translate_key = control_down ? 8'h0e : 8'h4e; // N
				9'h044: translate_key = control_down ? 8'h0f : 8'h4f; // O
				9'h04d: translate_key = control_down ? 8'h10 : 8'h50; // P
				9'h015: translate_key = control_down ? 8'h11 : 8'h51; // Q
				9'h02d: translate_key = control_down ? 8'h12 : 8'h52; // R
				9'h01b: translate_key = control_down ? 8'h13 : 8'h53; // S
				9'h02c: translate_key = control_down ? 8'h14 : 8'h54; // T
				9'h03c: translate_key = control_down ? 8'h15 : 8'h55; // U
				9'h02a: translate_key = control_down ? 8'h16 : 8'h56; // V
				9'h01d: translate_key = control_down ? 8'h17 : 8'h57; // W
				9'h022: translate_key = control_down ? 8'h18 : 8'h58; // X
				9'h035: translate_key = control_down ? 8'h19 : 8'h59; // Y
				9'h01a: translate_key = control_down ? 8'h1a : 8'h5a; // Z

				9'h016: case (mod_bits) 2'b00: translate_key=8'h31; 2'b01: translate_key=8'h21; default: translate_key=8'h31; endcase
				9'h01e: case (mod_bits) 2'b00: translate_key=8'h32; 2'b01: translate_key=8'h40; 2'b10: translate_key=8'h32; default: translate_key=8'h00; endcase
				9'h026: translate_key = shift_down ? 8'h23 : 8'h33;
				9'h025: translate_key = shift_down ? 8'h24 : 8'h34;
				9'h02e: translate_key = shift_down ? 8'h25 : 8'h35;
				9'h036: case (mod_bits) 2'b00: translate_key=8'h36; 2'b01: translate_key=8'h5e; 2'b10: translate_key=8'h35; default: translate_key=8'h53; endcase
				9'h03d: translate_key = shift_down ? 8'h26 : 8'h37;
				9'h03e: translate_key = shift_down ? 8'h2a : 8'h38;
				9'h046: translate_key = shift_down ? 8'h28 : 8'h39;
				9'h045: translate_key = shift_down ? 8'h29 : 8'h30;

				9'h04e: translate_key = control_down && shift_down ? 8'h1f : (shift_down ? 8'h5f : 8'h2d);
				9'h055: translate_key = shift_down ? 8'h2b : 8'h3d;
				9'h054: translate_key = control_down ? 8'h1b : (shift_down ? 8'h7b : 8'h5b);
				9'h05b: translate_key = control_down ? 8'h1d : (shift_down ? 8'h7d : 8'h5d);
				9'h05d: case (mod_bits) 2'b00: translate_key=8'h5c; 2'b01: translate_key=8'h7c; 2'b10: translate_key=8'h7f; default: translate_key=8'h1c; endcase
				9'h04c: translate_key = shift_down ? 8'h3a : 8'h3b;
				9'h052: translate_key = shift_down ? 8'h22 : 8'h27;
				9'h041: translate_key = shift_down ? 8'h3c : 8'h2c;
				9'h049: translate_key = shift_down ? 8'h3e : 8'h2e;
				9'h04a: translate_key = shift_down ? 8'h3f : 8'h2f;
				9'h00e: translate_key = shift_down ? 8'h7e : 8'h60;

				9'h076: translate_key = 8'h9b; // Escape
				9'h00d: translate_key = 8'h89; // Tab
				9'h05a: translate_key = 8'h0d; // Return
				9'h029: translate_key = 8'ha0; // Space (special-code flag set)
				9'h066: translate_key = 8'h88; // Backspace/left
				9'h175: translate_key = 8'h8b; // Up
				9'h172: translate_key = 8'h8a; // Down
				9'h16b: translate_key = 8'h88; // Left
				9'h174: translate_key = 8'h95; // Right
				9'h171: translate_key = 8'hae; // Delete/keypad period
				9'h15a: translate_key = 8'h8d; // Keypad Enter

				9'h070: translate_key = 8'hb0;
				9'h069: translate_key = 8'hb1;
				9'h072: translate_key = 8'hb2;
				9'h07a: translate_key = 8'hb3;
				9'h06b: translate_key = 8'hb4;
				9'h073: translate_key = 8'hb5;
				9'h074: translate_key = 8'hb6;
				9'h06c: translate_key = 8'hb7;
				9'h075: translate_key = 8'hb8;
				9'h07d: translate_key = 8'hb9;
				9'h071: translate_key = 8'hae;
				9'h07b: translate_key = 8'had;
				default: translate_key = 8'h00;
			endcase
		end
	endfunction

	always_comb begin
		translated = translate_key(ps2_key[8:0], shift, control);
		event_key = (translated != 8'h00);
	end

	always_ff @(posedge clk) begin
		data_ready <= 1'b0;
		if (reset) begin
			old_toggle    <= ps2_key[10];
			key_code      <= 8'h00;
			strobe        <= 1'b0;
			any_key_down  <= 1'b0;
			shift         <= 1'b0;
			control       <= 1'b0;
			alpha_lock    <= 1'b0;
			open_apple    <= 1'b0;
			solid_apple   <= 1'b0;
			reset_key     <= 1'b0;
			held_key      <= 9'h000;
			repeat_count   <= 24'd0;
		end
		else begin
			if (clear_strobe) strobe <= 1'b0;

			if (ps2_key[10] != old_toggle) begin
				old_toggle <= ps2_key[10];
				case (ps2_key[7:0])
					8'h12, 8'h59: shift <= ps2_key[9];
					8'h14: control <= ps2_key[9];
					8'h58: if (ps2_key[9]) alpha_lock <= ~alpha_lock;
					8'h1f: open_apple <= ps2_key[9];
					8'h27: if (ps2_key[8]) open_apple <= ps2_key[9];
					8'h11: solid_apple <= ps2_key[9];
					8'h07: reset_key <= ps2_key[9]; // F12
					default: begin
						if (event_key && ps2_key[9]) begin
							key_code      <= translated;
							strobe        <= 1'b1;
							any_key_down  <= 1'b1;
							data_ready    <= 1'b1;
							held_key      <= ps2_key[8:0];
							repeat_count   <= 24'd7159090; // 0.5 s at 14.31818 MHz
						end
						else if (!ps2_key[9] && (ps2_key[8:0] == held_key)) begin
							any_key_down <= 1'b0;
							held_key <= 9'h000;
							repeat_count <= 24'd0;
						end
					end
				endcase
			end
			else if (any_key_down) begin
				if (repeat_count != 0) repeat_count <= repeat_count - 1'b1;
				else begin
					key_code    <= translate_key(held_key, shift, control);
					strobe      <= 1'b1;
					data_ready  <= 1'b1;
					repeat_count <= solid_apple ? 24'd477272 : 24'd1431818;
				end
			end
		end
	end

endmodule
