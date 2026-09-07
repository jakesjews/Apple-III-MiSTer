`timescale 1ns/1ps

module timing_tb;
	logic clk_14m = 0, reset = 1;
	logic slow_mode = 0, screen_enable = 0, peripheral_cycle = 0;
	logic ram_cycle = 1;
	wire cpu_enable, via_rising, via_falling, q3, pixel_enable;
	wire hblank, vblank, display_slot, refresh_slot, frame_tick;
	wire [9:0] h_count;
	wire [8:0] v_count;
	wire [6:0] h_state;
	wire [3:0] state_dot;
	integer cpu_count, rise_count, fall_count, refresh_count, q3_rise_count;
	logic q3_old;

	apple3_timing dut (.*);
	always #5 clk_14m = ~clk_14m;

	task automatic count_line(output integer cpus, output integer rises,
	                          output integer falls, output integer refreshes);
	integer i;
	begin
		cpus = 0; rises = 0; falls = 0; refreshes = 0; q3_rise_count = 0;
		q3_old = q3;
		@(negedge clk_14m);
		while (h_count != 10'd0) @(negedge clk_14m);
		for (i = 0; i < 912; i = i + 1) begin
			@(negedge clk_14m);
			if (cpu_enable) cpus = cpus + 1;
			if (via_rising) rises = rises + 1;
			if (via_falling) falls = falls + 1;
			if ((state_dot == 4'd6) && refresh_slot) refreshes = refreshes + 1;
			if (q3 && !q3_old) q3_rise_count = q3_rise_count + 1;
			q3_old = q3;
		end
		if (h_count != 10'd0) $fatal(1, "line did not wrap after 912 clocks");
		if (q3_rise_count != 130)
			$fatal(1, "Q3 cycles per line=%0d, expected 130", q3_rise_count);
	end
	endtask

	initial begin
		repeat (2) @(posedge clk_14m);
		reset = 0;
		count_line(cpu_count, rise_count, fall_count, refresh_count);
		if (cpu_count != 122 || rise_count != 65 || fall_count != 65 || refresh_count != 8)
			$fatal(1, "fast blank line: cpu=%0d rise=%0d fall=%0d refresh=%0d",
			       cpu_count, rise_count, fall_count, refresh_count);

		slow_mode = 1;
		count_line(cpu_count, rise_count, fall_count, refresh_count);
		if (cpu_count != 65) $fatal(1, "slow line cpu slots=%0d", cpu_count);

		slow_mode = 0;
		peripheral_cycle = 1;
		count_line(cpu_count, rise_count, fall_count, refresh_count);
		if (cpu_count != 65) $fatal(1, "peripheral line cpu slots=%0d", cpu_count);

		peripheral_cycle = 0;
		screen_enable = 1;
		count_line(cpu_count, rise_count, fall_count, refresh_count);
		if (cpu_count >= 122 || cpu_count <= 65)
			$fatal(1, "display arbitration cpu slots=%0d", cpu_count);

		ram_cycle = 0;
		count_line(cpu_count, rise_count, fall_count, refresh_count);
		if (cpu_count != 130) $fatal(1, "non-RAM cycles lost slots during display/refresh: %0d", cpu_count);
		peripheral_cycle = 1;
		count_line(cpu_count, rise_count, fall_count, refresh_count);
		if (cpu_count != 65) $fatal(1, "non-RAM peripheral cycle was doubled: %0d", cpu_count);
		peripheral_cycle = 0;
		slow_mode = 1;
		count_line(cpu_count, rise_count, fall_count, refresh_count);
		if (cpu_count != 65) $fatal(1, "slow non-RAM cycle was doubled: %0d", cpu_count);
		slow_mode = 0;

		// One complete line is exactly 912 master clocks.  Check the special
		// final state explicitly rather than relying only on slot totals.
		while (h_state != 7'd64 || state_dot != 4'd0) @(negedge clk_14m);
		if (h_count != 10'd896) $fatal(1, "state 64 starts at dot %0d", h_count);
		repeat (16) @(negedge clk_14m);
		if (h_count != 10'd0) $fatal(1, "line length is not 912 clocks");

		$display("PASS apple3_timing");
		$finish;
	end
endmodule
