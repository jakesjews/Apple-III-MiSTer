`timescale 1ns / 1ps
// The three video sources and the green-phosphor monitor on whole frames.  The scan counters, the sister-byte
// RAM, the video generator and the monitor run together, so these checks cover
// what the unit benches cannot: where a fetched dot falls against the
// subcarrier, and the burst the monitor sees on each line.
//
// +FRAMES=<directory> also writes every captured frame as a PPM.
module video_source_tb;
	logic clk = 0;
	always #5 clk = ~clk;

	wire character_slot, frame_tick;
	wire [9:0] h_count;
	wire [8:0] v_count;
	wire [8:0] scan_line;
	wire       field;
	wire [6:0] h_state;
	wire [3:0] state_dot;
	apple3_timing timing (
		.clk_14m          (clk),
		.slow_mode        (1'b0),
		.interlace        (1'b0),
		.screen_enable    (1'b1),
		.peripheral_cycle (1'b0),
		.rtc_cycle        (1'b0),
		.peripheral_select(),
		.ram_cycle        (1'b0),
		.cpu_enable       (),
		.via_rising       (),
		.via_falling      (),
		.q3               (),
		.pixel_enable     (),
		.hblank           (),
		.vblank           (),
		.display_slot     (),
		.refresh_slot     (),
		.character_slot,
		.h_count,
		.v_count,
		.scan_line,
		.h_state,
		.state_dot,
		.frame_tick,
		.field
	);

	wire [15:0] video_q;
	wire [17:0] video_addr;
	apple3_ram #(
		.WORD_ADDRESS_BITS(17)
	) ram (
		.clk,
		.cpu_addr(18'd0),
		.cpu_lane(1'b0),
		.cpu_we  (1'b0),
		.cpu_din (8'd0),
		.cpu_q   (),
		.video_addr,
		.video_q
	);

	logic       native_mode = 1;
	logic [3:0] video_mode = 0;
	wire [7:0] video_r, video_g, video_b;
	wire [3:0] colour;
	wire [1:0] colour_phase;
	wire colour_burst, video_hblank, video_vblank, video_hsync, video_vsync;
	apple3_video video (
		.clk,
		.reset          (1'b0),
		.h_count,
		.v_count,
		.scan_line,
		.h_state,
		.state_dot,
		.frame_tick,
		.field,
		.screen_enable  (1'b1),
		.native_mode,
		.video_mode,
		.smooth_enable  (1'b0),
		.smooth_offset  (3'd0),
		.character_write(1'b0),
		.character_slot,
		.ram_addr       (video_addr),
		.ram_q          (video_q),
		.red            (video_r),
		.green          (video_g),
		.blue           (video_b),
		.colour,
		.colour_phase,
		.colour_burst,
		.hblank         (video_hblank),
		.vblank         (video_vblank),
		.hsync          (video_hsync),
		.vsync          (video_vsync)
	);

	logic [1:0] source = 0;
	logic       green_phosphor = 0;
	wire [7:0] red, green, blue;
	wire hblank, vblank;
	apple3_composite monitor (
		.clk,
		.source,
		.green_phosphor,
		.colour,
		.colour_phase,
		.colour_burst,
		.rgb_in   ({video_r, video_g, video_b}),
		.hblank_in(video_hblank),
		.vblank_in(video_vblank),
		.hsync_in (video_hsync),
		.vsync_in (video_vsync),
		.red,
		.green,
		.blue,
		.hblank,
		.vblank,
		.hsync    (),
		.vsync    ()
	);

	localparam integer       TEXT_PAGE = 'h78400;
	localparam integer       SISTER    = 'h400;
	localparam integer       PLANE     = 'h2000;
	localparam         [1:0] RGB       = 2'd0, NTSC = 2'd1, MONO = 2'd2;
	// The monitors a frame can be taken from: a source, and for the B/W jack
	// the green phosphor of a Monitor ///.
	localparam         [2:0] GREEN     = {1'b1, MONO};

	integer failures = 0;
	task automatic check(input logic ok, input string message);
		if (ok !== 1'b1) begin
			failures++;
			$display("FAIL: %s", message);
		end else $display("PASS: %s", message);
	endtask

	task automatic poke(input integer physical, input logic [7:0] value);
		logic [18:0] address;
		logic [17:0] word;
		address = physical;
		word    = {address[18:12], address[10] ^ address[11], address[9:0]};
		if (address[11]) ram.mem[word[16:0]][15:8] = value;
		else ram.mem[word[16:0]][7:0] = value;
	endtask
	function automatic integer graphics_address(input integer line, input integer column);
		graphics_address = (line % 8) * 1024 + ((line / 8) % 8) * 128 + (line / 64) * 40 + column;
	endfunction

	// The monitor's picture: 560 dots from the end of its own blanking.
	logic [23:0] frame[0:191][0:559];
	integer x = 0, y = 0;
	logic capturing = 0;
	always @(negedge clk) begin
		if (vblank) y <= 0;
		else if (hblank) begin
			if (x != 0) y <= y + 1;
			x <= 0;
		end else begin
			if (capturing && y < 192 && x < 560) frame[y][x] <= {red, green, blue};
			x <= x + 1;
		end
	end

	string        directory;
	integer       file;
	logic   [4:0] settled = '1;
	task automatic capture(input logic [2:0] monitor, input string name);
		{green_phosphor, source} = monitor;
		// After a mode change, a whole frame first, so that every line's
		// burst has been seen.
		if (settled !== {native_mode, video_mode}) @(posedge vblank);
		settled = {native_mode, video_mode};
		@(negedge vblank);
		capturing = 1;
		@(posedge vblank);
		capturing = 0;
		if ($value$plusargs("FRAMES=%s", directory)) begin
			file = $fopen({directory, "/", name, ".ppm"}, "wb");
			$fwrite(file, "P6\n560 192\n255\n");
			for (integer row = 0; row < 192; row++)
			for (integer column = 0; column < 560; column++)
			$fwrite(file, "%c%c%c", frame[row][column][23:16], frame[row][column][15:8], frame[row][column][7:0]);
			$fclose(file);
		end
	endtask

	// Dots of the frame that are neither black nor the given colour.
	function automatic integer off_colour(input logic [23:0] lit);
		off_colour = 0;
		for (integer row = 0; row < 192; row++)
		for (integer column = 0; column < 560; column++)
		if (frame[row][column] != 24'h000000 && frame[row][column] != lit) off_colour++;
	endfunction

	// Dots of the frame that are neither black nor white.
	function automatic integer tinted(input integer first_line, input integer last_line);
		tinted = 0;
		for (integer row = first_line; row <= last_line; row++)
		for (integer column = 0; column < 560; column++)
		if (frame[row][column] != 24'h000000 && frame[row][column] != 24'hffffff) tinted++;
	endfunction

	// The decoder's sixteen colours and the B/W ladder, as in composite_tb.
	logic [23:0] NTSC_COLOUR[16] = '{
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
	// Apple II hires bytes for even and odd columns, eight columns a band.
	// The ladder on a green phosphor, as in composite_tb.
	logic [23:0] GREEN_LEVEL[16] = '{
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
	logic [7:0] HIRES_EVEN[5] = '{8'h55, 8'h2a, 8'hd5, 8'haa, 8'h7f};
	logic [7:0] HIRES_ODD[5] = '{8'h2a, 8'h55, 8'haa, 8'hd5, 8'h7f};
	logic [23:0] ARTIFACT[5] = '{24'hf31cff, 24'h0be200, 24'h0b92ff, 24'hf36c00, 24'hffffff};
	string ARTIFACT_NAME[5] = '{"violet", "green", "blue", "orange", "white"};

	integer errors, band;
	logic [27:0] group;
	logic [ 3:0] bar_colour;

	initial begin
		for (integer word = 0; word < (1 << 17); word++) ram.mem[word] = 16'h0000;
		for (integer entry = 0; entry < 1024; entry++) video.character_ram[entry] = 8'h00;

		// Apple II hires: five bands of the classic fill bytes.
		for (integer line = 0; line < 192; line++)
		for (integer column = 0; column < 40; column++)
		poke(graphics_address(line, column), column[0] ? HIRES_ODD[column/8] : HIRES_EVEN[column/8]);
		native_mode = 0;
		video_mode  = 4'b1000;
		capture(NTSC, "hires-ntsc");
		for (band = 0; band < 5; band++)
		check(frame[100][band*112+56] == ARTIFACT[band], $sformatf(
			  "Apple II hires %s is %06x on the NTSC output", ARTIFACT_NAME[band], frame[100][band*112+56]));
		capture(RGB, "hires-rgb");
		check(tinted(0, 191) == 0, "Apple II hires is black and white on the RGB output");
		// Bit 7 moves the blue band's dots one master dot right of violet's.
		// Column 18 follows an $AA, whose bit 6 is clear.
		check(
			frame[100][0] == 24'hffffff && frame[100][2] == 24'h000000 &&
			  frame[100][252] == 24'h000000 && frame[100][253] == 24'hffffff && frame[100][254] == 24'hffffff &&
			  frame[100][255] == 24'h000000,
			"bit 7 delays hires dots by one master dot");
		capture(MONO, "hires-mono");
		check(tinted(0, 191) == 0, "Apple II hires is black and white on the B/W output");
		capture(GREEN, "hires-green");
		check(frame[100][0] == 24'h11dd00 && frame[100][2] == 24'h000000 && off_colour(24'h11dd00) == 0,
			  "Apple II hires is green on black on a green phosphor");

		// Apple II mixed mode keeps the burst through its text lines, so
		// they fringe as on an Apple II; TEXT alone kills it.
		for (integer entry = 0; entry < 1024; entry++) video.character_ram[entry] = 8'h55;
		for (integer offset = 0; offset < 'h800; offset++) poke(TEXT_PAGE + offset, 8'hc1);
		video_mode = 4'b1010;
		capture(NTSC, "mixed-ntsc");
		check(tinted(160, 191) > 1000, "mixed-mode text is fringed on the NTSC output");
		video_mode = 4'b0001;
		capture(NTSC, "text-ntsc");
		check(tinted(0, 191) == 0, "Apple II text is sharp black and white on the NTSC output");

		// Native 80-column text: no burst, so single 14M dots stay sharp.
		native_mode = 1;
		video_mode  = 4'b0010;
		capture(NTSC, "text80-ntsc");
		errors = 0;
		for (integer column = 0; column < 560; column++)
		if (frame[100][column] != (((column % 7) % 2 == 0) ? 24'hffffff : 24'h000000)) errors++;
		check(tinted(0, 191) == 0 && errors == 0, "80-column text is sharp on the NTSC output");
		capture(MONO, "text80-mono");
		check(frame[100][0] == 24'hffffff && tinted(0, 191) == 0, "80-column text is white on the B/W output");
		capture(RGB, "text80-rgb");
		errors = 0;
		for (integer column = 0; column < 560; column++)
		if (frame[100][column] != (((column % 7) % 2 == 0) ? 24'hffffff : 24'h000000)) errors++;
		check(tinted(0, 191) == 0 && errors == 0, "80-column text is white on black on the RGB output");
		// The phosphor is the monochrome monitor's: it shows the same dots in
		// green, and the other two sources ignore the option.
		capture(GREEN, "text80-green");
		errors = 0;
		for (integer column = 0; column < 560; column++)
		if (frame[100][column] != (((column % 7) % 2 == 0) ? 24'h11dd00 : 24'h000000)) errors++;
		check(off_colour(24'h11dd00) == 0 && errors == 0, "80-column text is sharp green on a green phosphor");
		capture({1'b1, RGB}, "text80-rgb-phosphor");
		check(frame[100][0] == 24'hffffff && tinted(0, 191) == 0, "the phosphor option leaves the RGB output white");
		capture({1'b1, NTSC}, "text80-ntsc-phosphor");
		check(frame[100][0] == 24'hffffff && tinted(0, 191) == 0, "the phosphor option leaves the NTSC output white");

		// 140 x 192: sixteen bars, 35 dots each rounded to whole pixels.
		for (integer line = 0; line < 192; line++)
		for (integer column = 0; column < 40; column += 2) begin
			bar_colour = (column / 2 * 16) / 20;
			group      = {7{bar_colour}};
			poke(graphics_address(line, column), {1'b0, group[6:0]});
			poke(graphics_address(line, column) + PLANE, {1'b0, group[13:7]});
			poke(graphics_address(line, column + 1), {1'b0, group[20:14]});
			poke(graphics_address(line, column + 1) + PLANE, {1'b0, group[27:21]});
		end
		video_mode = 4'b1011;
		capture(NTSC, "bars-ntsc");
		errors = 0;
		for (integer bar = 0; bar < 20; bar++) if (frame[100][bar*28+14] != NTSC_COLOUR[(bar*16)/20]) errors++;
		check(errors == 0, "140-colour bars decode to the sixteen NTSC colours");
		capture(MONO, "bars-mono");
		errors = 0;
		for (integer bar = 0; bar < 20; bar++) if (frame[100][bar*28+14] != {3{GREY[(bar*16)/20]}}) errors++;
		check(errors == 0, "140-colour bars are the RP4 grey scale on the B/W output");
		capture(GREEN, "bars-green");
		errors = 0;
		for (integer bar = 0; bar < 20; bar++) if (frame[100][bar*28+14] != GREEN_LEVEL[(bar*16)/20]) errors++;
		check(errors == 0, "140-colour bars keep their sixteen levels on a green phosphor");
		capture(RGB, "bars-rgb");
		check(frame[100][28*5+14] == 24'h007722 && frame[100][28*19+14] == 24'hffffff,
			  "140-colour bars keep the RGB palette");

		// Colour text carries a burst; black-and-white 40-column text does not.
		for (integer offset = 0; offset < 'h400; offset++) poke(TEXT_PAGE + SISTER + offset, 8'h2d);
		video_mode = 4'b0001;
		capture(NTSC, "colourtext-ntsc");
		check(tinted(0, 191) > 50000, "colour text is decoded in colour");
		video_mode = 4'b0000;
		capture(NTSC, "text40-ntsc");
		check(tinted(0, 191) == 0, "40-column text is sharp black and white on the NTSC output");

		$display("video sources: %0d failed checks", failures);
		if (failures != 0) $fatal(1, "video source checks failed");
		$finish;
	end
endmodule
