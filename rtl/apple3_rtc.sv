// National Semiconductor MM58167 clock/calendar used by the Apple ///.
//
// The register layout and interrupt semantics follow the MM58167 data sheet
// and are cross-checked against SOS's clock driver and the Apple /// service
// manual.  host_rtc uses MiSTer's MSM6242B-format BCD clock and seeds the
// battery-backed counters whenever its toggle bit changes.

module apple3_rtc #(
	parameter logic [13:0] CLOCKS_PER_MS = 14'd14318
) (
	input  logic        clk,
	input  logic        reset,
	input  logic [64:0] host_rtc,
	input  logic        read_strobe,
	input  logic        write_strobe,
	input  logic [4:0]  addr,
	input  logic [7:0]  data_in,
	output logic [7:0]  data_out,
	output logic        irq
);

	logic [13:0] millisecond_divider;
	logic [7:0] counter [0:7];
	logic [7:0] compare [0:7];
	logic [7:0] irq_status;
	logic [7:0] irq_control;
	logic [7:0] year_bcd;
	logic       host_toggle;
	logic       compare_match;
	logic       compare_match_d;
	logic       millisecond_tick;
	integer compare_index;
	integer reset_index;

	function automatic [7:0] bcd_increment(input logic [7:0] value);
		begin
			if (value[3:0] == 4'd9)
				bcd_increment = {value[7:4] + 1'b1, 4'h0};
			else
				bcd_increment = value + 1'b1;
		end
	endfunction

	function automatic [7:0] days_in_month(
		input logic [7:0] month,
		input logic [7:0] year
	);
		logic leap;
		begin
			leap = ((({3'b000, year[7:4], 1'b0} + {4'b0000, year[3:0]}) & 8'h03) == 0);
			case (month)
				8'h02: days_in_month = leap ? 8'h29 : 8'h28;
				8'h04, 8'h06, 8'h09, 8'h11: days_in_month = 8'h30;
				default: days_in_month = 8'h31;
			endcase
		end
	endfunction

	always_comb begin
		compare_match = 1'b1;
		for (compare_index = 0; compare_index < 8; compare_index = compare_index + 1) begin
			// A compare nibble with both high bits set is a don't-care.
			if ((compare_index != 0) && (compare[compare_index][3:2] != 2'b11) &&
			    (compare[compare_index][3:0] != counter[compare_index][3:0])) compare_match = 1'b0;
			if ((compare_index != 5) && (compare[compare_index][7:6] != 2'b11) &&
			    (compare[compare_index][7:4] != counter[compare_index][7:4])) compare_match = 1'b0;
		end

		case (addr)
			5'h00, 5'h01, 5'h02, 5'h03,
			5'h04, 5'h05, 5'h06, 5'h07: data_out = counter[addr[2:0]];
			5'h08, 5'h09, 5'h0a, 5'h0b,
			5'h0c, 5'h0d, 5'h0e, 5'h0f: data_out = compare[addr[2:0]];
			5'h10: data_out = irq_status;
			5'h11: data_out = irq_control;
			5'h14: data_out = 8'h00; // not busy
			default: data_out = 8'h00;
		endcase
		irq = |irq_status;
		millisecond_tick = (millisecond_divider == CLOCKS_PER_MS - 14'd1);
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			millisecond_divider <= 14'd0;
			host_toggle <= host_rtc[64];
			compare_match_d <= 1'b0;
			irq_status <= 8'h00;
			irq_control <= 8'h00;
			year_bcd <= 8'h80;
			counter[0] <= 8'h00;
			counter[1] <= 8'h00;
			counter[2] <= 8'h00;
			counter[3] <= 8'h00;
			counter[4] <= 8'h00;
			counter[5] <= 8'h01;
			counter[6] <= 8'h01;
			counter[7] <= 8'h01;
			for (reset_index = 0; reset_index < 8; reset_index = reset_index + 1)
				compare[reset_index] <= 8'hcc;
		end
		else begin
			compare_match_d <= compare_match;
			if (millisecond_tick) millisecond_divider <= 14'd0;
			else millisecond_divider <= millisecond_divider + 1'b1;

			if (host_rtc[64] != host_toggle) begin
				host_toggle <= host_rtc[64];
				counter[0] <= 8'h00;
				counter[1] <= 8'h00;
				counter[2] <= {1'b0, host_rtc[6:4], host_rtc[3:0]};
				counter[3] <= {1'b0, host_rtc[14:12], host_rtc[11:8]};
				counter[4] <= {2'b00, host_rtc[21:20], host_rtc[19:16]};
				counter[5] <= (host_rtc[50:48] == 0) ? 8'h01 :
				              {5'b00000, host_rtc[50:48]};
				counter[6] <= {2'b00, host_rtc[29:28], host_rtc[27:24]};
				counter[7] <= {3'b000, host_rtc[36], host_rtc[35:32]};
				year_bcd <= host_rtc[47:40];
			end
			else if (millisecond_tick) begin
				if (counter[0][7:4] != 4'd9) begin
					counter[0][7:4] <= counter[0][7:4] + 1'b1;
				end
				else begin
					counter[0] <= 8'h00;
					if (counter[1] != 8'h99) begin
						counter[1] <= bcd_increment(counter[1]);
						if ((counter[1][3:0] == 4'd9) && irq_control[1])
							irq_status[1] <= 1'b1;
					end
					else begin
						counter[1] <= 8'h00;
						if (irq_control[2]) irq_status[2] <= 1'b1;
						if (counter[2] != 8'h59) counter[2] <= bcd_increment(counter[2]);
						else begin
							counter[2] <= 8'h00;
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
									end
									else counter[5] <= counter[5] + 1'b1;
									if (counter[6] == days_in_month(counter[7], year_bcd)) begin
										counter[6] <= 8'h01;
										if (irq_control[7]) irq_status[7] <= 1'b1;
										if (counter[7] == 8'h12) begin
											counter[7] <= 8'h01;
											year_bcd <= bcd_increment(year_bcd);
										end
										else counter[7] <= bcd_increment(counter[7]);
									end
									else counter[6] <= bcd_increment(counter[6]);
								end
							end
						end
					end
				end
			end

			if (!compare_match_d && compare_match && irq_control[0])
				irq_status[0] <= 1'b1;

			if (read_strobe && (addr == 5'h10)) irq_status <= 8'h00;

			if (write_strobe) begin
				case (addr)
					5'h00, 5'h01, 5'h02, 5'h03,
					5'h04, 5'h05, 5'h06, 5'h07: counter[addr[2:0]] <= data_in;
					5'h08, 5'h09, 5'h0a, 5'h0b,
					5'h0c, 5'h0d, 5'h0e, 5'h0f: compare[addr[2:0]] <= data_in;
					5'h11: irq_control <= data_in;
					5'h12: if (data_in == 8'hff) begin
						counter[0] <= 8'h00; counter[1] <= 8'h00;
						counter[2] <= 8'h00; counter[3] <= 8'h00;
						counter[4] <= 8'h00; counter[5] <= 8'h01;
						counter[6] <= 8'h01; counter[7] <= 8'h01;
					end
					5'h13: if (data_in == 8'hff)
						for (reset_index = 0; reset_index < 8; reset_index = reset_index + 1)
							compare[reset_index] <= 8'h00;
					5'h15: begin
						counter[0] <= 8'h00;
						counter[1] <= 8'h00;
					end
					default: ;
				endcase
			end
		end
	end

endmodule
