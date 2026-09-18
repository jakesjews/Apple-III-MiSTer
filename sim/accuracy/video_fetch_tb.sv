`timescale 1ns / 1ps
// Clocked display-fetch and character-download checks.  The scan counters,
// the video generator and the sister-byte RAM run together.  The bench stores
// to display memory and switches $C0DA/$C0DB with the timing of a processor
// B-slot access (the core's cpu_enable at dot 13 commits on the clock that ends
// the state) and reads the results from the screen and the character RAM.
module video_fetch_tb;
	logic clk = 0;
	always #5 clk = ~clk;

	logic slow_mode = 0, screen_enable = 1, peripheral_cycle = 0, ram_cycle = 0;
	wire cpu_enable, via_rising, via_falling, q3, pixel_enable, scan_hblank, scan_vblank;
	wire display_slot, refresh_slot, character_slot, frame_tick;
	wire [9:0] h_count;
	wire [8:0] v_count;
	wire [6:0] h_state;
	wire [3:0] state_dot;
	apple3_timing timing (
		.clk_14m(clk),
		.slow_mode,
		.screen_enable,
		.peripheral_cycle,
		.ram_cycle,
		.cpu_enable,
		.via_rising,
		.via_falling,
		.q3,
		.pixel_enable,
		.hblank (scan_hblank),
		.vblank (scan_vblank),
		.display_slot,
		.refresh_slot,
		.character_slot,
		.h_count,
		.v_count,
		.h_state,
		.state_dot,
		.frame_tick
	);

	logic [17:0] cpu_addr = 0;
	logic cpu_lane = 0, cpu_we = 0;
	logic [7:0] cpu_din = 0;
	wire [15:0] cpu_q, video_q;
	wire [17:0] video_addr;
	apple3_ram #(
		.WORD_ADDRESS_BITS(17)
	) ram (
		.clk,
		.cpu_addr,
		.cpu_lane,
		.cpu_we,
		.cpu_din,
		.cpu_q,
		.video_addr,
		.video_q
	);

	logic reset = 1, native_mode = 1, smooth_enable = 0, character_write = 0;
	logic [3:0] video_mode = 0;
	logic [2:0] smooth_offset = 0;
	wire [7:0] red, green, blue;
	wire hblank, vblank, hsync, vsync;
	apple3_video video (
		.clk,
		.reset,
		.h_count,
		.v_count,
		.h_state,
		.state_dot,
		.frame_tick,
		.screen_enable,
		.native_mode,
		.video_mode,
		.smooth_enable,
		.smooth_offset,
		.character_write,
		.character_slot,
		.ram_addr(video_addr),
		.ram_q   (video_q),
		.red,
		.green,
		.blue,
		.hblank,
		.vblank,
		.hsync,
		.vsync
	);

	localparam integer TEXT_PAGE = 'h78400;  // system bank $0400; its sister is $0800
	localparam integer SISTER    = 'h400;
	localparam integer PLANE     = 'h2000;   // second 8 KiB graphics plane (CPU $4000)

	integer failures = 0, errors, seed = 7;
	integer line, before_line, before_state;
	integer       render_errors[0:20];
	logic   [4:0] expected;

	// Every visible dot of the frame being drawn: lit (non-black) or black.
	logic [559:0] lit[0:191];
	always @(negedge clk) if (v_count < 192 && !hblank) lit[v_count][h_count-28] <= ({red, green, blue} != 24'h000000);

	task automatic check(input logic ok, input string message);
		if (ok !== 1'b1) begin
			failures++;
			$display("FAIL: %s", message);
		end else $display("PASS: %s", message);
	endtask

	function automatic integer text_address(input integer line, input integer column);
		text_address = TEXT_PAGE + ((line / 8) % 8) * 128 + (line / 64) * 40 + column;
	endfunction
	function automatic integer graphics_address(input integer line, input integer column);
		graphics_address = (line % 8) * 1024 + ((line / 8) % 8) * 128 + (line / 64) * 40 + column;
	endfunction
	// Download cells: hole h (text rows 0..7) byte p.  The page 1 byte is the
	// bitmap, its page 2 sister the code, and the font row 2 x (h mod 4) + p/4.
	function automatic integer hole_address(input integer hole, input integer offset);
		hole_address = TEXT_PAGE + hole * 128 + 'h78 + offset;
	endfunction
	function automatic integer hole_entry(input integer hole, input integer offset);
		hole_entry = (8 * hole + offset) * 8 + 2 * (hole % 4) + offset / 4;
	endfunction
	// The blanking line that reads the byte: V5..V3 = h, V2..V1 = V4..V3 and
	// V0 = the byte's H2.  Lines 192..255 are counter values 448..511.
	function automatic integer hole_line(input integer hole, input integer offset);
		hole_line = 192 + hole * 8 + (hole % 4) * 2 + offset / 4;
	endfunction
	function automatic [7:0] old_bitmap(input integer hole, input integer offset);
		old_bitmap = 8'h80 | (hole << 3) | offset;
	endfunction
	function automatic [7:0] new_bitmap(input integer hole, input integer offset);
		new_bitmap = 8'h40 | (hole << 3) | offset;
	endfunction
	function automatic [6:0] pattern(input integer column);
		pattern = ((column * 37 + 11) % 127) + 1;
	endfunction
	// {native, VM3..VM0} for every rendering check: native text, colour text,
	// 80 columns, 280-dot, fg/bg colour, 560-dot and 140-colour on both pages,
	// then the emulation lores, text, hires and mixed modes.
	function automatic [4:0] configuration(input integer index);
		case (index)
			0:       configuration = 5'h10;
			1:       configuration = 5'h14;
			2:       configuration = 5'h11;
			3:       configuration = 5'h15;
			4:       configuration = 5'h12;
			5:       configuration = 5'h16;
			6:       configuration = 5'h18;
			7:       configuration = 5'h1c;
			8:       configuration = 5'h19;
			9:       configuration = 5'h1d;
			10:      configuration = 5'h1a;
			11:      configuration = 5'h1e;
			12:      configuration = 5'h1b;
			13:      configuration = 5'h1f;
			14:      configuration = 5'h00;
			15:      configuration = 5'h04;
			16:      configuration = 5'h01;
			17:      configuration = 5'h08;
			18:      configuration = 5'h0c;
			19:      configuration = 5'h0a;
			default: configuration = 5'h02;
		endcase
	endfunction

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
	function automatic [7:0] peek(input integer physical);
		logic [18:0] address;
		logic [17:0] word;
		address = physical;
		word    = word_of(address);
		peek    = address[11] ? ram.mem[word[16:0]][15:8] : ram.mem[word[16:0]][7:0];
	endfunction

	task automatic wait_for(input integer line, input integer state, input integer dot);
		@(negedge clk);
		while (v_count != line || h_state != state || state_dot != dot) @(negedge clk);
	endtask
	// A store in the B slot of (line, state).  State 64's B slot is also dot 13.
	task automatic cpu_store(input integer line, input integer state, input integer physical, input logic [7:0] value);
		logic [18:0] address;
		address = physical;
		wait_for(line, state, 13);
		cpu_addr = word_of(address);
		cpu_lane = address[11];
		cpu_din  = value;
		cpu_we   = 1;
		@(posedge clk);
		#1 cpu_we = 0;
	endtask
	// $C0DA/$C0DB in the B slot of (line, state): the latch changes with the
	// clock that ends the state, as apple3_io's does on cycle_strobe.
	task automatic download_switch(input integer line, input integer state, input logic enable);
		wait_for(line, state, 13);
		@(posedge clk);
		#1 character_write = enable;
	endtask
	task automatic next_blanking;
		wait_for(192, 0, 0);
	endtask

	// Seven dots of a column from its first dot, one per master dot, and the
	// seven double-width dots of a 280-dot column; bit 0 is leftmost.
	function automatic [6:0] seven_dots(input integer line, input integer column, input integer first);
		for (integer i = 0; i < 7; i++) seven_dots[i] = lit[line][column*14+first+i];
	endfunction
	function automatic [6:0] wide_dots(input integer line, input integer column);
		for (integer i = 0; i < 7; i++) wide_dots[i] = lit[line][column*14+2*i];
	endfunction

	task automatic reset_download(input logic [7:0] sentinel);
		for (integer entry = 0; entry < 1024; entry++) video.character_ram[entry] = sentinel;
		for (integer hole = 0; hole < 8; hole++)
			for (integer offset = 0; offset < 8; offset++) begin
				poke(hole_address(hole, offset), old_bitmap(hole, offset));
				poke(hole_address(hole, offset) + SISTER, 8 * hole + offset);
			end
	endtask
	// Holes whose cells hold the old or new bitmap; everything else keeps the
	// sentinel.  Returns the number of character RAM entries that differ.
	function automatic integer download_errors(input logic [7:0] loaded_holes, input logic [7:0] new_holes);
		integer count, entry;
		logic [   7:0] want;
		logic [1023:0] cells;
		count = 0;
		cells = 0;
		for (integer hole = 0; hole < 8; hole++)
		for (integer offset = 0; offset < 8; offset++) begin
			entry = hole_entry(hole, offset);
			cells[entry] = 1;
			want = !loaded_holes[hole] ? 8'h5a : new_holes[hole] ? new_bitmap(hole, offset) : old_bitmap(hole, offset);
			if (video.character_ram[entry] !== want) count++;
		end
		for (integer entry = 0; entry < 1024; entry++)
		if (!cells[entry] && video.character_ram[entry] !== 8'h5a) count++;
		download_errors = count;
	endfunction

	function automatic logic text_dot(input logic [7:0] code, input integer line, input integer column);
		logic [7:0] glyph;
		glyph    = video.character_ram[{code[6:0], line[2:0]}];
		text_dot = glyph[column] ^ (!code[7] && (!glyph[7] || video.flash_count[3]));
	endfunction
	function automatic [27:0] colour_group(input integer base, input integer line, input integer even);
		logic [7:0] p1, p2, p3, p4;
		p1           = peek(base + graphics_address(line, even));
		p2           = peek(base + PLANE + graphics_address(line, even));
		p3           = peek(base + graphics_address(line, even + 1));
		p4           = peek(base + PLANE + graphics_address(line, even + 1));
		colour_group = {p4[6:0], p3[6:0], p2[6:0], p1[6:0]};
	endfunction

	// Expected {graphics palette, colour index} from the SRM mode descriptions
	// and DESIGN.md, read straight from memory.
	function automatic [4:0] reference_pixel(input integer line, input integer column, input integer dot);
		integer text, base;
		logic page2;
		logic [7:0] first, second, colour, bitmap;
		logic [27:0] group;
		page2 = video_mode[2];
		text  = text_address(line, column);
		base  = page2 ? 'h4000 : 0;
		if (!native_mode && (video_mode[0] || (video_mode[1] && line >= 160))) begin
			first           = page2 ? peek(text + SISTER) : peek(text);
			reference_pixel = text_dot(first, line, dot / 2) ? 5'h0f : 5'h00;
		end else if (!native_mode && !video_mode[3]) begin
			colour          = page2 ? peek(text + SISTER) : peek(text);
			reference_pixel = {1'b1, (line % 8 >= 4) ? colour[7:4] : colour[3:0]};
		end else if (!native_mode || video_mode[1:0] == 2'b00 && video_mode[3]) begin
			// Apple ][ hires and native 280-dot monochrome keep page 2 at $2000.
			bitmap          = peek((page2 ? 'h2000 : 0) + graphics_address(line, column));
			reference_pixel = bitmap[dot/2] ? 5'h0f : 5'h00;
		end else begin
			case ({
				video_mode[3], video_mode[1:0]
			})
				3'b000: begin
					first           = page2 ? peek(text + SISTER) : peek(text);
					reference_pixel = text_dot(first, line, dot / 2) ? 5'h0f : 5'h00;
				end
				3'b001: begin
					first           = page2 ? peek(text + SISTER) : peek(text);
					colour          = page2 ? peek(text) : peek(text + SISTER);
					reference_pixel = {1'b0, text_dot(first, line, dot / 2) ? colour[7:4] : colour[3:0]};
				end
				3'b010, 3'b011: begin
					first           = page2 ? peek(text + SISTER) : peek(text);
					second          = page2 ? peek(text) : peek(text + SISTER);
					reference_pixel = text_dot((dot < 7) ? first : second, line, dot % 7) ? 5'h0c : 5'h00;
				end
				3'b101: begin
					bitmap          = peek(base + graphics_address(line, column));
					colour          = peek(base + PLANE + graphics_address(line, column));
					reference_pixel = {1'b1, bitmap[dot/2] ? colour[7:4] : colour[3:0]};
				end
				3'b110: begin
					bitmap          = peek(base + (dot < 7 ? 0 : PLANE) + graphics_address(line, column));
					reference_pixel = bitmap[dot%7] ? 5'h0f : 5'h00;
				end
				default: begin
					group           = colour_group(base, line, column & ~1);
					reference_pixel = {1'b1, group[(((column%2)*14+dot)/4)*4+:4]};
				end
			endcase
		end
	endfunction

	initial begin
		// Power-on memory: zeros, and a sentinel in every character RAM row.
		for (integer word = 0; word < (1 << 17); word++) ram.mem[word] = 16'h0000;
		for (integer entry = 0; entry < 1024; entry++) video.character_ram[entry] = 8'h5a;
		repeat (4) @(posedge clk);
		reset = 0;

		// Static rendering through the fetch path.  Random text pages, graphics
		// pages and character RAM; every visible dot of one line in each third
		// of the screen for every native and emulation mode on both pages.  A
		// line is read while it is drawn, so a mode set in the blanking before
		// it governs the whole line and all 21 fit in one frame.
		for (integer offset = 0; offset < 'h800; offset++) poke(TEXT_PAGE + offset, $random(seed));
		for (integer offset = 0; offset < 'h8000; offset++) poke(offset, $random(seed));
		for (integer entry = 0; entry < 1024; entry++) video.character_ram[entry] = $random(seed);
		for (integer index = 0; index < 21; index++) render_errors[index] = 0;
		next_blanking;
		for (integer third = 0; third < 3; third++)
		for (integer index = 0; index < 21; index++) begin
			line = 64 * third + 3 * index + third;
			if (line > 0) wait_for(line - 1, 50, 0);
			{native_mode, video_mode} = configuration(index);
			wait_for(line, 2, 0);
			for (integer column = 0; column < 40; column++)
			for (integer dot = 0; dot < 14; dot++) begin
				expected = reference_pixel(line, column, dot);
				if (video.colour_index !== expected[3:0] ||
					(expected[3:0] != 4'h0 && expected[3:0] != 4'hf && video.graphics_palette !== expected[4])) begin
					if (render_errors[index] < 3)
						$display(
							"  mode %s%x line %0d column %0d dot %0d: expected %x, got %x",
							native_mode ? "native " : "emulation ",
							video_mode,
							line,
							column,
							dot,
							expected,
							{
								video.graphics_palette, video.colour_index
							}
						);
					render_errors[index]++;
				end
				@(negedge clk);
			end
		end
		for (integer index = 0; index < 21; index++) begin
			expected = configuration(index);
			check(render_errors[index] == 0, $sformatf(
				  "%s mode %x renders every dot of three lines from RAM",
				  expected[4] ? "native" : "emulation",
				  expected[3:0]
				  ));
		end
		native_mode = 1;

		// Writes during active display.  The scanner reads each column in the
		// video half of that column's own state, so a store in the B slot of the
		// state before it shows on the line being drawn, and one in the
		// column's own state misses that frame.
		for (integer column = 0; column < 40; column++) begin
			for (integer line = 60; line < 64; line++) begin
				poke(graphics_address(line, column), 0);
				poke(PLANE + graphics_address(line, column), 0);
			end
		end
		video_mode = 4'b1000;
		next_blanking;
		cpu_store(59, 64, graphics_address(60, 0), pattern(0));
		for (integer column = 1; column < 40; column++)
		cpu_store(60, column - 1, graphics_address(60, column), pattern(column));
		for (integer column = 0; column < 40; column++)
		cpu_store(61, column, graphics_address(61, column), pattern(column));
		next_blanking;
		errors = 0;
		for (integer column = 0; column < 40; column++) if (wide_dots(60, column) !== pattern(column)) errors++;
		check(errors == 0, "a store in the state before each column's slot shows on the line being drawn");
		errors = 0;
		for (integer column = 0; column < 40; column++) if (wide_dots(61, column) !== 7'h00) errors++;
		check(errors == 0, "a store in each column's own state misses the line in that frame");
		next_blanking;
		errors = 0;
		for (integer column = 0; column < 40; column++) if (wide_dots(61, column) !== pattern(column)) errors++;
		check(errors == 0, "the late stores appear on the next frame");

		// The second graphics plane is read later in the same video half.
		video_mode = 4'b1010;
		cpu_store(61, 64, PLANE + graphics_address(62, 0), pattern(0));
		for (integer column = 1; column < 40; column++)
		cpu_store(62, column - 1, PLANE + graphics_address(62, column), pattern(column));
		for (integer column = 0; column < 40; column++)
		cpu_store(63, column, PLANE + graphics_address(63, column), pattern(column));
		next_blanking;
		errors = 0;
		for (integer column = 0; column < 40; column++)
		if (seven_dots(62, column, 7) !== pattern(column) || seven_dots(62, column, 0) !== 7'h00) errors++;
		for (integer column = 0; column < 40; column++) if (seven_dots(63, column, 7) !== 7'h00) errors++;
		check(errors == 0, "560-dot second plane has the same store boundary as the first");

		// Text is re-read on every scan line of a row, so a store just after a
		// column's slot misses only the current scan line.  Code $41 is blank
		// and $42 solid in every row; the stores go to text rows 8 and 9.
		for (integer row = 0; row < 8; row++) begin
			video.character_ram[{7'h41, row[2:0]}] = 8'h00;
			video.character_ram[{7'h42, row[2:0]}] = 8'h7f;
		end
		for (integer column = 0; column < 40; column++) begin
			poke(text_address(64, column), 8'hc1);
			poke(text_address(72, column), 8'hc1);
			poke(text_address(80, column), 8'hc1);
			poke(text_address(80, column) + SISTER, 8'hc1);
		end
		video_mode = 4'b0000;
		cpu_store(63, 64, text_address(64, 0), 8'hc2);
		for (integer column = 1; column < 40; column++) cpu_store(64, column - 1, text_address(64, column), 8'hc2);
		for (integer column = 0; column < 40; column++) cpu_store(72, column, text_address(72, column), 8'hc2);
		next_blanking;
		errors = 0;
		for (integer column = 0; column < 40; column++) begin
			if (wide_dots(64, column) !== 7'h7f) errors++;
			if (wide_dots(72, column) !== 7'h00 || wide_dots(73, column) !== 7'h7f) errors++;
		end
		check(errors == 0, "40-column text: early stores show at once, late ones from the next scan line");

		// 80 columns take the second character of each pair from the sister
		// byte, which arrives with the same read.
		video_mode = 4'b0010;
		cpu_store(79, 64, text_address(80, 0) + SISTER, 8'hc2);
		for (integer column = 1; column < 40; column++)
		cpu_store(80, column - 1, text_address(80, column) + SISTER, 8'hc2);
		next_blanking;
		errors = 0;
		for (integer column = 0; column < 40; column++)
		if (seven_dots(80, column, 0) !== 7'h00 || seven_dots(80, column, 7) !== 7'h7f) errors++;
		check(errors == 0, "80-column sister characters follow the same store boundary");

		// Character download.  Each hole byte is read in its own window and
		// written to the character RAM in the next state.
		video_mode = 4'b0000;
		reset_download(8'h5a);
		wait_for(0, 0, 0);
		check(download_errors(8'h00, 8'h00) == 0, "no character RAM writes while $C0DA is selected");

		download_switch(100, 10, 1);
		download_switch(10, 0, 0);
		check(download_errors(8'hff, 8'h00) == 0, "one blanking interval loads all 64 cells with $C0DB selected");

		reset_download(8'h5a);
		download_switch(223, 10, 1);
		download_switch(10, 0, 0);
		check(download_errors(8'hf0, 8'h00) == 0, "enabling after line 223 loads only holes 4 to 7");

		reset_download(8'h5a);
		download_switch(100, 10, 1);
		download_switch(213, 10, 0);
		wait_for(10, 0, 0);
		check(download_errors(8'h07, 8'h00) == 0, "disabling after line 213 keeps only holes 0 to 2");

		// Every one of the 64 read slots: a store in the B slot just before it
		// is captured, one in its own state is not.  Hole 7 is read again on
		// the last two lines, where the counter repeats 254 and 255.
		reset_download(8'h5a);
		download_switch(100, 10, 1);
		for (integer hole = 0; hole < 8; hole++)
		for (integer offset = 0; offset < 8; offset++) begin
			before_line  = hole_line(hole, offset) - (offset == 0);
			before_state = (offset == 0) ? 64 : offset - 1;
			cpu_store(before_line, before_state, hole_address(hole, offset), new_bitmap(hole, offset));
		end
		download_switch(10, 0, 0);
		check(download_errors(8'hff, 8'hff) == 0, "every hole byte stored just before its read slot is loaded");

		reset_download(8'h5a);
		download_switch(100, 10, 1);
		for (integer hole = 0; hole < 8; hole++)
		for (integer offset = 0; offset < 8; offset++)
		cpu_store(hole_line(hole, offset), offset, hole_address(hole, offset), new_bitmap(hole, offset));
		download_switch(10, 0, 0);
		check(download_errors(8'hff, 8'h80) == 0,
			  "a store in each read slot's own state is missed, except hole 7's repeat on lines 260-261");

		// $C0DB takes effect from the state after the access, when the write
		// strobe of the previous state's read falls.
		reset_download(8'h5a);
		download_switch(192, 1, 1);
		download_switch(192, 10, 0);
		wait_for(10, 0, 0);
		errors = 0;
		for (integer offset = 0; offset < 8; offset++)
		if (video.character_ram[hole_entry(
				0, offset
			)] !== ((offset == 1 || offset == 2 || offset == 3) ? old_bitmap(
				0, offset
			) : 8'h5a))
			errors++;
		check(errors == 0, "$C0DB in state 1 of line 192 misses byte 0 and loads bytes 1 to 3");

		reset_download(8'h5a);
		download_switch(100, 10, 1);
		download_switch(192, 1, 0);
		download_switch(10, 0, 0);
		errors = 0;
		for (integer offset = 0; offset < 4; offset++)
		if (video.character_ram[hole_entry(0, offset)] !== ((offset == 0) ? old_bitmap(0, offset) : 8'h5a)) errors++;
		check(errors == 0, "$C0DA in state 1 of line 192 still loads byte 0");

		// Blanking forces the text map, so the download works in a graphics
		// mode, and with the screen switched off.
		reset_download(8'h5a);
		video_mode    = 4'b1011;
		screen_enable = 0;
		download_switch(100, 10, 1);
		download_switch(10, 0, 0);
		check(download_errors(8'hff, 8'h00) == 0, "140-colour mode with the screen off still loads every cell");
		screen_enable = 1;

		$display("fetch timing: %0d failed checks", failures);
		if (failures) $fatal(1, "video fetch timing discrepancies");
		$finish;
	end
endmodule
