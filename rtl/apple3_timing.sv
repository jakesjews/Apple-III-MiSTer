// Apple /// master timing and memory-slot arbitration.
//
// The counters follow the Level 2 Service Reference Manual and the decoded
// 342-0030/342-0046 PROMs: 64 ordinary 14-dot states plus one 16-dot state,
// 262 lines, and one guaranteed CPU slot per state.  In fast mode the CPU may
// also use the video/refresh slot when neither consumer needs RAM.

module apple3_timing (
	input logic clk_14m,
	input logic slow_mode,
	input logic screen_enable,
	input logic peripheral_cycle,
	input logic ram_cycle,

	output logic       cpu_enable,
	output logic       via_rising,
	output logic       via_falling,
	output logic       q3,
	output logic       pixel_enable,
	output logic       hblank,
	output logic       vblank,
	output logic       display_slot,
	output logic       refresh_slot,
	output logic [9:0] h_count,
	output logic [8:0] v_count,
	output logic [6:0] h_state,
	output logic [3:0] state_dot,
	output logic       frame_tick
);

	logic       fast_a_slot;
	logic [2:0] q_divider;

	// RRFSH output of Apple's 342-0030 scan-decode PROM. Kept as logic so
	// the independently supplied binary PROM can verify the complete frame.
	function automatic logic scan_refresh(input logic [3:0] horizontal, input logic [4:0] vertical, input logic VBL);
		logic H2, H3, H4, H5, VA, VB, VC, V0, V1;
		begin
			{H5, H4, H3, H2} = horizontal;
			{V1, V0, VC, VB, VA} = vertical;
			scan_refresh = (!H2 && !H3 && !H4 && !VA && !VB && !VC) ||
						   (H2 && !H3 && !H4 && VA && !VB && !VC) ||
						   (!H2 && H3 && !H4 && !VA && VB && !VC) ||
						   (H2 && H3 && !H4 && VA && VB && !VC) ||
						   (!H2 && !H3 && H4 && !VA && !VB && VC) ||
						   (H2 && !H3 && H4 && VA && !VB && VC && !VBL) ||
						   (!H2 && H3 && H4 && !VA && VB && VC) ||
						   (H2 && H3 && H4 && VA && VB && VC) ||
						   (!H3 && !H4 && !H5 && VA && !VB && !VC && !V0 && !V1 && VBL) ||
						   (H2 && !H3 && H4 && VA && !VB && VC && !V1) ||
						   (H2 && H3 && H4 && H5 && VA && !VB && !VC && V0 && !V1 && VBL) ||
						   (!H2 && !H4 && !H5 && !VA && VB && !VC && V0 && !V1 && VBL) ||
						   (!H3 && !H4 && !H5 && VA && VB && !VC && V0 && !V1 && VBL) ||
						   (H2 && !H4 && !H5 && VA && VB && !VC && V0 && !V1 && VBL) ||
						   (H2 && H3 && H5 && VA && VB && !VC && !V0 && V1 && VBL) ||
						   (!H2 && !H3 && !H5 && !VA && !VB && VC && !V0 && V1 && VBL) ||
						   (!H3 && !H4 && !H5 && VA && !VB && VC && !V0 && V1 && VBL) ||
						   (H2 && !H3 && !H5 && VA && !VB && VC && !V0 && V1 && VBL) ||
						   (H2 && !H3 && H4 && VA && !VB && VC && !V0) ||
						   (H2 && !H3 && H4 && VA && !VB && VC && V0) ||
						   (H2 && H4 && H5 && VA && !VB && VC && V0 && V1 && VBL) ||
						   (!H2 && !H3 && !H4 && !H5 && VB && VC && V0 && V1 && VBL) ||
						   (!H3 && !H4 && !H5 && VA && VB && VC && V0 && V1 && VBL);
		end
	endfunction

	always_comb begin
		hblank       = (h_count >= 10'd560);
		vblank       = (v_count >= 9'd192);
		pixel_enable = 1'b1;

		// The scan PROM adds refresh slots and suppresses others during VBL.
		// Its vertical counter wraps from 511 to 250 for the final six lines.
		refresh_slot = (h_state < 7'd64) &&
			scan_refresh(h_state[5:2], (v_count < 9'd256) ? v_count[4:0] : v_count[4:0] - 5'd6, vblank);
		display_slot = screen_enable && !vblank && (h_state < 7'd40);
		fast_a_slot = !slow_mode && !peripheral_cycle && (!ram_cycle || (!display_slot && !refresh_slot));

		// Dot 6 is the optional A slot and dot 13 is the guaranteed B slot.
		// Peripheral accesses run on the 1 MHz slot and are never doubled.
		cpu_enable  = (state_dot == 4'd13) || ((state_dot == 4'd6) && fast_a_slot);
		via_rising  = (state_dot == 4'd0);
		via_falling = (state_dot == 4'd7);
		// Q3 is the asymmetric 2.045 MHz disk/state-machine clock: four
		// master clocks high and three low.  HPE freezes the shift register
		// for the final two clocks of each 912-clock scan line.
		q3          = (q_divider < 3'd4);
	end

	// The timing chain starts at zero when the FPGA is configured and is not
	// touched by machine reset, so video sync is continuous through a reset
	// as it is on the motherboard.
	initial begin
		h_count   = 10'd0;
		v_count   = 9'd0;
		h_state   = 7'd0;
		state_dot = 4'd0;
		q_divider = 3'd0;
	end

	always_ff @(posedge clk_14m) begin
		frame_tick <= 1'b0;
		if (!((h_state == 7'd64) && (state_dot >= 4'd14))) begin
			if (q_divider == 3'd6) q_divider <= 3'd0;
			else q_divider <= q_divider + 1'b1;
		end

		if (((h_state == 7'd64) && (state_dot == 4'd15)) || ((h_state != 7'd64) && (state_dot == 4'd13))) begin
			state_dot <= 4'd0;
			if (h_state == 7'd64) begin
				h_state <= 7'd0;
				h_count <= 10'd0;
				if (v_count == 9'd261) begin
					v_count    <= 9'd0;
					frame_tick <= 1'b1;
				end else begin
					v_count <= v_count + 1'b1;
				end
			end else begin
				h_state <= h_state + 1'b1;
				h_count <= h_count + 1'b1;
			end
		end else begin
			state_dot <= state_dot + 1'b1;
			h_count   <= h_count + 1'b1;
		end
	end

endmodule
