// Apple /// master timing and memory-slot arbitration.
//
// The counters follow the Level 2 Service Reference Manual and the decoded
// 342-0030/342-0046 PROMs: 64 ordinary 14-dot states plus one 16-dot state,
// 262 lines, and a CPU slot in each state, subject to peripheral waits. In fast
// mode the CPU may also use the video/refresh slot when neither needs RAM.

module apple3_timing (
	input logic clk_14m,
	input logic slow_mode,
	input logic screen_enable,
	input logic peripheral_cycle,
	input logic rtc_cycle,
	input logic ram_cycle,

	output logic       cpu_enable,
	output logic       via_rising,
	output logic       via_falling,
	output logic       peripheral_select,
	output logic       q3,
	output logic       pixel_enable,
	output logic       hblank,
	output logic       vblank,
	output logic       display_slot,
	output logic       refresh_slot,
	output logic       character_slot,
	output logic [9:0] h_count,
	output logic [8:0] v_count,
	output logic [6:0] h_state,
	output logic [3:0] state_dot,
	output logic       frame_tick
);

	logic       fast_a_slot;
	logic       iostop = 1'b0;
	logic       extended_state;
	logic [3:0] phase_dot;
	logic [4:0] scan_vertical;

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

	// RTCWRT output of the same PROM: the character-generator write window.
	// Its eight product terms reduce to one condition, and the binary PROM
	// confirms the reduction over the whole address space.
	//
	//   RTCWRT = /H2*/H3*/H4*/H5*/VA*/VB*/VC*/V0*/V1*VBL + (seven more)
	//          = VBL * /H3 * /H4 * /H5 * (H2 == VA) * (V0 == VB) * (V1 == VC)
	//
	// The scanner is reading the text-page screen holes at those states, so
	// each window transfers four of a hole's eight bytes into the character
	// RAM.  Every one of them is also a refresh state, which is what keeps
	// the processor from taking the slot the transfer needs. The decode held
	// from H=63 during the extended state has RTCWRT low.
	function automatic logic scan_character(input logic [3:0] horizontal, input logic [4:0] vertical, input logic VBL);
		logic H2, H3, H4, H5, VA, VB, VC, V0, V1;
		begin
			{H5, H4, H3, H2}     = horizontal;
			{V1, V0, VC, VB, VA} = vertical;
			scan_character       = VBL && !H3 && !H4 && !H5 && (H2 == VA) && (V0 == VB) && (V1 == VC);
		end
	endfunction

	always_comb begin
		hblank       = (h_count >= 10'd560);
		vblank       = (v_count >= 9'd192);
		pixel_enable = 1'b1;

		// The scan PROM adds refresh slots and suppresses others during VBL.
		// Its vertical counter wraps from 511 to 250 for the final six lines.
		scan_vertical  = (v_count < 9'd256) ? v_count[4:0] : v_count[4:0] - 5'd6;
		// G10 retains the preceding scan decode as the counters enter HPE.
		// HPE forces blanking, but does not disable the refresh latch.
		refresh_slot   = scan_refresh((h_state == 7'd64) ? 4'hf : h_state[5:2], scan_vertical, vblank);
		character_slot = (h_state < 7'd64) && scan_character(h_state[5:2], scan_vertical, vblank);
		display_slot   = screen_enable && !vblank && (h_state < 7'd40);
		fast_a_slot    = !slow_mode && !peripheral_cycle && (!ram_cycle || (!display_slot && !refresh_slot));

		// HPE holds the parallel-loaded Q register at the START of the A
		// slot. Every subsequent edge moves two dots, including the CPU and
		// PRE1M edges; padding the end of the state gives the wrong bus timing.
		extended_state = (h_state == 7'd64);
		phase_dot      = extended_state ? ((state_dot < 4'd2) ? 4'd0 : state_dot - 4'd2) : state_dot;

		// 342-0046 PHASEN. D11 samples FSPACE at C1M rising. A new address
		// following an A-slot completion misses that edge (SRM 5.12), so the
		// first B completion is suppressed. The next complete PRE1M cycle
		// services the device. Slow VIA/ACIA cycles bypass this delay; C07x
		// still requires IOSTOP even in slow mode.
		cpu_enable = ((phase_dot == 4'd13) &&
			(iostop || !peripheral_cycle || (slow_mode && !rtc_cycle))) ||
			((phase_dot == 4'd6) && fast_a_slot);
		// CS6522 from the same PROM. In particular the first PRE1M falling
		// edge of a late fast access must not write/acknowledge the VIA.
		peripheral_select = (iostop && peripheral_cycle) ||
			((phase_dot < 4'd7) && peripheral_cycle) || ((phase_dot >= 4'd7) && iostop);
		via_rising = (state_dot == 4'd0);
		via_falling = (phase_dot == 4'd7);
		// Q3 is the asymmetric 2.045 MHz disk/state-machine clock: four
		// master clocks high and three low.  HPE freezes the shift register
		// for two extra clocks at the start of the extended A slot.
		q3 = (phase_dot < 4'd4) || ((phase_dot >= 4'd7) && (phase_dot < 4'd11));
	end

	// The timing chain starts at zero when the FPGA is configured and is not
	// touched by machine reset, so video sync is continuous through a reset
	// as it is on the motherboard.
	initial begin
		h_count   = 10'd0;
		v_count   = 9'd0;
		h_state   = 7'd0;
		state_dot = 4'd0;
	end

	always_ff @(posedge clk_14m) begin
		frame_tick <= 1'b0;
		// Sample before T65 presents its next A-slot address. On the board
		// that address has not settled at D11's C1M edge yet (SRM 5.12).
		if (phase_dot == 4'd6) iostop <= peripheral_cycle;

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
