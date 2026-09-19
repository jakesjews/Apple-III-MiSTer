// Apple /// master timing and memory-slot arbitration.
//
// The counters follow the Level 2 Service Reference Manual and the decoded
// 342-0030/342-0046 PROMs: 64 ordinary 14-dot states plus one 16-dot state,
// 262 lines, and a CPU slot in each state, subject to peripheral waits. In fast
// mode the CPU may also use the video/refresh slot when neither needs RAM.
//
// The Apple /// Plus scan PROM (342-0145-A) and its text interlace switch add
// a field flip-flop and a 263-line field, which with the ordinary 262-line
// field makes a 525-line interlaced frame.

module apple3_timing (
	input logic clk_14m,
	input logic slow_mode,
	input logic screen_enable,
	input logic interlace,
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
	output logic [8:0] scan_line,
	output logic [6:0] h_state,
	output logic [3:0] state_dot,
	output logic       frame_tick,
	output logic       field
);

	logic       fast_a_slot;
	logic       iostop = 1'b0;
	logic       extended_state;
	logic [3:0] phase_dot;
	logic       long_field;

	// RRFSH output of Apple's 342-0030 scan-decode PROM. Kept as logic so
	// the independently supplied binary PROM can verify the complete frame.
	// The long field of the 342-0145-A never counts line 508, and that PROM
	// moves one of the lost refresh addresses to the line after it.
	function automatic logic scan_refresh(input logic [3:0] horizontal, input logic [4:0] vertical, input logic VBL,
										  input logic longer);
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
						   (!H3 && !H4 && !H5 && VA && VB && VC && V0 && V1 && VBL) ||
						   (longer && !H2 && !H3 && H4 && !H5 && VA && !VB && VC && V0 && V1 && VBL);
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

		// FIELDIN, pin 18 of the scan PROM, selects the long field when low.
		long_field     = !field;
		// The scan PROM adds refresh slots and suppresses others during VBL.
		// G10 retains the preceding scan decode as the counters enter HPE.
		// HPE forces blanking, but does not disable the refresh latch.
		refresh_slot   = scan_refresh((h_state == 7'd64) ? 4'hf : h_state[5:2], scan_line[4:0], vblank, long_field);
		character_slot = (h_state < 7'd64) && scan_character(h_state[5:2], scan_line[4:0], vblank);
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
		scan_line = 9'd256;
		h_state   = 7'd0;
		state_dot = 4'd0;
		field     = 1'b1;
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
				// V5..V0 and VC..VA count 256..511 and reload for the lines
				// before the next picture.  The reload's VB is the PROM's COMP
				// output, which is VA = 1 on line 511 and makes 250; the long
				// field's PROM answers 0 there for 248.  COMP also reloads VA
				// in every extended state, and the long field's 1 on entering
				// line 508 turns it straight into 509: 263 lines in all.
				if (scan_line == 9'd511) scan_line <= long_field ? 9'd248 : 9'd250;
				else if (long_field && scan_line == 9'd507) scan_line <= 9'd509;
				else scan_line <= scan_line + 1'b1;
				// v_count is the raster row: 0 on the first picture line.
				if (scan_line == 9'd255) begin
					v_count    <= 9'd0;
					frame_tick <= 1'b1;
				end else begin
					v_count <= v_count + 1'b1;
				end
				// RFIELD of the 342-0145-A is true at H5..H2 = 0 of line 448
				// alone, the one horizontal group the extended state makes an
				// odd five clocks long.  G10 latches it as FIELDOUT and the
				// switch returns that to FIELDIN, so the pair is a flip-flop
				// that changes over once a frame as blanking begins.
				if (scan_line == 9'd447) field <= !field;
			end else begin
				h_state <= h_state + 1'b1;
				h_count <= h_count + 1'b1;
			end
		end else begin
			state_dot <= state_dot + 1'b1;
			h_count   <= h_count + 1'b1;
		end

		// With the switch open RP10's 1K pull-up on FORCPAGE outweighs R63's
		// 3K to ground and FIELDIN rests high: the ordinary field, always.
		if (!interlace) field <= 1'b1;
	end

endmodule
