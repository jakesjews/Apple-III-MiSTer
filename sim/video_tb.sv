`timescale 1ns / 1ps

// Pixel decoding and fetch addressing checked without a clock: the pipeline
// registers are seeded directly and hold their values between samples.
module video_tb;
	logic clk = 0, reset = 0;
	logic [9:0] h_count = 0;
	logic [8:0] v_count = 0;
	logic [6:0] h_state = 0;
	logic [3:0] state_dot = 0;
	logic frame_tick = 0, screen_enable = 1, native_mode = 1;
	logic [3:0] video_mode = 0;
	logic smooth_enable = 0, character_write = 0, character_slot = 0;
	logic [ 2:0] smooth_offset = 0;
	wire  [17:0] ram_addr;
	logic [15:0] ram_q = 0;
	wire [7:0] red, green, blue;
	wire hblank, vblank, hsync, vsync;

	apple3_video dut (.*);

	// A column read in state S is displayed during state S + 2.
	task automatic sample (input [6:0] column, input [3:0] dot);
		begin
			h_state   = column + 7'd2;
			state_dot = dot;
			h_count   = h_state * 14 + dot;
			#1;
		end
	endtask

	task automatic scan(input [8:0] line, input [6:0] state, input [3:0] dot);
		begin
			v_count   = line;
			h_state   = state;
			state_dot = dot;
			h_count   = state * 14 + dot;
			#1;
		end
	endtask

	initial begin
		dut.flash_count                  = 0;
		// Character A row 0 has its low bit set. Normal characters use bit 7.
		dut.pixel_low                    = 8'hc1;
		dut.pixel_high                   = 8'h21;
		dut.character_ram[{7'h41, 3'd0}] = 8'h01;
		video_mode                       = 4'b0000;
		sample (0, 0);
		if ({red, green, blue} !== 24'hffffff) $fatal(1, "40-col foreground=%06x", {red, green, blue});
		sample (0, 2);
		if ({red, green, blue} !== 24'h000000) $fatal(1, "40-col background=%06x", {red, green, blue});

		video_mode = 4'b0001;
		sample (0, 0);
		if ({red, green, blue} !== 24'h000099) $fatal(1, "colour text fg=%06x", {red, green, blue});
		sample (0, 2);
		if ({red, green, blue} !== 24'h550055) $fatal(1, "colour text bg=%06x", {red, green, blue});

		// 560-pixel monochrome concatenates seven bits from each plane.
		video_mode     = 4'b1010;
		dut.pixel_low  = 8'h01;
		dut.pixel_high = 8'h02;
		sample (0, 0);
		if ({red, green, blue} !== 24'hffffff) $fatal(1, "SHGR plane 0");
		sample (0, 8);
		if ({red, green, blue} !== 24'hffffff) $fatal(1, "SHGR plane 1");

		// 140-mode ignores each byte's high bit and packs seven 4-bit colours.
		// The even column's pair is on screen; the odd column's is next.
		video_mode     = 4'b1011;
		dut.pixel_low  = 8'h21;
		dut.pixel_high = 8'h43;
		dut.next_low   = 8'h65;
		dut.next_high  = 8'h07;
		sample (0, 0);
		if ({red, green, blue} !== 24'hdd0033) $fatal(1, "140 colour 0=%06x", {red, green, blue});
		sample (0, 4);
		// p1[6:4]=$2 and p2[0]=1 form palette index $a.
		if ({red, green, blue} !== 24'haaaaaa) $fatal(1, "140 colour 1=%06x", {red, green, blue});

		// Fetch addressing: text line 0, column 0 is the $0400/$0800 sister
		// word, read in the column's own state.
		video_mode = 0;
		scan(0, 0, 0);
		if (ram_addr !== 18'h3c400 || dut.primary_lane !== 1'b0)
			$fatal(1, "text primary address=%05x lane=%b", ram_addr, dut.primary_lane);
		scan(0, 0, 5);
		if (ram_addr !== 18'h3c400 || dut.secondary_lane !== 1'b1)
			$fatal(1, "text sister address=%05x lane=%b", ram_addr, dut.secondary_lane);
		// Graphics line 1 is row 1 of the first cell: $0400 above the base.
		video_mode = 4'b1000;
		scan(1, 0, 0);
		if (ram_addr !== 18'h00400) $fatal(1, "graphics primary address=%05x", ram_addr);
		scan(1, 0, 5);
		if (ram_addr !== 18'h01400) $fatal(1, "graphics secondary address=%05x", ram_addr);

		// The visible window trails the scan counter by two states.
		scan(0, 2, 0);
		if (hblank) $fatal(1, "first visible dot is blanked");
		scan(0, 1, 13);
		if (!hblank) $fatal(1, "dot before the first column is visible");
		scan(0, 41, 13);
		if (hblank) $fatal(1, "last visible dot is blanked");
		scan(0, 42, 0);
		if (!hblank) $fatal(1, "dot after the last column is visible");

		screen_enable = 0;
		sample (0, 0);
		if ({red, green, blue} !== 24'h000000) $fatal(1, "screen disable did not blank");

		$display("PASS apple3_video");
		$finish;
	end
endmodule
