`timescale 1ns / 1ps
// Apple /// Plus text interlace: the field flip-flop, the 263-line field and
// its half-line vertical sync, and FORCPAGE's choice of display page in each
// field.  Sources: the 342-0145-A and 342-0032 PROM dumps, schematic sheet 10,
// ON THREE's interlace kit instructions.  docs/INTERLACE.md has the reasoning.
module interlace_tb;
	logic clk = 0;
	always #5 clk = ~clk;

	logic interlace = 0;
	wire cpu_enable, via_rising, via_falling, q3, pixel_enable, scan_hblank, scan_vblank;
	wire display_slot, refresh_slot, character_slot, frame_tick, field;
	wire [9:0] h_count;
	wire [8:0] v_count;
	wire [8:0] scan_line;
	wire [6:0] h_state;
	wire [3:0] state_dot;
	apple3_timing timing (
		.clk_14m          (clk),
		.slow_mode        (1'b0),
		.screen_enable    (1'b1),
		.interlace,
		.euro             (1'b0),
		.peripheral_cycle (1'b0),
		.rtc_cycle        (1'b0),
		.peripheral_select(),
		.ram_cycle        (1'b0),
		.cpu_enable,
		.via_rising,
		.via_falling,
		.q3,
		.pixel_enable,
		.hblank           (scan_hblank),
		.vblank           (scan_vblank),
		.display_slot,
		.refresh_slot,
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
	wire [7:0] red, green, blue;
	wire hblank, vblank, hsync, vsync;
	apple3_video video (
		.clk,
		.reset          (1'b0),
		.h_count,
		.v_count,
		.scan_line,
		.field,
		.euro           (1'b0),
		.h_state,
		.state_dot,
		.frame_tick,
		.screen_enable  (1'b1),
		.native_mode,
		.video_mode,
		.smooth_enable  (1'b0),
		.smooth_offset  (3'd0),
		.character_write(1'b0),
		.character_slot,
		.ram_addr       (video_addr),
		.ram_q          (video_q),
		.red,
		.green,
		.blue,
		.colour         (),
		.colour_phase   (),
		.colour_burst   (),
		.hblank,
		.vblank,
		.hsync,
		.vsync
	);

	integer failures = 0;
	task automatic check(input logic ok, input string message);
		if (ok !== 1'b1) begin
			failures++;
			$display("FAIL: %s", message);
		end else $display("PASS: %s", message);
	endtask

	function automatic [17:0] word_of(input logic [18:0] physical);
		word_of = {physical[18:12], physical[10] ^ physical[11], physical[9:0]};
	endfunction
	task automatic poke(input integer physical, input logic [7:0] value);
		logic [18:0] address;
		logic [17:0] word;
		address = physical;
		word    = word_of(address);
		if (address[11]) ram.mem[word[16:0]][15:8] = value;
		else ram.mem[word[16:0]][7:0] = value;
	endtask

	// One field: its clocks, the lines its counter took, where vertical sync
	// began, and how much of the picture was lit.
	integer clocks, line_count, lit_dots, sync_line, sync_dot;
	integer since_sync, sync_spacing;
	logic [8:0] lines[0:299];
	logic showing, vsync_q = 0;
	logic counting = 0;

	always @(negedge clk) begin
		if (counting) since_sync++;
		vsync_q <= vsync;
		if (vsync && !vsync_q) begin
			sync_line    = scan_line;
			sync_dot     = h_count;
			sync_spacing = since_sync;
			since_sync   = 0;
			counting     = 1;
		end
	end

	// A field is its vertical blanking, where the flip-flop changes over and
	// the sync pulse places the raster, and then the picture that follows.
	task automatic run_field;
		begin
			clocks     = 0;
			line_count = 0;
			lit_dots   = 0;
			showing    = field;
			do begin
				if (h_count == 0) begin
					lines[line_count] = scan_line;
					line_count++;
				end
				if (!hblank && !vblank && {red, green, blue} != 24'h000000) lit_dots++;
				if (!vblank && field !== showing) begin
					failures++;
					$display("FAIL: the field changed during the picture, line %0d", scan_line);
				end
				@(negedge clk);
				clocks++;
			end while (!(v_count == 192 && h_count == 0));
		end
	endtask

	task automatic to_blanking;
		begin
			@(negedge clk);
			while (!(v_count == 192 && h_count == 0)) @(negedge clk);
		end
	endtask

	// 448..511, 250..255, then the picture's 256..447.
	function automatic logic ordinary_lines;
		ordinary_lines = (line_count == 262);
		for (integer i = 0; i < 64; i++) if (lines[i] != 448 + i) ordinary_lines = 0;
		for (integer i = 0; i < 6; i++) if (lines[64+i] != 250 + i) ordinary_lines = 0;
		for (integer i = 0; i < 192; i++) if (lines[70+i] != 256 + i) ordinary_lines = 0;
	endfunction
	// 448..507, 509..511, 248..255, then the picture's 256..447.
	function automatic logic long_lines;
		long_lines = (line_count == 263);
		for (integer i = 0; i < 60; i++) if (lines[i] != 448 + i) long_lines = 0;
		for (integer i = 0; i < 3; i++) if (lines[60+i] != 509 + i) long_lines = 0;
		for (integer i = 0; i < 8; i++) if (lines[63+i] != 248 + i) long_lines = 0;
		for (integer i = 0; i < 192; i++) if (lines[71+i] != 256 + i) long_lines = 0;
	endfunction

	integer page1_dots, page2_dots, upper_dots, lower_dots;
	logic upper_field;

	// The lit dots of each of the next two fields.
	task automatic run_pair;
		begin
			run_field;
			if (showing) upper_dots = lit_dots;
			else lower_dots = lit_dots;
			upper_field = showing;
			run_field;
			if (showing) upper_dots = lit_dots;
			else lower_dots = lit_dots;
			if (showing === upper_field) begin
				failures++;
				$display("FAIL: two fields running showed the same field flag");
			end
		end
	endtask

	initial begin
		// Graphics page 1 is blank but for one byte; page 2 is solid.  The
		// 560-dot mode reads $2000/$4000 for page 1 and $6000/$8000 for 2,
		// which are $0000.. and $4000.. of bank 0.
		for (integer i = 0; i < 'h4000; i++) begin
			poke('h0000 + i, 8'h00);
			poke('h4000 + i, 8'h7f);
		end
		poke('h0000, 8'h7f);
		// Text page 1 at $0400/$0800 of the system bank, blank.
		for (integer i = 0; i < 'h400; i++) begin
			poke('h78400 + i, 8'ha0);
			poke('h78800 + i, 8'ha0);
		end
		for (integer i = 0; i < 1024; i++) video.character_ram[i] = 8'h00;
		video.flash_count = 0;

		// The switch is off: an Apple ///.
		video_mode = 4'b1010;
		to_blanking;
		run_field;
		check(showing && clocks == 262 * 912 && ordinary_lines(), "switch off: 262 lines, 448..511 then 250..447");
		check(sync_line == 483 && sync_dot == 252, "switch off: vertical sync begins at H = 16 of line 483");
		page1_dots = lit_dots;
		check(page1_dots == 7, "page 1 shows its one lit byte");
		video_mode = 4'b1110;
		run_field;
		page2_dots = lit_dots;
		check(showing && page2_dots == 560 * 192, "switch off: PAGE2 shows page 2 in every frame");
		run_field;
		check(sync_spacing == 262 * 912, "switch off: vertical sync every 262 lines");

		// The switch is on.
		interlace  = 1;
		video_mode = 4'b1010;
		run_field;
		run_field;
		for (integer pair = 0; pair < 2; pair++) begin
			run_field;
			if (showing) begin
				check(clocks == 262 * 912 && ordinary_lines(), "upper field: 262 lines, 448..511 then 250..447");
				check(sync_line == 483 && sync_dot == 252, "upper field: vertical sync begins at H = 16 of line 483");
				check(sync_spacing == 263 * 912 - 448,
					  "upper field's sync follows the lower's by 262 lines and 33 states");
			end else begin
				check(clocks == 263 * 912 && long_lines(), "lower field: 263 lines, 448..507, 509..511, 248..447");
				check(sync_line == 483 && sync_dot == 700,
					  "lower field: vertical sync begins on line 483's horizontal pulse");
				check(sync_spacing == 262 * 912 + 448,
					  "lower field's sync follows the upper's by 262 lines and 32 states");
			end
		end

		// FORCPAGE.  Page 1 selected: both fields are page 1.
		run_pair;
		check(upper_dots == page1_dots && lower_dots == page1_dots, "page 1 selected: the fields are the same picture");
		// Page 2 selected: the upper field honours it, the lower is forced to 1.
		video_mode = 4'b1110;
		run_pair;
		check(upper_dots == page2_dots && lower_dots == page1_dots, "page 2 selected: page 2 above, page 1 below");
		// Every native mode is forced alike; 40-column text page 2 is $0800.
		video_mode = 4'b0100;
		poke('h78800, 8'h81);
		video.character_ram[{7'h01, 3'd0}] = 8'h7f;
		run_pair;
		check(upper_dots == 14 && lower_dots == 0, "native text page 2: only the upper field reads $0800");
		// The emulation terms of the mode PROM do not contain FORCPAGE.
		native_mode = 0;
		video_mode  = 4'b0101;
		run_pair;
		check(upper_dots == 14 && lower_dots == 14, "emulation text page 2: both fields read $0800");
		native_mode = 1;

		// Switch off again: the ordinary field at once, and for good.
		interlace  = 0;
		video_mode = 4'b1110;
		run_field;
		run_field;
		check(showing && clocks == 262 * 912 && ordinary_lines() && lit_dots == page2_dots,
			  "switch off again: 262 lines and page 2");

		if (failures) $fatal(1, "interlace: %0d failed checks", failures);
		$display("PASS interlace fields, sync and page forcing");
		$finish;
	end
endmodule
