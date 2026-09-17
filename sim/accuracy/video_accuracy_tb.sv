`timescale 1ns / 1ps
// Independent boundary checks from SRM ch.2/ch.6 and the 342-0032/0055 PROMs.
module video_accuracy_tb;
	logic clk = 0, reset = 1;
	always #5 clk = ~clk;
	logic [9:0] h_count = 0;
	logic [8:0] v_count = 0;
	logic [6:0] h_state = 0;
	logic [3:0] state_dot = 0;
	logic frame_tick = 0, screen_enable = 1, native_mode = 1;
	logic [3:0] video_mode = 0;
	logic smooth_enable = 0, character_write = 0;
	logic [ 2:0] smooth_offset = 0;
	wire  [17:0] ram_addr;
	logic [15:0] ram_q = 0;
	wire [7:0] red, green, blue;
	wire hblank, vblank, hsync, vsync;
	apple3_video dut (.*);
	integer failures = 0, mismatches = 0;
	logic [27:0] pixels;
	logic [18:0] before_scroll;
	integer physical, expected_word, address_checks = 0, address_errors = 0;
	task automatic check(input logic ok, input string message);
		if (ok !== 1'b1) begin
			failures++;
			$display("FAIL: %s", message);
		end else $display("PASS: %s", message);
	endtask
	initial begin
		repeat (3) @(negedge clk);
		reset                   = 0;
		// Seven distinct colours in 28 serial bits, each displayed for four dots.
		// This checks the *entire* two-byte-pair group, including the 14-dot join.
		pixels                  = 28'h7654321;
		dut.line_buffer_low[0]  = {1'b0, pixels[6:0]};
		dut.line_buffer_high[0] = {1'b0, pixels[13:7]};
		dut.line_buffer_low[1]  = {1'b0, pixels[20:14]};
		dut.line_buffer_high[1] = {1'b0, pixels[27:21]};
		video_mode              = 4'hb;
		for (integer dot = 0; dot < 28; dot++) begin
			h_count   = dot;
			h_state   = dot / 14;
			state_dot = dot % 14;
			#1;
			if (dut.colour_index !== pixels[(dot/4)*4+:4]) begin
				mismatches++;
				$display("  140-mode dot %0d: expected colour %x, got %x", dot, pixels[(dot/4)*4+:4], dut.colour_index);
			end
		end
		check(mismatches == 0, "140-mode seven equal-width pixels across the 14-dot boundary");

		// VA/VB/VC offset must also change the high-resolution RAM fetch address.
		for (integer mode = 8; mode < 12; mode++) begin
			h_count       = 600;
			v_count       = 0;
			video_mode    = mode;
			smooth_enable = 0;
			#1;
			before_scroll = {dut.request_lane, ram_addr};
			smooth_enable = 1;
			smooth_offset = 1;
			#1;
			check({dut.request_lane, ram_addr} != before_scroll, $sformatf(
				  "graphics mode %x scroll changes fetched row", mode));
		end

		// Exact physical address and byte lane across all graphics rows, offsets,
		// both pages and both planes, including modulo-eight scroll wrap.
		smooth_enable = 1;
		for (integer mode = 8; mode < 16; mode++)
		for (integer y = 0; y < 192; y++)
		for (integer offset = 0; offset < 8; offset++)
		for (integer plane = 0; plane < 2; plane++)
		for (integer boundary = 0; boundary < 2; boundary++) begin
			video_mode    = mode;
			v_count       = (y == 0) ? 261 : y - 1;
			smooth_offset = offset;
			h_count       = 600 + 40 * plane + 39 * boundary;
			#1;
			physical=((y/8)%8)*128+(y/64)*40+((y+offset)%8)*1024+
				((mode&4)?((mode==12)?8192:16384):0)+8192*plane+39*boundary;
			expected_word=(physical>>12)*2048+(((physical>>10)^(physical>>11))&1)*1024+(physical&1023);
			address_checks++;
			if (ram_addr !== expected_word[17:0] || dut.request_lane !== ((physical >> 11) & 1)) begin
				if (address_errors < 5)
					$display(
						"graphics address mismatch mode=%x y=%0d scroll=%0d physical=%x word=%x lane=%b",
						mode,
						y,
						offset,
						physical,
						ram_addr,
						dut.request_lane
					);
				address_errors++;
			end
		end
		check(address_errors == 0, $sformatf("%0d exact graphics fetch addresses and byte lanes", address_checks));

		// Apple ][ mode: C051 selects TEXT regardless of the HIRES latch (C057).
		// Page 1, 'A' with first dot lit. SRM ch.10; mode PROM TEXT/-AIISW inputs.
		smooth_enable                    = 0;
		native_mode                      = 0;
		video_mode                       = 4'h9;
		h_state                          = 0;
		state_dot                        = 0;
		h_count                          = 0;
		v_count                          = 0;
		dut.line_buffer_low[0]           = 8'hc1;
		dut.line_buffer_high[0]          = 8'h00;
		dut.character_ram[{7'h41, 3'd0}] = 8'h01;
		#1;
		check({red, green, blue} == 24'hffffff, "Apple II TEXT overrides HIRES in emulation mode");

		// TEXT also selects text-page fetches when HIRES remains set.
		h_count = 600;
		v_count = 0;
		#1;
		check(ram_addr == 18'h3c400 && !dut.request_lane, "Apple II TEXT fetch overrides HIRES");
		h_count = 0;
		repeat (3) @(negedge clk);
		dut.line_buffer_low[0]  = 8'h21;
		dut.line_buffer_high[0] = 8'h43;
		for (integer page = 0; page < 2; page++) begin
			video_mode = page * 4;
			v_count    = 0;
			#1;
			check(dut.colour_index == (page ? 3 : 1), "Apple II lores upper nibble-row and page select");
			v_count = 4;
			#1;
			check(dut.colour_index == (page ? 4 : 2), "Apple II lores lower nibble-row and page select");
		end
		// MIXED selects text precisely at line 160, with the fetch on line 159.
		for (integer hires = 0; hires < 2; hires++) begin
			video_mode = 2 + hires * 8;
			h_count    = 600;
			v_count    = 158;
			#1;
			check(ram_addr == (hires ? 18'h009d0 : 18'h3c5d0), "mixed line 159 still fetches graphics");
			v_count = 159;
			#1;
			check(ram_addr == 18'h3c650 && !dut.request_lane, "mixed line 160 fetches text");
			h_count = 0;
			repeat (3) @(negedge clk);
			dut.line_buffer_low[0]           = 8'hc1;
			dut.character_ram[{7'h41, 3'd0}] = 8'h01;
			v_count                          = 160;
			#1;
			check({red, green, blue} == 24'hffffff, "mixed bottom region renders 40-column text");
		end

		$display("video accuracy: %0d failed checks", failures);
		if (failures) $fatal(1, "video accuracy discrepancies");
		$finish;
	end
endmodule
