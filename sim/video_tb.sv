`timescale 1ns / 1ps

module video_tb;
	logic clk = 0, reset = 1;
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
	always #5 clk = ~clk;

	task automatic sample (input [6:0] state, input [3:0] dot);
		begin
			h_state   = state;
			state_dot = dot;
			h_count   = state * 14 + dot;
			#1;
		end
	endtask

	initial begin
		repeat (2) @(posedge clk);
		reset                            = 0;
		// Character A row 0 has its low bit set. Normal characters use bit 7.
		dut.line_buffer_low[0]           = 8'hc1;
		dut.line_buffer_high[0]          = 8'h21;
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
		video_mode              = 4'b1010;
		dut.line_buffer_low[0]  = 8'h01;
		dut.line_buffer_high[0] = 8'h02;
		sample (0, 0);
		if ({red, green, blue} !== 24'hffffff) $fatal(1, "SHGR plane 0");
		sample (0, 8);
		if ({red, green, blue} !== 24'hffffff) $fatal(1, "SHGR plane 1");

		// 140-mode ignores each byte's high bit and packs seven 4-bit colours.
		video_mode              = 4'b1011;
		dut.line_buffer_low[0]  = 8'h21;
		dut.line_buffer_high[0] = 8'h43;
		dut.line_buffer_low[1]  = 8'h65;
		dut.line_buffer_high[1] = 8'h07;
		sample (0, 0);
		if ({red, green, blue} !== 24'hdd0033) $fatal(1, "140 colour 0=%06x", {red, green, blue});
		sample (0, 4);
		// p1[6:4]=$2 and p2[0]=1 form palette index $a.
		if ({red, green, blue} !== 24'haaaaaa) $fatal(1, "140 colour 1=%06x", {red, green, blue});

		// Address generator: next text row, both sister pages, and graphics plane.
		v_count    = 0;
		h_count    = 600;
		video_mode = 0;
		#1;
		if (ram_addr !== 18'h3c400) $fatal(1, "text prefetch address=%05x", ram_addr);
		h_count = 640;
		#1;
		if (ram_addr !== 18'h3c400) $fatal(1, "text sister pairing=%05x", ram_addr);
		video_mode = 4'b1000;
		h_count    = 600;
		#1;
		if (ram_addr !== 18'h00400) $fatal(1, "graphics prefetch address=%05x", ram_addr);

		screen_enable = 0;
		h_count       = 0;
		h_state       = 0;
		state_dot     = 0;
		#1;
		if ({red, green, blue} !== 24'h000000) $fatal(1, "screen disable did not blank");

		$display("PASS apple3_video");
		$finish;
	end
endmodule
