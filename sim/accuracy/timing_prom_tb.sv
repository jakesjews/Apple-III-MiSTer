`timescale 1ns / 1ps
// Compares RTL to the *binary* 341-0030 scan and 342-0046 timing PROMs.
// Input pin assignments: bitsavers A3PROMs decoded headers; SRM ch.5 counters.
module timing_prom_tb;
	logic clk_14m = 0, slow_mode = 0, screen_enable = 1, peripheral_cycle = 0;
	logic rtc_cycle = 0;
	wire  peripheral_select;
	logic ram_cycle = 0;
	always #5 clk_14m = ~clk_14m;
	wire cpu_enable, via_rising, via_falling, q3, pixel_enable, hblank, vblank;
	wire display_slot, refresh_slot, character_slot, frame_tick;
	wire [9:0] h_count;
	wire [8:0] v_count;
	wire [6:0] h_state;
	wire [3:0] state_dot;
	apple3_timing dut (.*);
	logic [7:0] scan_prom[0:2047], timing_prom[0:1023];
	string scan_path, timing_path;
	integer vertical, horizontal, scan_address, checked = 0, mismatches = 0;
	integer blank_mismatches = 0, visible_mismatches = 0, failures = 0;
	integer missing_refresh = 0, extra_refresh = 0;
	integer phase_checks = 0, phase_errors = 0, phase_address, ram_reserved;
	integer character_mismatches = 0, character_windows = 0, window_mismatches = 0;
	initial begin
		if (!$value$plusargs("SCAN=%s", scan_path) || !$value$plusargs("TIMING=%s", timing_path))
			$fatal(1, "supply +SCAN=<hex> +TIMING=<hex>");
		$readmemh(scan_path, scan_prom);
		$readmemh(timing_path, timing_prom);
		repeat (3) @(negedge clk_14m);
		// During display, a fast non-RAM cycle has PHASEN high even in A slot.
		// C1M=0,nC07X=1,RAMEN=0,DSPLY=1,nIOSTOPD=1,C-FXXX=0,
		// nFSPACE=1,R/W=1,RWPROT=0,nSEL2M=0 -> PROM address $0DA.
		wait (h_state == 10 && state_dot == 6);
		#1;
		if (cpu_enable !== timing_prom['h0da][1]) begin
			failures++;
			$display("FAIL: fast non-RAM display A-slot: PROM PHASEN=%b, RTL CPU enable=%b", timing_prom['h0da][1],
					 cpu_enable);
		end
		// G10 retains H=63's decode on entry to HPE. Unlike a new ordinary
		// state, the extended A completion is at dot 8.
		wait (v_count == 0 && h_count == 0);
		wait (h_count == 1);
		for (integer clocks = 0; clocks < 912 * 262; clocks++) begin
			@(negedge clk_14m);
			if (state_dot == ((h_state == 64) ? 8 : 6)) begin
				// Vertical hardware counter runs 256..511 then 250..255.
				vertical = (v_count < 256) ? v_count + 256 : v_count - 6;
				horizontal = (h_state == 64) ? 63 : int'(h_state);
				scan_address=(((vertical>>5)&1)&((vertical>>8)&1)) |
		  ((horizontal>>2)<<1) | ((vertical&7)<<5) |
		  (((vertical>>3)&1)<<8) | (((vertical>>4)&1)<<9) |
		  ((v_count>=192)<<10);
				checked++;
				// Compare both RAMEN values, screen settings and clock selections
				// to PHASEN at C1M=0. I/O wait-state timing is a separate contract.
				for (integer config_bits = 0; config_bits < 8; config_bits++) begin
					ram_cycle     = config_bits[0];
					screen_enable = config_bits[1];
					slow_mode     = config_bits[2];
					ram_reserved  = (screen_enable && v_count < 192 && h_state < 40) || scan_prom[scan_address][4];
					phase_address = 'hd2 + (ram_cycle << 2) + (ram_reserved << 3) + (slow_mode << 9);
					#0.01;
					phase_checks++;
					if (cpu_enable !== timing_prom[phase_address][1]) begin
						if (phase_errors < 5)
							$display(
								"PHASEN mismatch v=%0d h=%0d PROM[%x] config=%b",
								v_count,
								h_state,
								phase_address,
								config_bits
							);
						phase_errors++;
					end
				end
				ram_cycle     = 1;
				screen_enable = 1;
				slow_mode     = 0;
				#0.01;
				if (refresh_slot !== scan_prom[scan_address][4]) begin
					if (mismatches < 8)
						$display(
							"  refresh mismatch V=%0d H=%0d PROM[%03x]=%b RTL=%b",
							v_count,
							h_state,
							scan_address,
							scan_prom[scan_address][4],
							refresh_slot
						);
					mismatches++;
					if (scan_prom[scan_address][4]) missing_refresh++;
					else extra_refresh++;
					if (v_count >= 192) blank_mismatches++;
					else visible_mismatches++;
				end
				// RTCWRT (D2) opens the character-generator write window; -RBL
				// (D3) is high for the 40 displayed states of a visible line.
				if (scan_prom[scan_address][2]) character_windows++;
				if (character_slot !== scan_prom[scan_address][2]) begin
					if (character_mismatches < 8)
						$display(
							"  RTCWRT mismatch V=%0d H=%0d PROM[%03x]=%b RTL=%b",
							v_count,
							h_state,
							scan_address,
							scan_prom[scan_address][2],
							character_slot
						);
					character_mismatches++;
				end
				if (!(hblank || vblank) !== scan_prom[scan_address][3]) begin
					if (window_mismatches < 8)
						$display(
							"  -RBL mismatch V=%0d H=%0d PROM[%03x]=%b RTL display=%b",
							v_count,
							h_state,
							scan_address,
							scan_prom[scan_address][3],
							!(hblank || vblank)
						);
					window_mismatches++;
				end
			end
		end
		$display("refresh PROM: %0d/%0d mismatches (visible=%0d, blank=%0d)", mismatches, checked, visible_mismatches,
				 blank_mismatches);
		$display("refresh differences: missing=%0d extra=%0d", missing_refresh, extra_refresh);
		if (checked != 65 * 262) $fatal(1, "incomplete frame comparison: %0d", checked);
		$display("A-slot PHASEN: %0d/%0d mismatches", phase_errors, phase_checks);
		$display("character write PROM: %0d/%0d mismatches (%0d windows)", character_mismatches, checked,
				 character_windows);
		$display("display window PROM: %0d/%0d mismatches", window_mismatches, checked);
		if (character_windows != 72) $fatal(1, "expected 72 RTCWRT states per frame, PROM has %0d", character_windows);
		if (mismatches || failures || phase_errors || character_mismatches || window_mismatches)
			$fatal(1, "timing differs from motherboard PROMs");
		$finish;
	end
endmodule
