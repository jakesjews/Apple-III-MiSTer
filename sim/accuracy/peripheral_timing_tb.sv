`timescale 1ns / 1ps
// SRM 5.4/5.12: a new FSPACE address after the A completion misses D11.
// SRM 5.5 and sheet 10: HPE holds the loaded Q register, extending A to 9
// clocks. Expectations below are bus intervals, independent of the RTL FFs.
module peripheral_timing_tb;
	logic clk_14m = 0;
	always #5 clk_14m = ~clk_14m;
	logic slow_mode = 0, screen_enable = 0, peripheral_cycle = 0, rtc_cycle = 0, ram_cycle = 0;
	wire cpu_enable, via_rising, via_falling, peripheral_select, q3, pixel_enable;
	wire hblank, vblank, display_slot, refresh_slot, character_slot, frame_tick;
	wire  [9:0] h_count;
	wire  [8:0] v_count;
	logic       interlace = 0;
	logic       euro = 0;
	wire  [8:0] scan_line;
	wire        field;
	wire  [6:0] h_state;
	wire  [3:0] state_dot;
	apple3_timing dut (.*);
	integer checks = 0;

	task automatic access_device(input integer state_number, input bit from_a, input bit slow, input bit rtc);
		integer start_dot, elapsed, expected, accesses;
		begin
			slow_mode        = 0;
			peripheral_cycle = 0;
			rtc_cycle        = 0;
			start_dot        = (from_a ? 6 : 13) + (state_number == 64 ? 2 : 0);
			// Allow a whole line to clear the previous delayed select.
			repeat (912) @(negedge clk_14m);
			while (h_state != state_number || state_dot != start_dot) @(negedge clk_14m);
			if (!cpu_enable) $fatal(1, "missing initial non-RAM completion");
			@(posedge clk_14m);
			#1;  // T65 presents its next address after this edge.
			peripheral_cycle = 1;
			rtc_cycle        = rtc;
			slow_mode        = slow;
			expected         = from_a ? 21 : 14;
			if (state_number == 63) expected += 2;
			accesses = 0;
			for (elapsed = 1; elapsed <= expected; elapsed++) begin
				@(negedge clk_14m);
				if (via_falling && peripheral_select) accesses++;
				if (cpu_enable !== (elapsed == expected))
					$fatal(
						1,
						"FSPACE from %0d/%0d slow=%b RTC=%b elapsed=%0d expected=%0d enable=%b",
						state_number,
						start_dot,
						slow,
						rtc,
						elapsed,
						expected,
						cpu_enable
					);
				checks++;
			end
			if (accesses != 1) $fatal(1, "peripheral selected %0d times during one access", accesses);
			@(posedge clk_14m);
			#1;
			peripheral_cycle = 0;
			rtc_cycle        = 0;
			slow_mode        = 0;
		end
	endtask

	initial begin
		if (!$test$plusargs("BOUNDARY"))
			for (integer state_number = 0; state_number <= 64; state_number++) begin
				access_device(state_number, 1, 0, 0);
				access_device(state_number, 1, 0, 1);
				access_device(state_number, 0, 0, 0);
				access_device(state_number, 0, 0, 1);
				access_device(state_number, 0, 1, 0);
				access_device(state_number, 0, 1, 1);
			end
		// Check every edge across a full frame, including line/frame wrap.
		while (h_count != 0 || v_count != 0) @(negedge clk_14m);
		for (integer line_number = 0; line_number < 262; line_number++) begin
			for (integer dot = 0; dot < 912; dot++) begin
				if (h_count != dot || v_count != line_number) $fatal(1, "scanner discontinuity");
				if (dot >= 896) begin
					if (q3 !== ((dot < 902) || (dot >= 905 && dot < 909))) $fatal(1, "HPE Q3 dot %0d", dot);
					if (cpu_enable !== (dot == 904 || dot == 911)) $fatal(1, "HPE CPU dot %0d", dot);
					if (via_rising !== (dot == 896) || via_falling !== (dot == 905))
						$fatal(1, "HPE PRE1M dot %0d", dot);
					if (!hblank || display_slot || character_slot) $fatal(1, "HPE must stay blank");
					checks++;
				end
				@(negedge clk_14m);
			end
		end
		if (!frame_tick || h_count != 0 || v_count != 0) $fatal(1, "frame boundary");
		$display("PASS peripheral arrival alignment, single select and extended-state edges (%0d checks)", checks);
		$finish;
	end
endmodule
