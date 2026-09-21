`timescale 1ns / 1ps

// The three video sources and the monitors on the composite ones, driven
// with dot streams as apple3_video makes them.
module composite_tb;
	logic        clk = 0;
	logic [ 1:0] source = 0;
	logic [ 1:0] monitor = 0;
	logic [ 3:0] colour = 0;
	logic [ 1:0] colour_phase = 0;
	logic        colour_burst = 0;
	logic [23:0] rgb_in = 0;
	logic hblank_in = 0, vblank_in = 0, hsync_in = 0, vsync_in = 0;
	wire [7:0] red, green, blue;
	wire hblank, vblank, hsync, vsync;

	apple3_composite dut (.*);

	always #5 clk = ~clk;

	// One dot: the subcarrier slot advances with every 14M clock.
	task automatic dot(input [3:0] lines);
		begin
			colour = lines;
			@(posedge clk);
			#1 colour_phase = colour_phase + 2'd1;
		end
	endtask

	// The monitor samples the burst as the sync pulse ends.
	task automatic line_start(input burst);
		begin
			colour_burst = burst;
			hsync_in     = 1;
			dot(0);
			hsync_in = 0;
			dot(0);
		end
	endtask

	// Repeats a four-dot group, slot 0 first, until the decoder has settled.
	task automatic pattern(input [3:0] slot0, input [3:0] slot1, input [3:0] slot2, input [3:0] slot3);
		begin
			while (colour_phase != 0) dot(0);
			repeat (3) begin
				dot(slot0);
				dot(slot1);
				dot(slot2);
				dot(slot3);
			end
		end
	endtask

	task automatic expect_rgb(input [23:0] want, input string what);
		if ({red, green, blue} !== want) $fatal(1, "%s = %06x, expected %06x", what, {red, green, blue}, want);
	endtask

	// The NTSC pin's sixteen colours through the decoder, against the same
	// arithmetic done by hand from the RP3 weights.
	logic [23:0] NTSC[16] = '{
		24'h000000,
		24'h861b3f,
		24'h3f27bd,
		24'hc643fd,
		24'h00633f,
		24'h7f7f7f,
		24'h388bfd,
		24'hbfa7ff,
		24'h3f5700,
		24'hc67301,
		24'h7f7f7f,
		24'hff9bbf,
		24'h38bb01,
		24'hbfd741,
		24'h78e3bf,
		24'hffffff
	};
	// RP4's ladder.  RGB8 weighs ten times RGB1, so the scale steps up at 8.
	logic [7:0] GREY[16] = '{
		8'd0,
		8'd15,
		8'd29,
		8'd44,
		8'd62,
		8'd77,
		8'd91,
		8'd106,
		8'd149,
		8'd164,
		8'd178,
		8'd193,
		8'd211,
		8'd226,
		8'd240,
		8'd255
	};

	// A Monitor /// shows the same ladder in P31 green: each grey level times
	// 11dd00, worked by hand.
	logic [23:0] GREEN[16] = '{
		24'h000000,
		24'h010d00,
		24'h021900,
		24'h032600,
		24'h043600,
		24'h054300,
		24'h064f00,
		24'h075c00,
		24'h0a8100,
		24'h0b8e00,
		24'h0c9a00,
		24'h0da700,
		24'h0eb700,
		24'h0fc400,
		24'h10d000,
		24'h11dd00
	};

	// And in amber: each grey level times ffb000.
	logic [23:0] AMBER[16] = '{
		24'h000000,
		24'h0f0a00,
		24'h1d1400,
		24'h2c1e00,
		24'h3e2b00,
		24'h4d3500,
		24'h5b3f00,
		24'h6a4900,
		24'h956700,
		24'ha47100,
		24'hb27b00,
		24'hc18500,
		24'hd39200,
		24'he29c00,
		24'hf0a600,
		24'hffb000
	};
	// Colour 1 on the NTSC pin is 113, 51, -11 and 51 in slots 0 to 3.  A
	// monochrome tube shows 5/4 of that, clipped at black: 141, 63, 0, 63.
	logic [23:0] GREEN_COLOUR_1[4] = '{24'h097a00, 24'h043700, 24'h000000, 24'h043700};
	logic [23:0] AMBER_COLOUR_1[4] = '{24'h8d6100, 24'h3f2b00, 24'h000000, 24'h3f2b00};

	localparam logic [1:0] RGB_MONITOR = 2'd0, GREEN_MONITOR = 2'd1, AMBER_MONITOR = 2'd2, COLOUR_TV = 2'd3;

	// A single lit dot among dark ones, as a monitor with full bandwidth shows
	// it: nothing before the fourth dot, `want` on it and nothing after.
	task automatic expect_single_dot(input [3:0] lines, input [23:0] want, input string what);
		begin
			repeat (4) dot(0);
			dot(lines);
			repeat (2) dot(0);
			expect_rgb(24'h000000, {what, " arrived early"});
			dot(0);
			expect_rgb(want, what);
			dot(0);
			expect_rgb(24'h000000, {what, " lasted two dots"});
		end
	endtask

	// The same dot through a television's trap: a quarter of it on each of
	// four dots, beginning one dot sooner because the mean looks ahead.
	task automatic expect_trapped_dot(input [23:0] want, input string what);
		begin
			repeat (4) dot(0);
			dot(15);
			dot(0);
			expect_rgb(24'h000000, {what, " arrived early"});
			repeat (4) begin
				dot(0);
				expect_rgb(want, what);
			end
			dot(0);
			expect_rgb(24'h000000, {what, " lasted five dots"});
		end
	endtask

	// Dots of colour `to` after a long run of `from`, until the picture is
	// the steady colour `want`.
	task automatic dots_to_settle(input [3:0] from, input [3:0] to, input [23:0] want, output integer dots);
		begin
			repeat (16) dot(from);
			dots = 0;
			while ({red, green, blue} !== want && dots < 32) begin
				dot(to);
				dots++;
			end
		end
	endtask

	integer clean_dots, tv_dots;

	initial begin
		// Native colours on the clean monitor: a steady colour number is its
		// own hue.
		source  = 2'd1;
		monitor = RGB_MONITOR;
		line_start(1);
		for (int c = 0; c < 16; c++) begin
			pattern(c[3:0], c[3:0], c[3:0], c[3:0]);
			expect_rgb(NTSC[c], $sformatf("NTSC colour %0d", c));
		end

		// Apple II artifact colour: white dots two wide.  Even columns fill
		// slots 0-1, odd columns slots 2-3, and bit 7 moves either one later.
		pattern(15, 15, 0, 0);
		expect_rgb(24'hf31cff, "violet");
		pattern(0, 0, 15, 15);
		expect_rgb(24'h0be200, "green");
		pattern(0, 15, 15, 0);
		expect_rgb(24'h0b92ff, "blue");
		pattern(15, 0, 0, 15);
		expect_rgb(24'hf36c00, "orange");
		pattern(15, 15, 15, 15);
		expect_rgb(24'hffffff, "white");

		// No burst: the colour killer leaves single dots at full bandwidth.
		line_start(0);
		pattern(15, 0, 15, 0);
		dot(15);
		expect_rgb(24'h000000, "killed dark dot");
		dot(0);
		expect_rgb(24'hffffff, "killed lit dot");
		expect_single_dot(15, 24'hffffff, "killed single dot");
		// The same dots with a burst are a grey blur.
		line_start(1);
		pattern(15, 0, 15, 0);
		expect_rgb(24'h7f7f7f, "decoded single dots");

		// A colour television has the clean monitor's tint and saturation, so
		// steady colours and artifact colours are the same ones.
		monitor = COLOUR_TV;
		for (int c = 0; c < 16; c++) begin
			pattern(c[3:0], c[3:0], c[3:0], c[3:0]);
			expect_rgb(NTSC[c], $sformatf("television colour %0d", c));
		end
		pattern(15, 15, 0, 0);
		pattern(15, 15, 0, 0);
		expect_rgb(24'hf31cff, "television violet");
		pattern(15, 0, 0, 15);
		pattern(15, 0, 0, 15);
		expect_rgb(24'hf36c00, "television orange");
		// Its chroma filter spans two cycles, so a change of hue takes four
		// dots longer than on the clean monitor.  Colours 1 and 2 differ in
		// every slot, so the last old dot in either window shows.
		dots_to_settle(1, 2, NTSC[2], tv_dots);
		monitor = RGB_MONITOR;
		dots_to_settle(1, 2, NTSC[2], clean_dots);
		if (clean_dots != 6 || tv_dots != 10)
			$fatal(1, "hue change took %0d dots clean and %0d on the television", clean_dots, tv_dots);
		// Its trap stays in when the colour killer acts: 80-column dots are a
		// grey blur, and one dot is a quarter as bright over four.
		monitor = COLOUR_TV;
		line_start(0);
		pattern(15, 0, 15, 0);
		expect_rgb(24'h7f7f7f, "television single dots");
		expect_trapped_dot(24'h3f3f3f, "television single dot");
		pattern(15, 15, 15, 15);
		expect_rgb(24'hffffff, "television white");

		// A monochrome monitor on the NTSC pin shows the signal's level at
		// full bandwidth, burst or no burst: text is sharp, and a colour is
		// its subcarrier as dots.  dot() leaves colour_phase at the slot of
		// the dot now on the screen.
		for (int tube = 0; tube < 2; tube++) begin
			monitor = tube[0] ? AMBER_MONITOR : GREEN_MONITOR;
			for (int burst = 0; burst < 2; burst++) begin
				line_start(burst[0]);
				expect_single_dot(15, tube[0] ? 24'hffb000 : 24'h11dd00, "single dot on a monochrome tube");
				repeat (8) dot(1);
				repeat (4) begin
					dot(1);
					expect_rgb(tube[0] ? AMBER_COLOUR_1[colour_phase] : GREEN_COLOUR_1[colour_phase], $sformatf(
							   "colour 1 in slot %0d on a monochrome tube", colour_phase));
				end
				repeat (8) dot(5);
				expect_rgb(tube[0] ? 24'h7f5800 : 24'h086e00, "grey on a monochrome tube");
			end
		end

		// The B/W jack: grey by colour number, no chroma and no filter.
		source  = 2'd2;
		monitor = RGB_MONITOR;
		for (int c = 0; c < 16; c++) begin
			expect_single_dot(c[3:0], {3{GREY[c]}}, $sformatf("grey %0d", c));
			if (c > 0 && GREY[c] <= GREY[c-1]) $fatal(1, "grey scale is not monotonic at %0d", c);
		end

		// The same jack on a green or an amber tube: every grey level keeps
		// its place, and a single dot is as sharp and as late as it is in white.
		monitor = GREEN_MONITOR;
		for (int c = 0; c < 16; c++) begin
			expect_single_dot(c[3:0], GREEN[c], $sformatf("green %0d", c));
			if (c > 0 && GREEN[c][15:8] <= GREEN[c-1][15:8]) $fatal(1, "green scale is not monotonic at %0d", c);
		end
		monitor = AMBER_MONITOR;
		for (int c = 0; c < 16; c++) begin
			expect_single_dot(c[3:0], AMBER[c], $sformatf("amber %0d", c));
			if (c > 0 && AMBER[c][23:16] <= AMBER[c-1][23:16]) $fatal(1, "amber scale is not monotonic at %0d", c);
		end

		// A television on it has no chroma to decode, and its trap softens the
		// greys the same way: steady levels are exact, single dots are not.
		monitor = COLOUR_TV;
		for (int c = 0; c < 16; c++) begin
			repeat (8) dot(c[3:0]);
			expect_rgb({3{GREY[c]}}, $sformatf("television grey %0d", c));
		end
		expect_trapped_dot(24'h404040, "television single dot on the B/W jack");
		repeat (3) begin
			dot(15);
			dot(0);
		end
		expect_rgb(24'h808080, "television 80-column dots on the B/W jack");

		// RGB passes through, whatever the monitor option says, and every
		// source is four dots late with its blanking and sync.
		source    = 2'd0;
		rgb_in    = 24'h123456;
		hblank_in = 1;
		vsync_in  = 1;
		dot(0);
		rgb_in    = 24'h000000;
		hblank_in = 0;
		vsync_in  = 0;
		repeat (2) dot(0);
		if (hblank || vsync) $fatal(1, "blanking arrived early");
		dot(0);
		expect_rgb(24'h123456, "RGB after four dots");
		if (!hblank || !vsync || vblank || hsync) $fatal(1, "timing after four dots");
		dot(0);
		expect_rgb(24'h000000, "RGB after five dots");

		$display("PASS apple3_composite");
		$finish;
	end
endmodule
