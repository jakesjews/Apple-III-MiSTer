`timescale 1ns / 1ps

// The three video sources and the green-phosphor monitor, driven with dot
// streams as apple3_video makes them.
module composite_tb;
	logic        clk = 0;
	logic [ 1:0] source = 0;
	logic        green_phosphor = 0;
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

	initial begin
		// Native colours: a steady colour number is its own hue.  The
		// phosphor option is the monochrome monitor's and leaves them alone.
		source         = 2'd1;
		green_phosphor = 1;
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
		// The same dots with a burst are a grey blur.
		line_start(1);
		pattern(15, 0, 15, 0);
		expect_rgb(24'h7f7f7f, "decoded single dots");

		// The B/W jack: grey by colour number, no chroma and no filter.
		source         = 2'd2;
		green_phosphor = 0;
		for (int c = 0; c < 16; c++) begin
			dot(c[3:0]);
			repeat (3) dot(0);
			expect_rgb({3{GREY[c]}}, $sformatf("grey %0d", c));
			if (c > 0 && GREY[c] <= GREY[c-1]) $fatal(1, "grey scale is not monotonic at %0d", c);
		end

		// The same jack on a green phosphor: every grey level keeps its place,
		// and a single dot is as sharp and as late as it is in white.
		green_phosphor = 1;
		for (int c = 0; c < 16; c++) begin
			dot(c[3:0]);
			repeat (2) dot(0);
			expect_rgb(24'h000000, $sformatf("green %0d arrived early", c));
			dot(0);
			expect_rgb(GREEN[c], $sformatf("green %0d", c));
			if (c > 0 && GREEN[c][15:8] <= GREEN[c-1][15:8]) $fatal(1, "green scale is not monotonic at %0d", c);
			dot(0);
			expect_rgb(24'h000000, $sformatf("green %0d lasted two dots", c));
		end

		// RGB passes through, whatever the phosphor option says, and every
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
