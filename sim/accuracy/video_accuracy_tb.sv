`timescale 1ns / 1ps
// Independent boundary checks from SRM ch.2/ch.6 and the 342-0032/0055 PROMs.
// No clock runs: the pixel pipeline is seeded directly and addressing is
// combinational, so each check sets one scan position and reads the result.
module video_accuracy_tb;
	logic clk = 0, reset = 0;
	logic [9:0] h_count = 0;
	logic [8:0] v_count = 0;
	logic [6:0] h_state = 0;
	logic [3:0] state_dot = 0;
	logic frame_tick = 0, screen_enable = 1, native_mode = 1;
	logic [3:0] video_mode = 0;
	logic smooth_enable = 0, character_write = 0, character_slot = 0;
	logic [ 2:0] smooth_offset = 0;
	wire  [17:0] ram_addr;
	logic [15:0] ram_q = 0;
	wire [7:0] red, green, blue;
	wire hblank, vblank, hsync, vsync;
	apple3_video dut (.*);
	integer failures = 0, mismatches = 0;
	logic [27:0] pixels;
	logic [18:0] before_scroll;
	integer physical, expected_word, address_checks = 0, address_errors = 0;
	integer vertical, text_checks = 0, text_errors = 0, hole_checks = 0;
	task automatic check(input logic ok, input string message);
		if (ok !== 1'b1) begin
			failures++;
			$display("FAIL: %s", message);
		end else $display("PASS: %s", message);
	endtask
	// Scan position: line, horizontal state and dot within it.
	task automatic scan(input integer line, input integer state, input integer dot);
		v_count   = line;
		h_state   = state;
		state_dot = dot;
		h_count   = state * 14 + dot;
		#1;
	endtask
	function automatic integer word_of(input integer address);
		word_of = (address >> 12) * 2048 + (((address >> 10) ^ (address >> 11)) & 1) * 1024 + (address & 1023);
	endfunction
	initial begin
		dut.flash_count = 0;
		// Seven distinct colours in 28 serial bits, each displayed for four dots.
		// This checks the *entire* two-byte-pair group, including the 14-dot join:
		// the even column shows its own pair and the odd one after it, the odd
		// column shows the even pair before it and its own.
		pixels          = 28'h7654321;
		video_mode      = 4'hb;
		for (integer dot = 0; dot < 28; dot++) begin
			if (dot < 14) begin
				dut.pixel_low  = {1'b0, pixels[6:0]};
				dut.pixel_high = {1'b0, pixels[13:7]};
				dut.next_low   = {1'b0, pixels[20:14]};
				dut.next_high  = {1'b0, pixels[27:21]};
				scan(0, 2, dot);
			end else begin
				dut.prev_low   = {1'b0, pixels[6:0]};
				dut.prev_high  = {1'b0, pixels[13:7]};
				dut.pixel_low  = {1'b0, pixels[20:14]};
				dut.pixel_high = {1'b0, pixels[27:21]};
				scan(0, 3, dot - 14);
			end
			if (dut.colour_index !== pixels[(dot/4)*4+:4]) begin
				mismatches++;
				$display("  140-mode dot %0d: expected colour %x, got %x", dot, pixels[(dot/4)*4+:4], dut.colour_index);
			end
		end
		check(mismatches == 0, "140-mode seven equal-width pixels across the 14-dot boundary");

		// VA/VB/VC offset must also change the high-resolution RAM fetch address.
		for (integer mode = 8; mode < 12; mode++) begin
			video_mode    = mode;
			smooth_enable = 0;
			scan(0, 0, 0);
			before_scroll = {dut.primary_lane, ram_addr};
			smooth_enable = 1;
			smooth_offset = 1;
			#1;
			check({dut.primary_lane, ram_addr} != before_scroll, $sformatf(
				  "graphics mode %x scroll changes fetched row", mode));
		end

		// Exact physical address and byte lane across all graphics rows, offsets,
		// both pages and both planes, including modulo-eight scroll wrap.  Each
		// line is read during that line: the primary plane in the first four
		// dots of the column's state, the secondary in the rest of the half.
		smooth_enable = 1;
		for (integer mode = 8; mode < 16; mode++)
		for (integer y = 0; y < 192; y++)
		for (integer offset = 0; offset < 8; offset++)
		for (integer plane = 0; plane < 2; plane++)
		for (integer boundary = 0; boundary < 2; boundary++) begin
			video_mode    = mode;
			smooth_offset = offset;
			scan(y, 39 * boundary, plane ? 5 : 0);
			physical=((y/8)%8)*128+(y/64)*40+((y+offset)%8)*1024+
				((mode&4)?((mode==12)?8192:16384):0)+8192*plane+39*boundary;
			expected_word = word_of(physical);
			address_checks++;
			if (ram_addr !== expected_word[17:0] ||
				(plane ? dut.secondary_lane : dut.primary_lane) !== ((physical >> 11) & 1)) begin
				if (address_errors < 5)
					$display(
						"graphics address mismatch mode=%x y=%0d scroll=%0d physical=%x word=%x",
						mode,
						y,
						offset,
						physical,
						ram_addr
					);
				address_errors++;
			end
		end
		check(address_errors == 0, $sformatf("%0d exact graphics fetch addresses and byte lanes", address_checks));

		// The text scanner over every state of every line.  SRM p.2.6: "The
		// Video addresses are much the same as in the Apple ][. There is a minor
		// difference in the Summing Circuit, but the technique of condensing
		// undisplayed addresses is the same."  Each line reads 64 consecutive
		// bytes of its 128-byte block, beginning with its displayed 40-byte
		// segment; the Apple /// counter starts its display at H = 0, where the
		// Apple II's needed an offset adder for H = 24.  Blanking lines have
		// V7..V6 = 3, whose segment would start at $78: the screen hole, read
		// at H5..H3 = 0.  The extended state repeats H = 0.
		smooth_enable = 0;
		video_mode    = 0;
		for (integer line = 0; line < 262; line++)
		for (integer state = 0; state < 65; state++) begin
			vertical = (line < 256) ? line + 256 : line - 6;
			physical = 'h78400 + ((vertical >> 3) & 7) * 128 + (40 * ((vertical >> 6) & 3) + state % 64) % 128;
			scan(line, state, 0);
			text_checks++;
			if (ram_addr !== word_of(physical) || dut.primary_lane !== 1'b0) text_errors++;
			if (line < 192 && state < 40 && physical != 'h78400 + ((line / 8) % 8) * 128 + (line / 64) * 40 + state)
				text_errors++;
			if (line >= 192 && (state % 64) < 8) begin
				hole_checks++;
				if (physical != 'h78478 + ((vertical >> 3) & 7) * 128 + (state % 8)) text_errors++;
			end
		end
		check(text_errors == 0 && hole_checks == 70 * 9, $sformatf(
			  "%0d text scanner addresses follow the 128-byte blocks, SRM layout and %0d hole reads",
			  text_checks,
			  hole_checks
			  ));

		// Vertical blanking forces the text map (every DHIRES term of 342-0032
		// has /VBL), so every mode reads the holes in the download window.
		mismatches = 0;
		for (integer emulation = 0; emulation < 2; emulation++)
		for (integer mode = 0; mode < 16; mode++) begin
			native_mode = !emulation;
			video_mode  = mode;
			scan(224, 3, 0);
			if (ram_addr !== word_of('h78478 + 4 * 128 + 3)) mismatches++;
			scan(224, 3, 5);
			if (ram_addr !== word_of('h78878 + 4 * 128 + 3) || dut.secondary_lane !== 1'b1) mismatches++;
		end
		check(mismatches == 0, "every native and emulation mode reads the screen holes during VBL");
		native_mode = 1;

		// Apple ][ mode: C051 selects TEXT regardless of the HIRES latch (C057).
		// Page 1, 'A' with first dot lit. SRM ch.10; mode PROM TEXT/-AIISW inputs.
		native_mode                      = 0;
		video_mode                       = 4'h9;
		dut.pixel_low                    = 8'hc1;
		dut.pixel_high                   = 8'h00;
		dut.character_ram[{7'h41, 3'd0}] = 8'h01;
		scan(0, 2, 0);
		check({red, green, blue} == 24'hffffff, "Apple II TEXT overrides HIRES in emulation mode");

		// TEXT also selects text-page fetches when HIRES remains set.
		scan(0, 0, 0);
		check(ram_addr == 18'h3c400 && !dut.primary_lane, "Apple II TEXT fetch overrides HIRES");
		dut.pixel_low  = 8'h21;
		dut.pixel_high = 8'h43;
		for (integer page = 0; page < 2; page++) begin
			video_mode = page * 4;
			scan(0, 2, 0);
			check(dut.colour_index == (page ? 3 : 1), "Apple II lores upper nibble-row and page select");
			scan(4, 2, 0);
			check(dut.colour_index == (page ? 4 : 2), "Apple II lores lower nibble-row and page select");
		end
		// MIXED selects text precisely at line 160, and a line is read during
		// that line, so line 159 reads graphics and line 160 text.
		for (integer hires = 0; hires < 2; hires++) begin
			video_mode = 2 + hires * 8;
			scan(159, 0, 0);
			check(ram_addr == (hires ? 18'h009d0 : 18'h3c5d0), "mixed line 159 still fetches graphics");
			scan(160, 0, 0);
			check(ram_addr == 18'h3c650 && !dut.primary_lane, "mixed line 160 fetches text");
			dut.pixel_low                    = 8'hc1;
			dut.character_ram[{7'h41, 3'd0}] = 8'h01;
			scan(160, 2, 0);
			check({red, green, blue} == 24'hffffff, "mixed bottom region renders 40-column text");
		end

		$display("video accuracy: %0d failed checks", failures);
		if (failures) $fatal(1, "video accuracy discrepancies");
		$finish;
	end
endmodule
