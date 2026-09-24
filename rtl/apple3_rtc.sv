// National Semiconductor MM58167 clock/calendar used by the Apple ///.
//
// The register layout and interrupt semantics follow the MM58167 data sheet
// and are cross-checked against SOS's clock driver and the Apple /// service
// manual.  host_rtc uses MiSTer's MSM6242B-format BCD clock, which Main sends
// at start and every minute.  It keeps the chip set, as a battery would have,
// until the Apple /// writes the time, the RAM or a reset or GO command; from
// then on the machine owns the clock and host updates are ignored.  Neither
// the boot ROM nor SOS's boot writes any of those registers.

module apple3_rtc #(
	parameter logic [13:0] CLOCKS_PER_MS = 14'd14318
) (
	input  logic        clk,
	input  logic        reset,
	input  logic [64:0] host_rtc,
	input  logic        read_strobe,
	input  logic        write_strobe,
	input  logic [ 4:0] addr,
	input  logic [ 7:0] data_in,
	output logic [ 7:0] data_out,
	output logic        irq
);

	logic [13:0] millisecond_divider;
	logic [ 7:0] counter             [0:7];
	logic [ 7:0] compare             [0:7];
	logic [ 7:0] irq_status;
	logic [ 7:0] irq_control;
	logic        host_toggle;
	logic        guest_set;
	logic        compare_match;
	logic        compare_match_d;
	logic        millisecond_tick;
	// AN-353 describes a 150 us ripple-counter update window each millisecond.
	localparam integer ROLLOVER_CLOCKS = (CLOCKS_PER_MS * 150 + 999) / 1000;
	logic counter_read_pending, rollover_status, rollover_window;
	logic   go_command;
	integer compare_index;
	integer reset_index;

	function automatic [7:0] bcd_increment(input logic [7:0] value);
		begin
			if (value[3:0] == 4'd9) bcd_increment = {value[7:4] + 1'b1, 4'h0};
			else bcd_increment = value + 1'b1;
		end
	endfunction

	// Data sheet Table I: the bits each counter has. The others read as zero
	// and ignore writes, 46 bits in all.
	function automatic [7:0] counter_mask(input logic [2:0] index);
		case (index)
			3'd0:       counter_mask = 8'hf0;
			3'd1:       counter_mask = 8'hff;
			3'd2, 3'd3: counter_mask = 8'h7f;
			3'd4, 3'd6: counter_mask = 8'h3f;
			3'd5:       counter_mask = 8'h07;
			default:    counter_mask = 8'h1f;
		endcase
	endfunction

	// AN-353 figure 2: the RAM has no nibble at the low half of 08 or the high
	// half of 0D, the digits the comparator ignores.
	function automatic [7:0] ram_mask(input logic [2:0] index);
		ram_mask = (index == 3'd0) ? 8'hf0 : (index == 3'd5) ? 8'h0f : 8'hff;
	endfunction

	// A counter rolls over when it decodes its highest value plus one. For the
	// day of month that is 32 in any month, 31 in a 30-day month and 29 in
	// February: the chip has no year and no leap day. AN-353 has software write
	// February 31 for the 29th, which the next day carries to March 1.
	function automatic logic day_rolls(input logic [7:0] day, input logic [7:0] month);
		day_rolls = (day == 8'h32) || ((day == 8'h29) && (month == 8'h02)) ||
			((day == 8'h31) && ((month == 8'h04) || (month == 8'h06) || (month == 8'h09) || (month == 8'h11)));
	endfunction

	function automatic [7:0] next_month(input logic [7:0] month);
		next_month = (month == 8'h12) ? 8'h01 : bcd_increment(month);
	endfunction

	always_comb begin
		compare_match = 1'b1;
		for (compare_index = 0; compare_index < 8; compare_index = compare_index + 1) begin
			// A compare nibble with both high bits set is a don't-care.
			if ((compare_index != 0) && (compare[compare_index][3:2] != 2'b11) &&
				(compare[compare_index][3:0] != counter[compare_index][3:0]))
				compare_match = 1'b0;
			if ((compare_index != 5) && (compare[compare_index][7:6] != 2'b11) &&
				(compare[compare_index][7:4] != counter[compare_index][7:4]))
				compare_match = 1'b0;
		end

		// The status read mux must use this clock's window value.
		rollover_window = (millisecond_divider < ROLLOVER_CLOCKS) || (millisecond_divider == CLOCKS_PER_MS - 14'd1);
		case (addr)
			5'h00, 5'h01, 5'h02, 5'h03, 5'h04, 5'h05, 5'h06, 5'h07: data_out = counter[addr[2:0]];
			5'h08, 5'h09, 5'h0a, 5'h0b, 5'h0c, 5'h0d, 5'h0e, 5'h0f: data_out = compare[addr[2:0]];
			5'h10: data_out = irq_status;
			5'h11: data_out = irq_control;
			5'h14: data_out = {7'd0, rollover_status || (counter_read_pending && rollover_window)};
			default: data_out = 8'h00;
		endcase
		irq              = |irq_status;
		go_command       = !reset && write_strobe && (addr == 5'h15);
		millisecond_tick = (millisecond_divider == CLOCKS_PER_MS - 14'd1);
	end

	// The motherboard RESET signal does not reset this battery-backed chip.
	// FPGA configuration initializes it; register writes provide the MM58167's
	// counter/RAM reset commands. Time and alarm state survive machine resets.
	initial begin
		millisecond_divider  = 14'd0;
		host_toggle          = 1'b0;
		guest_set            = 1'b0;
		compare_match_d      = 1'b0;
		counter_read_pending = 1'b0;
		rollover_status      = 1'b0;
		irq_status           = 8'h00;
		irq_control          = 8'h00;
		counter[0]           = 8'h00;
		counter[1]           = 8'h00;
		counter[2]           = 8'h00;
		counter[3]           = 8'h00;
		counter[4]           = 8'h00;
		counter[5]           = 8'h01;
		counter[6]           = 8'h01;
		counter[7]           = 8'h01;
		for (integer i = 0; i < 8; i = i + 1) compare[i] = 8'hcc & ram_mask(3'(i));
	end

	// Both ordinary seconds carry and GO rounding use the same calendar chain.
	task automatic advance_minute;
		begin
			if (irq_control[3]) irq_status[3] <= 1'b1;
			if (counter[3] != 8'h59) counter[3] <= bcd_increment(counter[3]);
			else begin
				counter[3] <= 8'h00;
				if (irq_control[4]) irq_status[4] <= 1'b1;
				if (counter[4] != 8'h23) counter[4] <= bcd_increment(counter[4]);
				else begin
					counter[4] <= 8'h00;
					if (irq_control[5]) irq_status[5] <= 1'b1;
					if (counter[5] == 8'h07) begin
						counter[5] <= 8'h01;
						if (irq_control[6]) irq_status[6] <= 1'b1;
					end else counter[5] <= counter[5] + 1'b1;
					if (day_rolls(bcd_increment(counter[6]), counter[7])) begin
						counter[6] <= 8'h01;
						counter[7] <= next_month(counter[7]);
						if (irq_control[7]) irq_status[7] <= 1'b1;
					end else counter[6] <= bcd_increment(counter[6]);
				end
			end
		end
	endtask

	always_ff @(posedge clk) begin
		compare_match_d <= compare_match;
		if (millisecond_tick) millisecond_divider <= 14'd0;
		else millisecond_divider <= millisecond_divider + 1'b1;

		// AN-353 figure 23: a counter read arms the rollover detector; status
		// read returns the sticky result and clears it for the next snapshot.
		if (counter_read_pending && rollover_window) rollover_status <= 1'b1;
		if (!reset && read_strobe && (addr < 5'h08)) begin
			counter_read_pending <= 1'b1;
			if (rollover_window) rollover_status <= 1'b1;
		end
		if (!reset && read_strobe && (addr == 5'h14)) begin
			counter_read_pending <= 1'b0;
			rollover_status      <= 1'b0;
		end

		host_toggle <= host_rtc[64];
		if ((host_rtc[64] != host_toggle) && !guest_set) begin
			millisecond_divider <= 14'd0;
			if (counter_read_pending) rollover_status <= 1'b1;
			counter[0] <= 8'h00;
			counter[1] <= 8'h00;
			counter[2] <= {1'b0, host_rtc[6:4], host_rtc[3:0]};
			counter[3] <= {1'b0, host_rtc[14:12], host_rtc[11:8]};
			counter[4] <= {2'b00, host_rtc[21:20], host_rtc[19:16]};
			// MiSTer counts weekdays from Sunday = 0; the MM58167 and SOS from 1.
			counter[5] <= {5'b00000, host_rtc[50:48]} + 8'h01;
			counter[6] <= {2'b00, host_rtc[29:28], host_rtc[27:24]};
			counter[7] <= {3'b000, host_rtc[36], host_rtc[35:32]};
			// The chip has no year counter. SOS SET.TIME stores the two-digit year
			// in the day and month compare latches with the other bits left in the
			// don't-care state, and GET.TIME reads it back as ((month << 2) | 3) &
			// day. A year of 00 makes Apple Pascal treat the clock as never set and
			// overwrite it with the date saved on the boot disk.
			compare[6] <= host_rtc[47:40] | 8'hcc;
			compare[7] <= {2'b00, host_rtc[47:42]} | 8'hcc;
		end else if (go_command) begin
			// GO clears milliseconds through seconds, rounding up at 40 s.
			millisecond_divider <= 14'd0;
			counter[0]          <= 8'h00;
			counter[1]          <= 8'h00;
			counter[2]          <= 8'h00;
			if (counter[2] >= 8'h40) advance_minute();
		end else if (millisecond_tick) begin
			if (counter[0][7:4] != 4'd9) begin
				counter[0][7:4] <= counter[0][7:4] + 1'b1;
			end else begin
				counter[0] <= 8'h00;
				// The 10 Hz edge includes the .99 -> .00 transition.
				if ((counter[1][3:0] == 4'd9) && irq_control[1]) irq_status[1] <= 1'b1;
				if (counter[1] != 8'h99) counter[1] <= bcd_increment(counter[1]);
				else begin
					counter[1] <= 8'h00;
					if (irq_control[2]) irq_status[2] <= 1'b1;
					if (counter[2] != 8'h59) counter[2] <= bcd_increment(counter[2]);
					else begin
						counter[2] <= 8'h00;
						advance_minute();
					end
				end
			end
		end else if (day_rolls(counter[6], counter[7])) begin
			// A counter written with its overflow value resets when the write is
			// removed and may carry: February 29 reads back as March 1 (AN-353).
			counter[6] <= 8'h01;
			counter[7] <= next_month(counter[7]);
			if (irq_control[7]) irq_status[7] <= 1'b1;
		end else if (counter[7] == 8'h13) counter[7] <= 8'h01;

		if (!compare_match_d && compare_match && irq_control[0]) irq_status[0] <= 1'b1;

		if (!reset && read_strobe && (addr == 5'h10)) irq_status <= 8'h00;

		if (!reset && write_strobe) begin
			if ((addr < 5'h10) || (addr == 5'h12) || (addr == 5'h13) || (addr == 5'h15)) guest_set <= 1'b1;
			case (addr)
				5'h00, 5'h01, 5'h02, 5'h03, 5'h04, 5'h05, 5'h06, 5'h07:
				counter[addr[2:0]] <= data_in & counter_mask(addr[2:0]);
				5'h08, 5'h09, 5'h0a, 5'h0b, 5'h0c, 5'h0d, 5'h0e, 5'h0f:
				compare[addr[2:0]] <= data_in & ram_mask(addr[2:0]);
				5'h11: irq_control <= data_in;
				5'h12:
				if (data_in == 8'hff) begin
					counter[0] <= 8'h00;
					counter[1] <= 8'h00;
					counter[2] <= 8'h00;
					counter[3] <= 8'h00;
					counter[4] <= 8'h00;
					counter[5] <= 8'h01;
					counter[6] <= 8'h01;
					counter[7] <= 8'h01;
				end
				5'h13:
				if (data_in == 8'hff)
					for (reset_index = 0; reset_index < 8; reset_index = reset_index + 1) compare[reset_index] <= 8'h00;
				default: ;
			endcase
		end
	end

endmodule
