`timescale 1ns / 1ps
// Compares the 50 Hz frame to the *binary* Euro scan PROM, 341-0060, and that
// PROM to the 341-0030 it was made from.  Pin assignments as in
// timing_prom_tb; COMP is D7, RFIELD D6, S50-60 D5, RCOLRGT D1, RSYNCH D0.
// docs/PAL.md has the reasoning, and what the dump leaves to inference.
module euro_prom_tb;
	logic clk = 0;
	always #5 clk = ~clk;

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
		.interlace       (1'b0),
		.euro            (1'b1),
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
		.euro           (1'b1),
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

	logic [7:0] standard_prom[0:2047], euro_prom[0:2047];
	string standard_path, euro_path;

	function automatic integer address_of(input integer line, input integer group);
		address_of = (((line >> 5) & 1) & ((line >> 8) & 1)) | (group << 1) | ((line & 7) << 5) |
			(((line >> 3) & 1) << 8) | (((line >> 4) & 1) << 9) | ((((line >> 6) & 3) == 3) << 10);
	endfunction

	// The counter's next line.  V5..VB reload as line 511's last state ends:
	// S50/60 for V2 and V1, which a 50 Hz PROM has to hold low, and COMP for
	// VB.  VA reloads from COMP in every extended state.
	function automatic integer line_after(input integer line);
		integer       entered;
		logic   [7:0] decode;
		begin
			decode = euro_prom[address_of(511, 15)];
			if (line == 511) entered = 'b011001000 | (decode[7] ? 2 : 0);
			else entered = line + 1;
			decode     = euro_prom[address_of(entered, 0)];
			line_after = (entered & ~1) | (decode[7] ? 1 : 0);
		end
	endfunction

	// Vertical sync is from the first broad pulse, six groups of four states
	// with RSYNCH low, to the last; groups are numbered 16 to a line.
	task automatic broad_pulses(output integer first, output integer last);
		integer run, address;
		logic [7:0] decode;
		begin
			first = -1;
			last  = -1;
			run   = 0;
			for (integer group = 448 * 16; group < 512 * 16; group++) begin
				address = address_of(group / 16, group % 16);
				decode  = euro_prom[address];
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

	integer failures = 0, checked, mismatches, moved, high;
	integer first, last, rise, fall, expected, clocks, from;
	logic vsync_q = 0;
	logic [7:0] decode, source;
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
		if (!$value$plusargs("SCAN=%s", standard_path) || !$value$plusargs("EURO=%s", euro_path))
			$fatal(1, "supply +SCAN=<hex> +EURO=<hex>");
		$readmemh(standard_path, standard_prom);
		$readmemh(euro_path, euro_prom);

		// The 341-0060 is the 341-0030 with V1 (A9) inverted in RSYNCH and
		// RCOLRGT where V2*V5 (A0) and VBL (A10) are high: lines 480..511.
		mismatches = 0;
		moved      = 0;
		high       = 0;
		for (integer address = 0; address < 2048; address++) begin
			decode = euro_prom[address];
			from   = (address[0] && address[10]) ? (address ^ 'h200) : address;
			source = standard_prom[from];
			if (decode[7:2] !== standard_prom[address][7:2] || decode[1:0] !== source[1:0]) mismatches++;
			if (decode !== standard_prom[address]) moved++;
			if (decode[5]) high++;
		end
		check(mismatches == 0 && moved == 92,
			  "341-0060 is the 341-0030 with sync and burst gate 16 lines later, and nothing else");
		// Apple's drawing changes G9 and the crystal alone, so the 50 Hz reload
		// has to come from this pin, and the sync above suits no 262-line frame.
		if (high == 2048) $display("NOTE: S50-60 reads high throughout this dump; the frame below takes it as low");

		// One frame from the start of its blanking interval.
		@(negedge clk);
		while (!(v_count == 192 && h_count == 0)) @(negedge clk);
		checked    = 0;
		mismatches = 0;
		clocks     = 0;
		do begin
			if (state_dot == ((h_state == 64) ? 8 : 6)) begin
				expected = address_of(scan_line, (h_state == 64) ? 15 : int'(h_state) / 4);
				checked++;
				decode = euro_prom[expected];
				if (refresh_slot !== decode[4] || character_slot !== decode[2] ||
					!(scan_hblank || scan_vblank) !== decode[3] || field !== decode[6]) begin
					if (mismatches < 8) $display("  decode mismatch line %0d H=%0d", scan_line, h_state);
					mismatches++;
				end
			end
			if (h_state == 64 && state_dot == 15) begin
				expected = line_after(scan_line);
				#6;
				if (scan_line !== expected[8:0]) begin
					if (mismatches < 8) $display("  COMP leads to line %0d, RTL went to %0d", expected, scan_line);
					mismatches++;
				end
			end
			@(negedge clk);
			clocks++;
		end while (!(v_count == 192 && h_count == 0));
		broad_pulses(first, last);
		check(checked == 65 * 310 && clocks == 912 * 310 && mismatches == 0,
			  "310 lines: refresh, character window, blanking, field and line sequence are the 341-0060's");
		check(first == 499 * 16 + 4 && rise == first && fall == last,
			  "vertical sync spans the 341-0060's broad pulses, from H = 16 of line 499");

		if (failures) $fatal(1, "50 Hz frame differs from the Euro scan PROM");
		$display("PASS 50 Hz frame against the 341-0060 scan PROM");
		$finish;
	end
endmodule
