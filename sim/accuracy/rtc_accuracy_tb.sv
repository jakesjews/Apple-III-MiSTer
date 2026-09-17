`timescale 1ns / 1ps
// National Semiconductor AN-353, pp.8,16,17; Apple SRM p.7.11.
module rtc_accuracy_tb;
	logic clk = 0, reset = 1;
	always #5 clk = ~clk;
	logic [64:0] host_rtc = 0;
	logic read_strobe = 0, write_strobe = 0;
	logic [4:0] addr = 0;
	logic [7:0] data_in = 0;
	wire  [7:0] data_out;
	wire        irq;
	// Speed up time without changing counter sequencing.
	apple3_rtc #(.CLOCKS_PER_MS(1000)) dut (.*);
	integer failures = 0, ten_hz_events = 0, one_hz_events = 0;
	logic [7:0] sampled, year_latch;
	task automatic wr(input [4:0] a, input [7:0] value);
		@(negedge clk);
		addr         = a;
		data_in      = value;
		write_strobe = 1;
		@(negedge clk);
		write_strobe = 0;
	endtask
	task automatic rd(input [4:0] a, output [7:0] value);
		@(negedge clk);
		addr        = a;
		read_strobe = 1;
		#1;
		value = data_out;
		@(negedge clk);
		read_strobe = 0;
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
		// GO rounds 12:34:45 up to 12:35:00, not merely zeroing fractions.
		wr(4, 8'h12);
		wr(3, 8'h34);
		wr(2, 8'h45);
		wr(5'h15, 0);
		addr = 2;
		#1;
		check(data_out == 0, "GO clears seconds");
		addr = 3;
		#1;
		check(data_out == 8'h35, "GO rounds seconds >=40 into the next minute");

		// The tenth 10 Hz event coincides with second rollover and must not vanish.
		wr(5'h11, 8'h02);
		wr(1, 8'h99);
		wr(0, 8'h90);
		repeat (1010) @(negedge clk);
		addr = 5'h10;
		#1;
		check(data_out[1], "10 Hz interrupt also fires at whole-second rollover");

		// A multi-register read spanning a tick must be marked as possibly torn.
		addr        = 2;
		read_strobe = 1;
		@(negedge clk);
		read_strobe = 0;
		repeat (1010) @(negedge clk);
		addr = 5'h14;
		#1;
		check(data_out[0], "rollover status warns about reads spanning a counter update");

		// The motherboard RESET line is not a battery-backed clock power cycle.
		// apple3_core wires machine_reset to this reset input.
		wr(3, 8'h34);
		wr(2, 8'h56);
		@(negedge clk);
		reset = 1;
		repeat (3) @(negedge clk);
		reset = 0;
		addr  = 2;
		#1;
		check(data_out == 8'h56, "machine reset preserves battery-backed time");
		wr(5'h0b, 8'h34);
		wr(5'h11, 8'h06);
		reset = 1;
		repeat (11000) @(negedge clk);
		reset = 0;
		addr  = 5'h0b;
		#1;
		check(data_out == 8'h34, "machine reset preserves comparator RAM");
		addr = 5'h11;
		#1;
		check(data_out == 8'h06, "machine reset preserves interrupt control");
		addr = 1;
		#1;
		check(data_out != 0, "clock advances while machine reset is held");

		wr(3, 8'h34);
		wr(2, 8'h39);
		wr(1, 8'h99);
		wr(0, 8'h90);
		wr(5'h15, 0);
		addr = 2;
		#1;
		check(data_out == 0, "GO at 39 seconds clears seconds");
		addr = 3;
		#1;
		check(data_out == 8'h34, "GO below 40 seconds keeps the minute");
		addr = 1;
		#1;
		check(data_out == 0, "GO clears fractional seconds");
		wr(7, 8'h12);
		wr(6, 8'h31);
		wr(5, 8'h07);
		wr(4, 8'h23);
		wr(3, 8'h59);
		wr(2, 8'h40);
		wr(5'h15, 8'h55);
		addr = 3;
		#1;
		check(data_out == 0, "GO at 40 seconds carries through minute 59");
		addr = 4;
		#1;
		check(data_out == 0, "GO carries through midnight");
		addr = 5;
		#1;
		check(data_out == 1, "GO carries through week rollover");
		addr = 6;
		#1;
		check(data_out == 1, "GO carries through month rollover");
		addr = 7;
		#1;
		check(data_out == 1, "GO carries through year rollover");

		rd(5'h14, sampled);  // clear an earlier multi-register read
		wait (dut.millisecond_divider == 300);
		rd(2, sampled);
		rd(5'h14, sampled);
		check(sampled == 0, "counter snapshot outside the update window is safe");
		wait (dut.millisecond_divider == 20);
		rd(2, sampled);
		rd(5'h14, sampled);
		check(sampled == 1, "counter read inside the update window flags rollover");
		rd(5'h14, sampled);
		check(sampled == 0, "status read clears the rollover latch");
		wait (dut.millisecond_divider == 300);
		rd(2, sampled);
		repeat (1100) @(negedge clk);
		rd(5'h14, sampled);
		check(sampled == 1, "rollover remains latched after the update window ends");
		rd(5'h14, sampled);
		check(sampled == 0, "rollover remains clear until another counter read");

		// Hold the status address across the update-window edge. Changing the
		// address at the edge can hide a stale intermediate in the read mux.
		wait (dut.millisecond_divider == 300);
		rd(2, sampled);
		addr = 5'h14;
		#1;
		check(data_out == 0, "held status address is clear before the update window");
		wait (dut.millisecond_divider == 999);
		@(negedge clk);
		check(data_out == 1, "held status address sees the update window on its first clock");
		rd(5'h14, sampled);

		wr(5'h15, 0);
		wr(5'h11, 8'h06);
		rd(5'h10, sampled);
		for (integer ms = 0; ms < 1000; ms++) begin
			wait (dut.millisecond_tick);
			@(negedge clk);
			rd(5'h10, sampled);
			if (sampled[1]) ten_hz_events++;
			if (sampled[2]) one_hz_events++;
		end
		check(ten_hz_events == 10 && one_hz_events == 1, $sformatf(
			  "one second produces ten 10 Hz and one 1 Hz interrupts (%0d,%0d)", ten_hz_events, one_hz_events));
		// Host seed: Thursday 2026-09-17 23:58:07. SOS reads the year back from the
		// day and month latches as ((month << 2) | 3) & day (SOS 1.3 GET.TIME).
		host_rtc = {1'b1, 8'h40, 8'h04, 8'h26, 8'h09, 8'h17, 8'h23, 8'h58, 8'h07};
		repeat (3) @(negedge clk);
		rd(4, sampled);
		check(sampled == 8'h23, "host seed sets the hour");
		rd(7, sampled);
		check(sampled == 8'h09, "host seed sets the month");
		rd(6, sampled);
		check(sampled == 8'h17, "host seed sets the day of month");
		rd(5, sampled);
		check(sampled == 8'h05, "host weekday 4 (Thursday) becomes MM58167 day 5");
		rd(5'h0f, sampled);
		year_latch = {sampled[5:0], 2'b11};
		rd(5'h0e, sampled);
		check((year_latch & sampled) == 8'h26, "SOS reads the seeded year from the day and month latches");
		check(irq == 0, "don't-care year latches raise no compare interrupt");
		$display("RTC accuracy: %0d failed checks", failures);
		if (failures) $fatal(1, "RTC accuracy discrepancies");
		$finish;
	end
endmodule
