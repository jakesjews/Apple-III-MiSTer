`timescale 1ns / 1ps
// Compares the interlaced fields to the *binary* scan PROMs.  The long field is
// the archived half of the Apple /// Plus 342-0145-A (FIELDIN low); the other
// field must still be the 341-0030's, which is how the two make 525 lines.
// Pin assignments as in timing_prom_tb; COMP is D7, RFIELD D6, RSYNCH D0.
module interlace_prom_tb;
	logic clk = 0;
	always #5 clk = ~clk;

	logic interlace = 1;
	wire cpu_enable, via_rising, via_falling, q3, pixel_enable, scan_hblank, scan_vblank;
	wire display_slot, refresh_slot, character_slot, frame_tick, field, peripheral_select;
	wire [9:0] h_count;
	wire [8:0] v_count;
	wire [8:0] scan_line;
	wire [6:0] h_state;
	wire [3:0] state_dot;
	apple3_timing timing (
		.clk_14m         (clk),
		.slow_mode       (1'b0),
		.screen_enable   (1'b1),
		.interlace,
		.peripheral_cycle(1'b0),
		.rtc_cycle       (1'b0),
		.peripheral_select,
		.ram_cycle       (1'b1),
		.cpu_enable,
		.via_rising,
		.via_falling,
		.q3,
		.pixel_enable,
		.hblank          (scan_hblank),
		.vblank          (scan_vblank),
		.display_slot,
		.refresh_slot,
		.character_slot,
		.h_count,
		.v_count,
		.scan_line,
		.h_state,
		.state_dot,
		.frame_tick,
		.field
	);

	wire hblank, vblank, hsync, vsync;
	apple3_video video (
		.clk,
		.reset          (1'b0),
		.h_count,
		.v_count,
		.scan_line,
		.field,
		.h_state,
		.state_dot,
		.frame_tick,
		.screen_enable  (1'b1),
		.native_mode    (1'b1),
		.video_mode     (4'd0),
		.smooth_enable  (1'b0),
		.smooth_offset  (3'd0),
		.character_write(1'b0),
		.character_slot,
		.ram_addr       (),
		.ram_q          (16'd0),
		.red            (),
		.green          (),
		.blue           (),
		.colour         (),
		.colour_phase   (),
		.colour_burst   (),
		.hblank,
		.vblank,
		.hsync,
		.vsync
	);

	logic [7:0] ordinary_prom[0:2047], long_prom[0:2047];
	string ordinary_path, long_path;

	function automatic integer address_of(input integer line, input integer group);
		address_of = (((line >> 5) & 1) & ((line >> 8) & 1)) | (group << 1) | ((line & 7) << 5) |
			(((line >> 3) & 1) << 8) | (((line >> 4) & 1) << 9) | ((((line >> 6) & 3) == 3) << 10);
	endfunction
	function automatic [7:0] prom(input logic long_field, input integer line, input integer group);
		prom = long_field ? long_prom[address_of(line, group)] : ordinary_prom[address_of(line, group)];
	endfunction

	// The counter's next line, from COMP alone.  V5..VB reload as line 511's
	// last state ends, with COMP for VB; VA reloads from COMP in the extended
	// state, where the PROM already sees the new line and H = 0.
	function automatic integer line_after(input logic long_field, input integer line);
		integer       entered;
		logic   [7:0] decode;
		begin
			decode = prom(long_field, 511, 15);
			if (line == 511) entered = 'b011111000 | (decode[7] ? 2 : 0);
			else entered = line + 1;
			decode     = prom(long_field, entered, 0);
			line_after = (entered & ~1) | (decode[7] ? 1 : 0);
		end
	endfunction

	// RSYNCH is low in a horizontal or equalising pulse for one group of four
	// states and in a broad pulse for six.  Vertical sync is from the first
	// broad pulse to the last; groups are numbered 16 to a line.
	task automatic broad_pulses(input logic long_field, output integer first, output integer last);
		integer       run;
		logic   [7:0] decode;
		begin
			first = -1;
			last  = -1;
			run   = 0;
			for (integer group = 470 * 16; group < 500 * 16; group++) begin
				decode = prom(long_field, group / 16, group % 16);
				if (!decode[0]) run++;
				else begin
					if (run >= 6) begin
						if (first < 0) first = group - run;
						last = group;
					end
					run = 0;
				end
			end
		end
	endtask

	integer failures = 0, checked, mismatches;
	integer first, last, rise, fall, expected;
	logic long_field, vsync_q = 0;
	logic [7:0] decode;
	task automatic check(input logic ok, input string message);
		if (ok !== 1'b1) begin
			failures++;
			$display("FAIL: %s", message);
		end else $display("PASS: %s", message);
	endtask

	// The video module's sync trails the counter by 28 dots.
	always @(negedge clk) begin
		vsync_q <= vsync;
		if (vsync && !vsync_q) rise = scan_line * 16 + (h_count - 28) / 56;
		if (!vsync && vsync_q) fall = scan_line * 16 + (h_count - 28) / 56;
	end

	initial begin
		if (!$value$plusargs("SCAN=%s", ordinary_path) || !$value$plusargs("PLUS=%s", long_path))
			$fatal(1, "supply +SCAN=<hex> +PLUS=<hex>");
		$readmemh(ordinary_path, ordinary_prom);
		$readmemh(long_path, long_prom);

		// RFIELD: the archived half sets the flip-flop at H5..H2 = 0 of line 448.
		mismatches = 0;
		for (integer address = 0; address < 2048; address++)
		if (long_prom[address][6] !== (address == address_of(448, 0))) mismatches++;
		check(mismatches == 0, "342-0145-A RFIELD is true at line 448, H5..H2 = 0 alone");

		// Two fields from the start of one blanking interval.
		@(negedge clk);
		while (!(v_count == 192 && h_count == 0)) @(negedge clk);
		for (integer fields = 0; fields < 2; fields++) begin
			long_field = !field;
			checked    = 0;
			mismatches = 0;
			do begin
				if (state_dot == ((h_state == 64) ? 8 : 6)) begin
					expected = address_of(scan_line, (h_state == 64) ? 15 : int'(h_state) / 4);
					checked++;
					decode = long_field ? long_prom[expected] : ordinary_prom[expected];
					if (refresh_slot !== decode[4] || character_slot !== decode[2] ||
						!(scan_hblank || scan_vblank) !== decode[3]) begin
						if (mismatches < 8)
							$display("  decode mismatch line %0d H=%0d field %b", scan_line, h_state, field);
						mismatches++;
					end
				end
				if (h_state == 64 && state_dot == 15) begin
					expected = line_after(long_field, scan_line);
					#6;
					if (scan_line !== expected[8:0]) begin
						if (mismatches < 8) $display("  COMP leads to line %0d, RTL went to %0d", expected, scan_line);
						mismatches++;
					end
				end
				@(negedge clk);
			end while (!(v_count == 192 && h_count == 0));
			broad_pulses(long_field, first, last);
			if (long_field) begin
				check(checked == 65 * 263 && mismatches == 0,
					  "long field: refresh, character window, blanking and line sequence are the 342-0145-A's");
				check(rise == first && fall == last, "long field: vertical sync spans the 342-0145-A's broad pulses");
			end else begin
				check(checked == 65 * 262 && mismatches == 0,
					  "other field: refresh, character window, blanking and line sequence are the 341-0030's");
				check(rise == first && fall == last, "other field: vertical sync spans the 341-0030's broad pulses");
			end
		end

		if (failures) $fatal(1, "interlace differs from the scan PROMs");
		$display("PASS interlaced fields against the 341-0030 and 342-0145-A scan PROMs");
		$finish;
	end
endmodule
