// Apple /// RGB video generator.
//
// Display memory is prefetched into an 80-byte line buffer during horizontal
// blanking.  This preserves the machine's byte layout and lets the main 512 KiB
// store remain synchronous FPGA block RAM.  Address and pixel rules are derived
// from the service manual, video/mux PROMs, Apple's US4383296/US4533909 patents,
// SOS console driver, and diskhero; MAME is a secondary cross-check.

module apple3_video (
	input  logic        clk,
	input  logic        reset,
	input  logic [9:0]  h_count,
	input  logic [8:0]  v_count,
	input  logic [6:0]  h_state,
	input  logic [3:0]  state_dot,
	input  logic        frame_tick,
	input  logic        screen_enable,
	input  logic        native_mode,
	input  logic [3:0]  video_mode,
	input  logic        smooth_enable,
	input  logic [2:0]  smooth_offset,
	input  logic        character_write,

	output logic [17:0] ram_addr,
	input  logic [15:0] ram_q,

	output logic [7:0]  red,
	output logic [7:0]  green,
	output logic [7:0]  blue,
	output logic        hblank,
	output logic        vblank,
	output logic        hsync,
	output logic        vsync
);

	logic [7:0] line_buffer [0:79];
	logic [7:0] character_ram [0:1023];
	logic [5:0] flash_count;

	logic [8:0] next_y;
	logic [6:0] request_index;
	logic request_lane;
	logic line_request, character_request;
	logic request_valid_d, request_character_d, request_lane_d;
	logic [6:0] request_index_d;

	logic [7:0] char_code, glyph;
	logic [7:0] bitmap_byte, colour_byte;
	logic [3:0] colour_index;
	logic [2:0] glyph_row;
	logic [2:0] glyph_column;
	logic       pixel_on, invert_pixel;
	logic [6:0] char_position;
	logic [5:0] byte_position;
	logic [4:0] colour_position;
	logic [4:0] within_28;
	logic [7:0] p1, p2, p3, p4;
	logic [27:0] packed_140;
	logic graphics_palette;

	function automatic [10:0] text_line_base(input logic [4:0] row);
		logic [10:0] group_offset;
		begin
			case (row[4:3])
				2'd0: group_offset = 11'd0;
				2'd1: group_offset = 11'd40;
				default: group_offset = 11'd80;
			endcase
			text_line_base = 11'h400 + {row[2:0], 7'b0000000} + group_offset;
		end
	endfunction

	function automatic [23:0] palette_rgb(
		input logic [3:0] index,
		input logic graphics
	);
		begin
			// Nibbles are expanded to eight bits below.  Text and graphics use
			// slightly different grey/pink/aqua values on original RGB hardware.
			if (!graphics) begin
				case (index)
					4'h0: palette_rgb = 24'h000000;
					4'h1: palette_rgb = 24'h550055;
					4'h2: palette_rgb = 24'h000099;
					4'h3: palette_rgb = 24'hdd22dd;
					4'h4: palette_rgb = 24'h007722;
					4'h5: palette_rgb = 24'haaaaaa;
					4'h6: palette_rgb = 24'h2222ff;
					4'h7: palette_rgb = 24'h66aaff;
					4'h8: palette_rgb = 24'h885500;
					4'h9: palette_rgb = 24'hff6600;
					4'ha: palette_rgb = 24'h555555;
					4'hb: palette_rgb = 24'hff99ff;
					4'hc: palette_rgb = 24'h11dd00;
					4'hd: palette_rgb = 24'heeee00;
					4'he: palette_rgb = 24'h44eedd;
					default: palette_rgb = 24'hffffff;
				endcase
			end
			else begin
				case (index)
					4'h0: palette_rgb = 24'h000000;
					4'h1: palette_rgb = 24'hdd0033;
					4'h2: palette_rgb = 24'h000099;
					4'h3: palette_rgb = 24'hdd22dd;
					4'h4: palette_rgb = 24'h007722;
					4'h5: palette_rgb = 24'h555555;
					4'h6: palette_rgb = 24'h2222ff;
					4'h7: palette_rgb = 24'h66aaff;
					4'h8: palette_rgb = 24'h885500;
					4'h9: palette_rgb = 24'hff6600;
					4'ha: palette_rgb = 24'haaaaaa;
					4'hb: palette_rgb = 24'hff9988;
					4'hc: palette_rgb = 24'h11dd00;
					4'hd: palette_rgb = 24'hffff00;
					4'he: palette_rgb = 24'h44ff99;
					default: palette_rgb = 24'hffffff;
				endcase
			end
		end
	endfunction

	always_comb begin : address_generation
		logic [18:0] physical;
		logic [12:0] gfx_line;
		logic [14:0] gfx_page;
		logic [10:0] text_base;
		logic [6:0] char_slot;
		logic [2:0] char_i;
		logic [2:0] char_k;

		next_y = (v_count == 9'd261) ? 9'd0 : v_count + 1'b1;
		line_request = (h_count >= 10'd600) && (h_count < 10'd680);
		character_request = character_write && (v_count == 9'd261) &&
		                    (h_count >= 10'd700) && (h_count < 10'd764);
		request_index = line_request ? (h_count[6:0] - 7'd88) :
		                                (h_count[6:0] - 7'd60);
		physical = 19'h00000;
		gfx_line = 13'd0;
		gfx_page = 15'd0;
		text_base = 11'd0;
		char_slot = 7'd0;
		char_i = 3'd0;
		char_k = 3'd0;

		if (character_request) begin
			// Sixty-four screen-hole pairs describe arbitrary character rows.
			char_slot = h_count[6:0] - 7'd60;
			char_i = char_slot[5:3];
			char_k = char_slot[2:0];
			physical = {4'hf, 15'h0478 + {5'b00000, char_i, 7'b0000000} +
			                           {12'b000000000000, char_k}};
		end
		else if (line_request && (next_y < 9'd192)) begin
			if (!video_mode[3]) begin
				text_base = text_line_base(next_y[7:3]);
				physical = {4'hf, 4'b0000, text_base} +
				           ((request_index >= 7'd40) ? 19'h00400 : 19'h00000) +
				           ((request_index >= 7'd40) ?
				            {12'd0, request_index - 7'd40} : {12'd0, request_index});
			end
			else begin
				gfx_line = {2'b00, (text_line_base(next_y[7:3]) - 11'h400)} +
				           {next_y[2:0], 10'b0000000000};
				gfx_page = video_mode[2] ? 15'h4000 : 15'h0000;
				physical = {4'h0, gfx_page} + {6'b000000, gfx_line} +
				           ((request_index >= 7'd40) ? 19'h02000 : 19'h00000) +
				           ((request_index >= 7'd40) ?
				            {12'd0, request_index - 7'd40} : {12'd0, request_index});
			end
		end

		request_lane = physical[11];
		ram_addr = {physical[18:12], physical[10] ^ physical[11], physical[9:0]};
	end

	always_ff @(posedge clk) begin : prefetch_and_character_load
		request_valid_d     <= line_request || character_request;
		request_character_d <= character_request;
		request_lane_d      <= request_lane;
		request_index_d     <= request_index;

		if (request_valid_d) begin
			if (request_character_d) begin
				// Screen-hole low byte is bitmap; high byte is the character code.
				character_ram[{ram_q[14:8], request_index_d[4:3], request_index_d[2]}]
					<= ram_q[7:0];
			end
			else begin
				line_buffer[request_index_d] <= request_lane_d ? ram_q[15:8] : ram_q[7:0];
			end
		end

		if (reset) begin
			request_valid_d <= 1'b0;
			flash_count <= 6'd0;
		end
		else if (frame_tick) begin
			flash_count <= flash_count + 1'b1;
		end
	end

	always_comb begin : pixel_generation
		logic [23:0] rgb;
		logic [5:0] pair_index;
		logic [2:0] bit_index;

		rgb = 24'h000000;
		pair_index = 6'd0;
		bit_index = 3'd0;
		hblank = (h_count >= 10'd560);
		vblank = (v_count >= 9'd192);
		hsync = (h_count >= 10'd672) && (h_count < 10'd728);
		vsync = (v_count >= 9'd224) && (v_count < 9'd228);

		char_code = 8'h00;
		glyph = 8'h00;
		bitmap_byte = 8'h00;
		colour_byte = 8'h00;
		colour_index = 4'h0;
		graphics_palette = 1'b0;
		pixel_on = 1'b0;
		invert_pixel = 1'b0;
		char_position = 7'd0;
		byte_position = h_state[5:0];
		colour_position = h_state[5:1];
		within_28 = {h_state[0], state_dot};
		glyph_row = v_count[2:0] + (smooth_enable ? smooth_offset : 3'd0);
		glyph_column = state_dot[3:1];
		p1 = 8'h00; p2 = 8'h00; p3 = 8'h00; p4 = 8'h00;
		packed_140 = 28'h0000000;

		if (!hblank && !vblank && screen_enable) begin
			case ({video_mode[3], video_mode[1], video_mode[0]})
				3'b000, 3'b001: begin
					// 40-column text: the other half of the sister pair carries colour.
					char_code = line_buffer[(video_mode[2] ? 7'd40 : 7'd0) + h_state];
					colour_byte = line_buffer[(video_mode[2] ? 7'd0 : 7'd40) + h_state];
					glyph = character_ram[{char_code[6:0], glyph_row}];
					pixel_on = glyph[glyph_column];
					invert_pixel = !char_code[7] && (!glyph[7] || flash_count[3]);
					pixel_on = pixel_on ^ invert_pixel;
					if (video_mode[0] && native_mode) begin
						colour_index = pixel_on ? colour_byte[7:4] : colour_byte[3:0];
					end
					else begin
						colour_index = pixel_on ? 4'hf : 4'h0;
					end
				end

				3'b010, 3'b011: begin
					// 80-column text: page select exchanges the two 40-byte halves.
					char_position = {h_state[5:0], 1'b0} + (state_dot >= 4'd7);
					pair_index = char_position[6:1];
					char_code = line_buffer[
						((char_position[0] ^ video_mode[2]) ? 7'd40 : 7'd0) + pair_index];
					glyph_column = (state_dot >= 4'd7) ?
					               state_dot[2:0] + 1'b1 : state_dot[2:0];
					glyph = character_ram[{char_code[6:0], glyph_row}];
					pixel_on = glyph[glyph_column];
					invert_pixel = !char_code[7] && (!glyph[7] || flash_count[3]);
					pixel_on = pixel_on ^ invert_pixel;
					colour_index = pixel_on ? 4'hc : 4'h0;
				end

				3'b100: begin
					bitmap_byte = line_buffer[{1'b0, byte_position}];
					bit_index = state_dot[3:1];
					colour_index = bitmap_byte[bit_index] ? 4'hf : 4'h0;
				end

				3'b101: begin
					bitmap_byte = line_buffer[{1'b0, byte_position}];
					colour_byte = line_buffer[7'd40 + {1'b0, byte_position}];
					bit_index = state_dot[3:1];
					colour_index = bitmap_byte[bit_index] ? colour_byte[7:4] : colour_byte[3:0];
					graphics_palette = 1'b1;
				end

				3'b110: begin
					if (state_dot < 4'd7) begin
						bitmap_byte = line_buffer[{1'b0, byte_position}];
						bit_index = state_dot[2:0];
					end
					else begin
						bitmap_byte = line_buffer[7'd40 + {1'b0, byte_position}];
						bit_index = state_dot[2:0] + 1'b1;
					end
					colour_index = bitmap_byte[bit_index] ? 4'hf : 4'h0;
				end

				default: begin
					p1 = line_buffer[{1'b0, colour_position, 1'b0}];
					p2 = line_buffer[7'd40 + {1'b0, colour_position, 1'b0}];
					p3 = line_buffer[{1'b0, colour_position, 1'b0} + 7'd1];
					p4 = line_buffer[7'd40 + {1'b0, colour_position, 1'b0} + 7'd1];
					packed_140 = {p4[6:0], p3[6:0], p2[6:0], p1[6:0]};
					case (within_28[4:2])
						3'd0: colour_index = packed_140[3:0];
						3'd1: colour_index = packed_140[7:4];
						3'd2: colour_index = packed_140[11:8];
						3'd3: colour_index = packed_140[15:12];
						3'd4: colour_index = packed_140[19:16];
						3'd5: colour_index = packed_140[23:20];
						default: colour_index = packed_140[27:24];
					endcase
					graphics_palette = 1'b1;
				end
			endcase
		end

		rgb = palette_rgb(colour_index, graphics_palette);
		red   = rgb[23:16];
		green = rgb[15:8];
		blue  = rgb[7:0];
	end

endmodule
