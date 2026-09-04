// Apple /// motherboard I/O page ($C000-$C0ff).
//
// Decode and polarity are taken primarily from the Level 2 Service Reference
// Manual and schematics, with SOS/ROM/console sources used to check software
// expectations.  MAME is only a secondary behavioral cross-check.

module apple3_io (
	input  logic        clk,
	input  logic        reset,
	input  logic        cycle_strobe,
	input  logic        select,
	input  logic        cpu_read,
	input  logic [7:0]  addr,
	input  logic [4:0]  rtc_register,

	input  logic [7:0]  key_code,
	input  logic        key_strobe,
	input  logic        any_key_down,
	input  logic        shift,
	input  logic        control_key,
	input  logic        alpha_lock,
	input  logic        open_apple,
	input  logic        solid_apple,
	output logic        clear_key_strobe,

	input  logic [7:0]  joy_a_x,
	input  logic [7:0]  joy_a_y,
	input  logic [7:0]  joy_b_x,
	input  logic [7:0]  joy_b_y,
	input  logic [3:0]  joy_buttons,
	input  logic        slot1_irq_n,
	input  logic        slot2_irq_n,

	input  logic [7:0]  rtc_data,
	input  logic [7:0]  disk_data,
	input  logic [7:0]  acia_data,
	output logic        rtc_read,
	output logic        rtc_write,
	output logic [4:0]  rtc_addr,
	output logic        disk_strobe,
	output logic        acia_read,
	output logic        acia_write,

	output logic [7:0]  data_out,
	output logic [3:0]  video_mode,
	output logic        smooth_scroll,
	output logic        character_write,
	output logic        external_select,
	output logic        serial_enable,
	output logic [2:0]  analog_select,
	output logic        speaker
);

	localparam logic [12:0] BELL_HALF_PERIOD = 13'd7159;
	localparam logic [23:0] BELL_DURATION = 24'd1431818;

	logic [11:0] paddle_charge;
	logic [11:0] paddle_target;
	logic [3:0]  paddle_divider;
	logic        paddle_active;
	logic [23:0] bell_count;
	logic [12:0] bell_divider;
	logic [7:0]  selected_paddle;

	always_comb begin
		case (analog_select)
			3'b000: selected_paddle = 8'h00; // ground/reference diagnostic
			3'b001: selected_paddle = joy_b_x;
			3'b010: selected_paddle = 8'hff - joy_b_y;
			3'b011: selected_paddle = joy_a_x;
			3'b100: selected_paddle = 8'hff - joy_a_y;
			3'b101: selected_paddle = 8'hc0; // nominal clock-battery channel
			default: selected_paddle = 8'hff; // open and full-scale reference
		endcase

		data_out = 8'hff;
		if (select) begin
			casez (addr)
				8'b00000???: data_out = {key_strobe, key_code[6:0]};
				8'b00001???: data_out = {key_code[7], 1'b1, !solid_apple,
				                               !open_apple, !alpha_lock, !control_key,
				                               !shift, any_key_down};
				8'h60, 8'h68: data_out = {joy_buttons[0], 7'h00};
				8'h61, 8'h69: data_out = {joy_buttons[2], 7'h00};
				8'h62, 8'h6a: data_out = {joy_buttons[1], 7'h00};
				8'h63, 8'h6b: data_out = {joy_buttons[3], 7'h00};
				8'h64, 8'h6c: data_out = {slot2_irq_n, 7'h00};
				8'h65, 8'h6d: data_out = {slot1_irq_n, 7'h00};
				8'h66, 8'h6e: data_out = {paddle_active, 7'h00};
				8'h70, 8'h71, 8'h72, 8'h73,
				8'h74, 8'h75, 8'h76, 8'h77,
				8'h78, 8'h79, 8'h7a, 8'h7b,
				8'h7c, 8'h7d, 8'h7e, 8'h7f: data_out = rtc_data;
				8'hd0, 8'hd1, 8'hd2, 8'hd3,
				8'hd4, 8'hd5, 8'hd6, 8'hd7: data_out = 8'h00;
				8'he0, 8'he1, 8'he2, 8'he3,
				8'he4, 8'he5, 8'he6, 8'he7,
				8'he8, 8'he9, 8'hea, 8'heb,
				8'hec, 8'hed, 8'hee, 8'hef: data_out = disk_data;
				8'hf0, 8'hf1, 8'hf2, 8'hf3: data_out = acia_data;
				default: ;
			endcase
		end

		rtc_addr = rtc_register;
		rtc_read = cycle_strobe && select && cpu_read && (addr[7:4] == 4'h7);
		rtc_write = cycle_strobe && select && !cpu_read && (addr[7:4] == 4'h7);
		disk_strobe = cycle_strobe && select &&
		              ((addr[7:4] == 4'hd) || (addr[7:4] == 4'he));
		acia_read = cycle_strobe && select && cpu_read &&
		             (addr >= 8'hf0) && (addr <= 8'hf3);
		acia_write = cycle_strobe && select && !cpu_read &&
		              (addr >= 8'hf0) && (addr <= 8'hf3);
	end

	always_ff @(posedge clk) begin
		clear_key_strobe <= 1'b0;
		if (reset) begin
			video_mode <= 4'h0;
			smooth_scroll <= 1'b0;
			character_write <= 1'b0;
			external_select <= 1'b0;
			serial_enable <= 1'b0;
			analog_select <= 3'b000;
			paddle_charge <= 12'd0;
			paddle_target <= 12'd0;
			paddle_divider <= 4'd0;
			paddle_active <= 1'b0;
			bell_count <= 24'd0;
			bell_divider <= 13'd0;
			speaker <= 1'b0;
		end
		else begin
			if (paddle_divider == 4'd14) begin
				paddle_divider <= 4'd0;
				if (paddle_active) begin
					if (paddle_target != 0) paddle_target <= paddle_target - 1'b1;
					else paddle_active <= 1'b0;
				end
				else if (paddle_charge != 12'hfff) begin
					paddle_charge <= paddle_charge + 1'b1;
				end
			end
			else paddle_divider <= paddle_divider + 1'b1;

			if (bell_count != 0) begin
				bell_count <= bell_count - 1'b1;
				if (bell_divider == BELL_HALF_PERIOD - 1) begin
					bell_divider <= 13'd0;
					speaker <= !speaker;
				end
				else bell_divider <= bell_divider + 1'b1;
			end

			if (cycle_strobe && select) begin
				casez (addr)
					8'b0001????: clear_key_strobe <= 1'b1;
					8'b0011????: speaker <= !speaker;
					8'h40, 8'h41, 8'h42, 8'h43,
					8'h44, 8'h45, 8'h46, 8'h47,
					8'h48, 8'h49, 8'h4a, 8'h4b,
					8'h4c, 8'h4d: begin
						bell_count <= BELL_DURATION;
						bell_divider <= 13'd0;
					end
					8'h50, 8'h51, 8'h52, 8'h53,
					8'h54, 8'h55, 8'h56, 8'h57:
						video_mode[addr[2:1]] <= addr[0];
					8'h58, 8'h59: analog_select[0] <= addr[0];
					8'h5a, 8'h5b: analog_select[2] <= addr[0];
					8'h5c: begin
						paddle_active <= 1'b0;
						paddle_charge <= 12'd0;
					end
					8'h5d: begin
						// A complete CPU polling loop takes roughly the same time as
						// seven of the 15-clock divider ticks.  This makes Y track the
						// selected 8-bit channel while channel 0 (ground), used by the
						// power-on diagnostic, times out immediately.
						paddle_target <= {4'd0, selected_paddle} * 4'd7;
						paddle_active <= (selected_paddle != 8'h00);
					end
					8'h5e, 8'h5f: analog_select[1] <= addr[0];
					8'hd8, 8'hd9: smooth_scroll <= addr[0];
					8'hda, 8'hdb: character_write <= addr[0];
					8'hdc, 8'hdd: external_select <= addr[0];
					8'hde, 8'hdf: serial_enable <= addr[0];
					default: ;
				endcase
			end
		end
	end

endmodule
