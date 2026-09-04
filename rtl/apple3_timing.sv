// Apple /// master timing and memory-slot arbitration.
//
// The counters follow the Level 2 Service Reference Manual and the decoded
// 342-0030/342-0046 PROMs: 64 ordinary 14-dot states plus one 16-dot state,
// 262 lines, and one guaranteed CPU slot per state.  In fast mode the CPU may
// also use the video/refresh slot when neither consumer needs RAM.

module apple3_timing (
	input  logic        clk_14m,
	input  logic        reset,
	input  logic        slow_mode,
	input  logic        screen_enable,
	input  logic        peripheral_cycle,

	output logic        cpu_enable,
	output logic        via_rising,
	output logic        via_falling,
	output logic        pixel_enable,
	output logic        hblank,
	output logic        vblank,
	output logic        display_slot,
	output logic        refresh_slot,
	output logic [9:0]  h_count,
	output logic [8:0]  v_count,
	output logic [6:0]  h_state,
	output logic [3:0]  state_dot,
	output logic        frame_tick
);

	logic [4:0] state_length;
	logic       fast_a_slot;

	always_comb begin
		state_length = (h_state == 7'd64) ? 5'd16 : 5'd14;
		hblank       = (h_count >= 10'd560);
		vblank       = (v_count >= 9'd192);
		pixel_enable = 1'b1;

		// Four consecutive refresh states in each 32-state half-line.  The
		// otherwise special state 64 is not one of the decoded refresh groups.
		refresh_slot = (h_state < 7'd64) &&
		               (h_state[4:2] == v_count[2:0]);
		display_slot = screen_enable && !vblank && (h_state < 7'd40);
		fast_a_slot  = !slow_mode && !peripheral_cycle &&
		               !display_slot && !refresh_slot;

		// Dot 6 is the optional A slot and dot 13 is the guaranteed B slot.
		// Peripheral accesses run on the 1 MHz slot and are never doubled.
		cpu_enable = (state_dot == 4'd13) ||
		             ((state_dot == 4'd6) && fast_a_slot);
		via_rising  = (state_dot == 4'd0);
		via_falling = (state_dot == 4'd7);
	end

	always_ff @(posedge clk_14m) begin
		frame_tick <= 1'b0;
		if (reset) begin
			h_count   <= 10'd0;
			v_count   <= 9'd0;
			h_state   <= 7'd0;
			state_dot <= 4'd0;
		end
		else if (state_dot == state_length - 1'b1) begin
			state_dot <= 4'd0;
			if (h_state == 7'd64) begin
				h_state <= 7'd0;
				h_count <= 10'd0;
				if (v_count == 9'd261) begin
					v_count    <= 9'd0;
					frame_tick <= 1'b1;
				end
				else begin
					v_count <= v_count + 1'b1;
				end
			end
			else begin
				h_state <= h_state + 1'b1;
				h_count <= h_count + 1'b1;
			end
		end
		else begin
			state_dot <= state_dot + 1'b1;
			h_count   <= h_count + 1'b1;
		end
	end

endmodule
