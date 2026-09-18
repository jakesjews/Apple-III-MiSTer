// Apple /// RGB video generator.
//
// The scanner reads display memory in the video half of every horizontal
// state, all 65 states of all 262 lines, as the motherboard does.  A processor
// write therefore reaches the screen if it lands before the scanner's slot for
// that byte, and the character generator is loaded by the same reads when the
// scan PROM's RTCWRT window finds the scanner in the text-page screen holes.
// Address and pixel rules are derived from the service manual, video/mux
// PROMs, Apple's US4383296/US4533909 patents, SOS console driver, and
// diskhero; MAME is a secondary cross-check.

module apple3_video (
	input logic       clk,
	input logic       reset,
	input logic [9:0] h_count,
	input logic [8:0] v_count,
	input logic [6:0] h_state,
	input logic [3:0] state_dot,
	input logic       frame_tick,
	input logic       screen_enable,
	input logic       native_mode,
	input logic [3:0] video_mode,
	input logic       smooth_enable,
	input logic [2:0] smooth_offset,
	input logic       character_write,
	input logic       character_slot,

	output logic [17:0] ram_addr,
	input  logic [15:0] ram_q,

	output logic [7:0] red,
	output logic [7:0] green,
	output logic [7:0] blue,
	output logic       hblank,
	output logic       vblank,
	output logic       hsync,
	output logic       vsync
);

	logic [7:0] character_ram[0:1023];
	logic [5:0] flash_count;

	// Each state's read returns a primary byte and its secondary partner: the
	// sister byte in text modes, the matching byte of the other 8 KiB plane in
	// graphics modes.  A pair reaches the pixel stage two states after it was
	// read, and 140-colour mode also sees the pairs on either side of it.
	logic [7:0] slot_low, slot_high;
	logic [7:0] next_low, next_high;
	logic [7:0] pixel_low, pixel_high;
	logic [7:0] prev_low, prev_high;

	logic [7:0] vertical;
	logic [18:0] primary_address, secondary_address;
	logic primary_lane, secondary_lane;
	logic state_end;

	// A download-window read waits here for the next state's write strobe.
	logic       download_pending;
	logic [6:0] download_code;
	logic [2:0] download_row;
	logic [7:0] download_bitmap;

	logic [7:0] char_code, glyph;
	logic [7:0] bitmap_byte, colour_byte;
	logic [3:0] colour_index;
	logic [2:0] glyph_row;
	logic [2:0] glyph_column;
	logic pixel_on, invert_pixel;
	logic       second_char;
	logic [2:0] char_dot;
	logic [4:0] within_28;
	logic [7:0] p1, p2, p3, p4;
	logic [27:0] packed_140;
	logic        graphics_palette;
	logic        apple2_hires;
	logic [3:0] fetch_mode, pixel_mode;

	// V7..V0 of the vertical counter, which runs 256..511 then 250..255.
	// Visible line y is counter value 256 + y, which puts every blanking line
	// in the top quarter (V7..V6 = 3) where the scanner reaches the holes.
	assign vertical  = (v_count < 9'd256) ? v_count[7:0] : v_count[7:0] - 8'd6;
	assign state_end = (h_state == 7'd64) ? (state_dot == 4'd15) : (state_dot == 4'd13);

	// A pair read in state S is shifted out during state S + 2, so blanking and
	// sync trail the scan counter by 28 dots.  The guest's own blanking input
	// (E-VIA PB6) and VBL stay on the counter, as the scan PROM drives them.
	assign hblank = (h_count < 10'd28) || (h_count >= 10'd588);
	assign vblank = (v_count >= 9'd192);
	assign hsync  = (h_count >= 10'd700) && (h_count < 10'd756);
	assign vsync  = (v_count >= 9'd224) && (v_count < 9'd228);

	// In emulation VM0/VM1/VM3 are TEXT/MIXED/HIRES, not the native
	// three-bit mode number. Mixed graphics ends at scan line 160.
	function automatic [3:0] display_mode(input logic [8:0] y);
		if (native_mode) display_mode = {1'b0, video_mode[3], video_mode[1:0]};
		else if (video_mode[0] || (video_mode[1] && y >= 9'd160)) display_mode = 4'd0;
		else display_mode = video_mode[3] ? 4'd4 : 4'd8;
	endfunction

	function automatic [23:0] palette_rgb(input logic [3:0] index, input logic graphics);
		begin
			// Nibbles are expanded to eight bits below.  Text and graphics use
			// slightly different grey/pink/aqua values on original RGB hardware.
			if (!graphics) begin
				case (index)
					4'h0:    palette_rgb = 24'h000000;
					4'h1:    palette_rgb = 24'h550055;
					4'h2:    palette_rgb = 24'h000099;
					4'h3:    palette_rgb = 24'hdd22dd;
					4'h4:    palette_rgb = 24'h007722;
					4'h5:    palette_rgb = 24'haaaaaa;
					4'h6:    palette_rgb = 24'h2222ff;
					4'h7:    palette_rgb = 24'h66aaff;
					4'h8:    palette_rgb = 24'h885500;
					4'h9:    palette_rgb = 24'hff6600;
					4'ha:    palette_rgb = 24'h555555;
					4'hb:    palette_rgb = 24'hff99ff;
					4'hc:    palette_rgb = 24'h11dd00;
					4'hd:    palette_rgb = 24'heeee00;
					4'he:    palette_rgb = 24'h44eedd;
					default: palette_rgb = 24'hffffff;
				endcase
			end else begin
				case (index)
					4'h0:    palette_rgb = 24'h000000;
					4'h1:    palette_rgb = 24'hdd0033;
					4'h2:    palette_rgb = 24'h000099;
					4'h3:    palette_rgb = 24'hdd22dd;
					4'h4:    palette_rgb = 24'h007722;
					4'h5:    palette_rgb = 24'h555555;
					4'h6:    palette_rgb = 24'h2222ff;
					4'h7:    palette_rgb = 24'h66aaff;
					4'h8:    palette_rgb = 24'h885500;
					4'h9:    palette_rgb = 24'hff6600;
					4'ha:    palette_rgb = 24'haaaaaa;
					4'hb:    palette_rgb = 24'hff9988;
					4'hc:    palette_rgb = 24'h11dd00;
					4'hd:    palette_rgb = 24'hffff00;
					4'he:    palette_rgb = 24'h44ff99;
					default: palette_rgb = 24'hffffff;
				endcase
			end
		end
	endfunction

	always_comb begin : address_generation
		logic [ 3:0] line_group;
		logic [ 9:0] text_offset;
		logic [ 2:0] graphics_row;
		logic [14:0] graphics_base;
		logic [18:0] fetch_address;

		// A9..A0 = V5..V3, (H5..H3 + 5 x V7..V6) mod 16, H2..H0.  The adder
		// places the three 40-byte line groups inside each 128-byte block; its
		// wrap reaches the eight-byte screen hole at H5..H3 = 0 in every
		// blanking line.  The extended state repeats H = 0 (h_state 64 has
		// h_state[5:0] = 0), so it reads the same word as the first column.
		line_group    = h_state[5:3] + {vertical[7:6], 2'b00} + {2'b00, vertical[7:6]};
		text_offset   = {vertical[5:3], line_group, h_state[2:0]};
		// Vertical blanking forces the text map: every DHIRES term of the mode
		// PROM (342-0032) carries /VBL, so the character-download window reads
		// the screen holes whatever mode is selected.
		fetch_mode    = vblank ? 4'd0 : display_mode(v_count);
		apple2_hires  = (fetch_mode == 4'd4);
		graphics_row  = vertical[2:0] + (smooth_enable ? smooth_offset : 3'd0);
		graphics_base = 15'h0000;

		if (!fetch_mode[2]) begin
			// Text page 1 at $0400 and its sister byte in page 2 at $0800.
			primary_address   = {4'hf, 15'h0400 + {5'b00000, text_offset}};
			secondary_address = {4'hf, 15'h0800 + {5'b00000, text_offset}};
		end else begin
			// Page 2 sits at $4000/$6000 for the Apple /// native graphics
			// modes, but the Apple ][-compatible 280-pixel monochrome mode
			// keeps the Apple II location: its page 2 is CPU $4000, which
			// is physical $2000.  Confirmed against the Confidence
			// Program's "Apple ][ Hires page 2" test and MAME's
			// apple3_v.cpp, which selects hgr_map (base $2000) for VM2 in
			// that mode and hgr_map+$2000 in every other graphics mode.
			graphics_base     = (video_mode[2] ? (apple2_hires ? 15'h2000 : 15'h4000) : 15'h0000) +
				{2'b00, graphics_row, text_offset};
			primary_address = {4'h0, graphics_base};
			secondary_address = {4'h0, graphics_base} + 19'h02000;
		end

		// The motherboard's two CAS lines deliver both bytes in one cycle.  The
		// FPGA RAM pairs A with A xor $0c00, which covers the text sister but
		// not the $2000 graphics plane, so the primary is read in the first
		// four dots and the secondary in the rest of the video half.
		primary_lane   = primary_address[11];
		secondary_lane = secondary_address[11];
		fetch_address  = (state_dot < 4'd4) ? primary_address : secondary_address;
		ram_addr       = {fetch_address[18:12], fetch_address[10] ^ fetch_address[11], fetch_address[9:0]};
	end

	always_ff @(posedge clk) begin : fetch_and_character_load
		// RAM data lags its address by one clock: the primary byte is
		// sampled from dot 2's read and the secondary from dot 6's, both after
		// the previous state's processor slot and before this one's.
		if (state_dot == 4'd3) begin
			slot_low <= primary_lane ? ram_q[15:8] : ram_q[7:0];
			// WE2114* = NAND(ENCWRT, TCWRT, C1M*, Q0): the character RAM is
			// written in the video half of the state after the read, from the
			// latched pair, with $C0DB as it stands at that moment.
			if (download_pending && character_write) begin
				character_ram[{download_code, download_row}] <= download_bitmap;
			end
		end
		if (state_dot == 4'd7) begin
			slot_high        <= secondary_lane ? ram_q[15:8] : ram_q[7:0];
			// In a download window both addresses name the same text word:
			// the $04xx hole byte is the bitmap and its $08xx sister the code.
			// The font row is the scan line within the character, VC..VA.
			download_pending <= character_slot;
			download_code    <= ram_q[14:8];
			download_row     <= vertical[2:0];
			download_bitmap  <= ram_q[7:0];
		end

		if (state_end) begin
			prev_low   <= pixel_low;
			prev_high  <= pixel_high;
			pixel_low  <= next_low;
			pixel_high <= next_high;
			next_low   <= slot_low;
			next_high  <= slot_high;
		end

		if (reset) begin
			flash_count      <= 6'd0;
			download_pending <= 1'b0;
		end else if (frame_tick) begin
			flash_count <= flash_count + 1'b1;
		end
	end

	always_comb begin : pixel_generation
		logic [23:0] rgb;
		logic [ 2:0] bit_index;

		rgb       = 24'h000000;
		bit_index = 3'd0;

		char_code        = 8'h00;
		glyph            = 8'h00;
		bitmap_byte      = 8'h00;
		colour_byte      = 8'h00;
		colour_index     = 4'h0;
		graphics_palette = 1'b0;
		pixel_on         = 1'b0;
		invert_pixel     = 1'b0;
		// The displayed column is h_state - 2, so h_state's parity is the
		// column's and 140-colour groups still start on even columns.
		// Dots 7..13 are the second character or byte: 7 + 1 wraps to dot 0.
		second_char      = (state_dot >= 4'd7);
		char_dot         = state_dot[2:0] + {2'b00, second_char};
		within_28        = (h_state[0] ? 5'd14 : 5'd0) + {1'b0, state_dot};
		pixel_mode       = display_mode(v_count);
		glyph_row        = v_count[2:0] + (smooth_enable ? smooth_offset : 3'd0);
		glyph_column     = state_dot[3:1];
		p1               = 8'h00;
		p2               = 8'h00;
		p3               = 8'h00;
		p4               = 8'h00;
		packed_140       = 28'h0000000;

		if (!hblank && !vblank && screen_enable) begin
			case (pixel_mode)
				4'd0, 4'd1: begin
					// 40-column text: the other half of the sister pair carries colour.
					char_code    = video_mode[2] ? pixel_high : pixel_low;
					colour_byte  = video_mode[2] ? pixel_low : pixel_high;
					glyph        = character_ram[{char_code[6:0], glyph_row}];
					pixel_on     = glyph[glyph_column];
					invert_pixel = !char_code[7] && (!glyph[7] || flash_count[3]);
					pixel_on     = pixel_on ^ invert_pixel;
					if (video_mode[0] && native_mode) begin
						colour_index = pixel_on ? colour_byte[7:4] : colour_byte[3:0];
					end else begin
						colour_index = pixel_on ? 4'hf : 4'h0;
					end
				end

				4'd2, 4'd3: begin
					// 80-column text: page select exchanges the two 40-byte halves.
					char_code    = (second_char ^ video_mode[2]) ? pixel_high : pixel_low;
					glyph_column = char_dot;
					glyph        = character_ram[{char_code[6:0], glyph_row}];
					pixel_on     = glyph[glyph_column];
					invert_pixel = !char_code[7] && (!glyph[7] || flash_count[3]);
					pixel_on     = pixel_on ^ invert_pixel;
					colour_index = pixel_on ? 4'hc : 4'h0;
				end

				4'd4: begin
					bitmap_byte  = pixel_low;
					bit_index    = state_dot[3:1];
					colour_index = bitmap_byte[bit_index] ? 4'hf : 4'h0;
				end

				4'd5: begin
					bitmap_byte      = pixel_low;
					colour_byte      = pixel_high;
					bit_index        = state_dot[3:1];
					colour_index     = bitmap_byte[bit_index] ? colour_byte[7:4] : colour_byte[3:0];
					graphics_palette = 1'b1;
				end

				4'd6: begin
					bitmap_byte  = second_char ? pixel_high : pixel_low;
					bit_index    = char_dot;
					colour_index = bitmap_byte[bit_index] ? 4'hf : 4'h0;
				end

				4'd8: begin
					// Apple II 40x48 lores uses the text pages: one nibble for
					// each four-scan-line half of a character cell.
					colour_byte      = video_mode[2] ? pixel_high : pixel_low;
					colour_index     = glyph_row[2] ? colour_byte[7:4] : colour_byte[3:0];
					graphics_palette = 1'b1;
				end

				default: begin
					// Seven colours span an even column and the odd one after it.
					p1         = h_state[0] ? prev_low : pixel_low;
					p2         = h_state[0] ? prev_high : pixel_high;
					p3         = h_state[0] ? pixel_low : next_low;
					p4         = h_state[0] ? pixel_high : next_high;
					packed_140 = {p4[6:0], p3[6:0], p2[6:0], p1[6:0]};
					case (within_28[4:2])
						3'd0:    colour_index = packed_140[3:0];
						3'd1:    colour_index = packed_140[7:4];
						3'd2:    colour_index = packed_140[11:8];
						3'd3:    colour_index = packed_140[15:12];
						3'd4:    colour_index = packed_140[19:16];
						3'd5:    colour_index = packed_140[23:20];
						default: colour_index = packed_140[27:24];
					endcase
					graphics_palette = 1'b1;
				end
			endcase
		end

		rgb   = palette_rgb(colour_index, graphics_palette);
		red   = rgb[23:16];
		green = rgb[15:8];
		blue  = rgb[7:0];
	end

endmodule
