// Apple /// motherboard I/O page ($C000-$C0ff).
//
// Decode and polarity are taken primarily from the Level 2 Service Reference
// Manual and schematics, with SOS/ROM/console sources used to check software
// expectations.  MAME is only a secondary behavioral cross-check.

module apple3_io (
	input logic       clk,
	input logic       reset,
	input logic       cycle_strobe,
	input logic       select,
	input logic       cpu_read,
	input logic [7:0] addr,
	input logic [4:0] rtc_register,

	input  logic [7:0] key_code,
	input  logic       key_strobe,
	input  logic       any_key_down,
	input  logic       shift,
	input  logic       control_key,
	input  logic       alpha_lock,
	input  logic       open_apple,
	input  logic       solid_apple,
	output logic       clear_key_strobe,

	// Joystick ports A (J3) and B (J2).  Positions read 0 at the left or bottom
	// and 255 at the right or top; a closed button or switch is 1.
	input logic [7:0] joy_a_x,
	input logic [7:0] joy_a_y,
	input logic [7:0] joy_b_x,
	input logic [7:0] joy_b_y,
	input logic       joy_a_button,
	input logic       joy_a_switch,
	input logic       joy_b_button,
	input logic       joy_b_switch,
	// The D VIA's CB1 and CB2 pins when it drives them: the Silentype clock
	// and data share port A's switch and X input.
	input logic       via_cb1_drive,
	input logic       via_cb1_out,
	input logic       via_cb2_drive,
	input logic       via_cb2_out,
	input logic       slot1_irq_n,
	input logic       slot2_irq_n,

	input  logic [7:0] rtc_data,
	input  logic [7:0] disk_data,
	input  logic [7:0] acia_data,
	output logic       rtc_read,
	output logic       rtc_write,
	output logic [4:0] rtc_addr,
	output logic       disk_strobe,
	output logic       acia_read,
	output logic       acia_write,

	output logic [7:0] data_out,
	output logic [3:0] video_mode,
	output logic       smooth_scroll,
	output logic       character_write,
	output logic       external_select,
	output logic       serial_enable,
	output logic [2:0] analog_select,
	output logic       margin_switch,
	output logic       serial_clock,
	output logic       speaker
);

	localparam logic [12:0] BELL_HALF_PERIOD = 13'd7159;
	localparam logic [23:0] BELL_DURATION    = 24'd1431818;

	// The A/D converter is a 9708 (M9, sheet 8 of 050-0039-H), the part Fujitsu
	// second-sourced as the MB4053.  PDLEN drives its RAMP START input.  $C05C
	// takes it low: the selected input charges the ramp capacitor, C15, to the
	// input voltage plus a diode offset.  $C05D takes it high: the input is
	// disconnected and a constant current discharges C15.  RAMP STOP, PDLOT at
	// $C066 bit 7, is high whenever C15 is above the comparator threshold, so it
	// rises early in the charge and falls when the ramp reaches the threshold,
	// after a time proportional to the input voltage.
	//
	// ramp_level is C15 above that threshold, in master clocks of discharge. R39
	// sets the discharge current to (12 V - VREF) / 1.2 Mohm = 8.11 uA, so C15's
	// 0.01 uF falls 0.811 V/ms and one volt lasts 17,648 clocks.  VREF is R37 and
	// R38 dividing +12 V: 2.264 V, the full scale of the reference channel.  The
	// data sheet's acquisition current of at least 150 uA charges the capacitor
	// about twenty times as fast as it discharges, within the 500 us that the
	// Service Reference Manual allows.  The zero offset and the level a finished
	// discharge settles at are nominal: a ground conversion lasts about 30 us,
	// and a discharged C15 needs about 28 us of charge to cross the threshold.
	localparam logic signed [17:0] RAMP_FLOOR     = -18'sd7942;
	localparam logic signed [17:0] RAMP_GROUND    = 18'sd430;
	localparam logic signed [17:0] RAMP_REFERENCE = RAMP_GROUND + 18'sd39959;
	// The input range ends at VCC - 2 V.  An unconnected input floats up to that
	// limit, and so does the clock's battery of three AA cells.
	localparam logic signed [17:0] RAMP_CLAMP     = RAMP_GROUND + 18'sd52944;
	localparam logic signed [17:0] RAMP_CHARGE    = 18'sd20;
	// A joystick spans SOS 1.3's reading window.  GET_ANALOG times the ramp
	// with the D VIA's timer 2 from a few ticks after the start: it skips 360
	// ticks and counts 8 per step, 112.25 clocks.  Its polling loop ends up to
	// six ticks late, so a ramp of 354 + 8p ticks reads p from 0 to 255 with
	// under a tick of margin either side (sim/joystick measures it).  The
	// emulation disk's PREAD samples later and reads one or two steps lower.
	// As voltages the travel is 0.26 V to 1.88 V.
	localparam logic signed [17:0] STICK_BASE     = 18'sd4966;

	logic               ramp_start;
	logic signed [17:0] ramp_level = RAMP_FLOOR;
	logic signed [17:0] ramp_input;
	logic               ramp_stop;
	logic               serial_data;
	logic        [23:0] bell_count;
	logic        [12:0] bell_divider;

	function automatic logic signed [17:0] stick_level(input logic [7:0] position);
		stick_level = STICK_BASE + $signed({3'd0, position, 7'd0}) - $signed({6'd0, position, 4'd0}) +
			$signed({12'd0, position[7:2]});
	endfunction

	always_comb begin
		// Port A doubles as the Silentype port.  ENSIO sends the VIA's serial data
		// out on X1/SER and ENSEL sends AXCO out on Y1/XCO; a pin the VIA does not
		// drive floats high.  AXCO is low whenever port A's Y channel is selected.
		serial_data = !via_cb2_drive || via_cb2_out;
		case (analog_select)
			3'd0:       ramp_input = RAMP_GROUND;
			3'd1:       ramp_input = stick_level(joy_b_x);
			3'd2:       ramp_input = stick_level(joy_b_y);
			3'd3:       ramp_input = serial_enable ? (serial_data ? RAMP_CLAMP : RAMP_GROUND) : stick_level(joy_a_x);
			3'd4:       ramp_input = external_select ? RAMP_GROUND : stick_level(joy_a_y);
			3'd5, 3'd6: ramp_input = RAMP_CLAMP;
			default:    ramp_input = RAMP_REFERENCE;
		endcase
		ramp_stop = ramp_level > 18'sd0;

		// SW1/MGNSW is the D VIA's CA2 and SW3/SCO its CB1.  With ENSEL set the
		// port's switch is cut off from SW3/SCO, which the VIA's shift clock
		// drives when it is an output and otherwise floats high.
		margin_switch = joy_a_button;
		serial_clock  = via_cb1_drive ? via_cb1_out : (external_select || joy_a_switch);

		data_out = 8'hff;
		if (select) begin
			casez (addr)
				8'b00000???: data_out = {key_strobe, key_code[6:0]};
				// KB port: bit 7 = key code bit 7, bit 6 = 1 (mode committed),
				// bits 5..2 are active-low switch inputs, bit 1 is active-HIGH
				// shift (the SOS console driver's EOR #$3C flips bits 5..2 only and
				// MAME's model agrees), bit 0 = any key down.
				8'b00001???:
				data_out = {
					key_code[7], 1'b1, !solid_apple, !open_apple, !alpha_lock, !control_key, shift, any_key_down
				};
				// The 74LS251 at L7: SW0 and SW2 are port B's switch and button,
				// SW1 and SW3 port A's button and switch.
				8'h60, 8'h68: data_out = {joy_b_switch, 7'h00};
				8'h61, 8'h69: data_out = {margin_switch, 7'h00};
				8'h62, 8'h6a: data_out = {joy_b_button, 7'h00};
				8'h63, 8'h6b: data_out = {serial_clock, 7'h00};
				8'h64, 8'h6c: data_out = {slot2_irq_n, 7'h00};
				8'h65, 8'h6d: data_out = {slot1_irq_n, 7'h00};
				8'h66, 8'h6e: data_out = {ramp_stop, 7'h00};
				8'h70, 8'h71, 8'h72, 8'h73,
				8'h74, 8'h75, 8'h76, 8'h77,
				8'h78, 8'h79, 8'h7a, 8'h7b,
				8'h7c, 8'h7d, 8'h7e, 8'h7f:
				data_out = rtc_data;
				8'hd0, 8'hd1, 8'hd2, 8'hd3, 8'hd4, 8'hd5, 8'hd6, 8'hd7: data_out = 8'h00;
				8'he0, 8'he1, 8'he2, 8'he3,
				8'he4, 8'he5, 8'he6, 8'he7,
				8'he8, 8'he9, 8'hea, 8'heb,
				8'hec, 8'hed, 8'hee, 8'hef:
				data_out = disk_data;
				// SRM figure 2.30: FX strobes the ACIA, which decodes A0-A1, so
				// $C0F4-$C0FF are mirrors of its four registers.
				8'hf0, 8'hf1, 8'hf2, 8'hf3,
				8'hf4, 8'hf5, 8'hf6, 8'hf7,
				8'hf8, 8'hf9, 8'hfa, 8'hfb,
				8'hfc, 8'hfd, 8'hfe, 8'hff:
				data_out = acia_data;
				default: ;
			endcase
		end

		rtc_addr    = rtc_register;
		rtc_read    = cycle_strobe && select && cpu_read && (addr[7:4] == 4'h7);
		rtc_write   = cycle_strobe && select && !cpu_read && (addr[7:4] == 4'h7);
		disk_strobe = cycle_strobe && select && ((addr[7:4] == 4'hd) || (addr[7:4] == 4'he));
		acia_read   = cycle_strobe && select && cpu_read && (addr[7:4] == 4'hf);
		acia_write  = cycle_strobe && select && !cpu_read && (addr[7:4] == 4'hf);
	end

	// Reset does not touch C15.  While PDLEN is low the acquisition current
	// raises C15 to the input quickly, but only the discharge current lowers it,
	// so a lower input takes as long to settle as a ramp would.
	always_ff @(posedge clk) begin
		if (ramp_start) begin
			if (ramp_level > RAMP_FLOOR) ramp_level <= ramp_level - 18'sd1;
		end else if (ramp_level < ramp_input) begin
			ramp_level <= (ramp_input - ramp_level > RAMP_CHARGE) ? ramp_level + RAMP_CHARGE : ramp_input;
		end else if (ramp_level > ramp_input) begin
			ramp_level <= ramp_level - 18'sd1;
		end
	end

	always_ff @(posedge clk) begin
		clear_key_strobe <= 1'b0;
		if (reset) begin
			// Reset clears the 9334 addressable latches, PDLEN included.
			video_mode      <= 4'h0;
			smooth_scroll   <= 1'b0;
			character_write <= 1'b0;
			external_select <= 1'b0;
			serial_enable   <= 1'b0;
			analog_select   <= 3'b000;
			ramp_start      <= 1'b0;
			bell_count      <= 24'd0;
			bell_divider    <= 13'd0;
			speaker         <= 1'b0;
		end else begin
			if (bell_count != 0) begin
				bell_count <= bell_count - 1'b1;
				if (bell_divider == BELL_HALF_PERIOD - 1) begin
					bell_divider <= 13'd0;
					speaker      <= !speaker;
				end else bell_divider <= bell_divider + 1'b1;
			end

			if (cycle_strobe && select) begin
				casez (addr)
					8'b0001????:                                            clear_key_strobe <= 1'b1;
					8'b0011????:                                            speaker <= !speaker;
					8'h40, 8'h41, 8'h42, 8'h43,
					8'h44, 8'h45, 8'h46, 8'h47,
					8'h48, 8'h49, 8'h4a, 8'h4b,
					8'h4c, 8'h4d: begin
						bell_count   <= BELL_DURATION;
						bell_divider <= 13'd0;
					end
					8'h50, 8'h51, 8'h52, 8'h53, 8'h54, 8'h55, 8'h56, 8'h57: video_mode[addr[2:1]] <= addr[0];
					8'h58, 8'h59:                                           analog_select[0] <= addr[0];
					8'h5a, 8'h5b:                                           analog_select[2] <= addr[0];
					8'h5c, 8'h5d:                                           ramp_start <= addr[0];
					8'h5e, 8'h5f:                                           analog_select[1] <= addr[0];
					8'hd8, 8'hd9:                                           smooth_scroll <= addr[0];
					8'hda, 8'hdb:                                           character_write <= addr[0];
					8'hdc, 8'hdd:                                           external_select <= addr[0];
					8'hde, 8'hdf:                                           serial_enable <= addr[0];
					default:                                                ;
				endcase
			end
		end
	end

endmodule
