`timescale 1ns / 1ps
// Check both PHASEN and CS6522 against the original timing PROM, including
// a delayed FSPACE value different from the current one and slow C07x.
module timing_control_prom_tb;
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
	logic [7:0] scan_prom[0:2047], timing_prom[0:1023];
	string scan_path, timing_path;
	integer vertical, scan_address, address, reserved, checks = 0;
	initial begin
		if (!$value$plusargs("SCAN=%s", scan_path) || !$value$plusargs("TIMING=%s", timing_path))
			$fatal(1, "supply scan and timing PROMs");
		$readmemh(scan_path, scan_prom);
		$readmemh(timing_path, timing_prom);
		for (integer history = 0; history < 2; history++) begin
			for (integer half_slot = 0; half_slot < 2; half_slot++) begin
				for (integer config_bits = 0; config_bits < 32; config_bits++) begin
					if (config_bits[4] && !config_bits[3]) continue;
					@(negedge clk_14m);
					while (h_state != 10 || state_dot != 0) @(negedge clk_14m);
					peripheral_cycle = 1'(history);
					rtc_cycle        = 0;
					while (state_dot != 7) @(negedge clk_14m);
					{rtc_cycle, peripheral_cycle, slow_mode, screen_enable, ram_cycle} = 5'(config_bits);
					if (half_slot == 0) begin
						while (state_dot != 6) @(negedge clk_14m);
					end else begin
						while (state_dot != 13) @(negedge clk_14m);
					end
					#1;
					vertical = (v_count < 256) ? v_count + 256 : v_count - 6;
					scan_address = (((vertical >> 5) & 1) & ((vertical >> 8) & 1)) |
						((h_state >> 2) << 1) | ((vertical & 7) << 5) |
						(((vertical >> 3) & 1) << 8) | (((vertical >> 4) & 1) << 9) | ((v_count >= 192) << 10);
					reserved = (screen_enable && v_count < 192 && h_state < 40) || scan_prom[scan_address][4];
					address = half_slot | (!rtc_cycle << 1) | (ram_cycle << 2) | (reserved << 3) |
						(!history << 4) | (!peripheral_cycle << 6) | 'h80 | (slow_mode << 9);
					if (cpu_enable !== timing_prom[address][1] || peripheral_select !== timing_prom[address][0])
						$fatal(
							1,
							"PROM[%03x]=%02x RTL PHASEN=%b CS6522=%b",
							address,
							timing_prom[address],
							cpu_enable,
							peripheral_select
						);
					checks++;
				end
			end
		end
		$display("PASS delayed PHASEN/CS6522 against original PROM (%0d combinations)", checks);
		$finish;
	end
endmodule
