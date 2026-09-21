// Apple /// video outputs and the monitor on each of them.
//
// Sheet 6 of the schematic makes three pictures from the colour lines
// RGB8..RGB1.  The XRGB pins carry them to an RGB monitor as they are.  The
// B/W jack sums them through the ladder RP4, so a colour is a shade of grey.
// The NTSC pin sums them with equal weight through RP3 and adds NTSCA and
// NTSCB, which the L8 multiplexer picks from the same four lines in step with
// the subcarrier; its hue is therefore the colour number's bit pattern, as in
// an Apple II's low resolution, and a serial bitmap makes Apple II artifact
// colour by the same route.
//
// `source` selects the monitor: 0 RGB, 1 colour composite, 2 monochrome
// composite.  All three leave here four dots after they arrive, with blanking
// and sync to match, so the picture does not move when the source changes.
//
// `green_phosphor` makes the monochrome monitor a Monitor ///, whose P31 tube
// shows the B/W signal's grey levels in green.  It is a presentation of that
// signal alone: the RGB and NTSC pictures are as the motherboard sends them.

module apple3_composite (
	input logic       clk,
	input logic [1:0] source,
	input logic       green_phosphor,

	input logic [ 3:0] colour,
	input logic [ 1:0] colour_phase,
	input logic        colour_burst,
	input logic [23:0] rgb_in,
	input logic        hblank_in,
	input logic        vblank_in,
	input logic        hsync_in,
	input logic        vsync_in,

	output logic [7:0] red,
	output logic [7:0] green,
	output logic [7:0] blue,
	output logic       hblank,
	output logic       vblank,
	output logic       hsync,
	output logic       vsync
);

	// RP3: 6.2K from each colour line and 5.1K from NTSCA and NTSCB, so a
	// chroma line weighs 62 where a colour line weighs 51.  NTSCA is line k of
	// RGB1, RGB2, RGB4, RGB8 in slot k and NTSCB the inverse of line k + 2.
	// Their sum rests at one chroma weight, taken here as the black level.
	function automatic signed [9:0] ntsc_level(input logic [3:0] lines, input logic [1:0] slot);
		logic [2:0] lit;
		begin
			lit = {2'b00, lines[0]} + {2'b00, lines[1]} + {2'b00, lines[2]} + {2'b00, lines[3]};
			ntsc_level = $signed({2'b00, 8'd51 * lit}) + (lines[slot] ? 10'sd62 : 10'sd0) -
				(lines[slot^2'd2] ? 10'sd62 : 10'sd0);
		end
	endfunction

	// RP4: 18K, 9.1K, 4.3K and 1.8K from RGB1, RGB2, RGB4 and RGB8.  The
	// conductances are scaled so that white is 255.
	function automatic [7:0] grey_level(input logic [3:0] lines);
		grey_level = (lines[0] ? 8'd15 : 8'd0) + (lines[1] ? 8'd29 : 8'd0) + (lines[2] ? 8'd62 : 8'd0) +
			(lines[3] ? 8'd149 : 8'd0);
	endfunction

	// A phosphor's picture is the grey level times its colour at full drive.
	localparam logic [23:0] P31_GREEN = 24'h11dd00;

	function automatic [7:0] scaled(input logic [7:0] level, input logic [7:0] full);
		logic [16:0] product;
		begin
			// level * full / 255, to the nearest step.
			product = {9'd0, level} * {9'd0, full} + 17'd127;
			scaled  = 8'((product + 17'd1 + (product >> 8)) >> 8);
		end
	endfunction

	function automatic [23:0] phosphor(input logic [7:0] level, input logic [23:0] full);
		phosphor = {scaled(level, full[23:16]), scaled(level, full[15:8]), scaled(level, full[7:0])};
	endfunction

	function automatic [7:0] clip(input logic signed [17:0] value);
		if (value < 0) clip = 8'd0;
		else if (value > 18'sd255) clip = 8'd255;
		else clip = value[7:0];
	endfunction

	// sample[i] is the composite level i + 1 dots ago, and sample_phase the
	// slot of sample[0].
	logic signed [ 9:0] sample       [4];
	logic        [ 1:0] sample_phase;
	logic        [ 7:0] grey         [3];
	logic        [23:0] rgb          [3];
	logic        [ 3:0] timing       [3];
	logic               hsync_q;

	// A colour monitor decodes chroma only on lines that carried a burst; K8
	// gates it with -COLRKL.  Without one it shows the whole signal as luma.
	logic burst_seen;

	logic signed [11:0] luma_sum;
	logic signed [10:0] red_axis, blue_axis;
	logic signed [9:0] luma_direct;

	always_ff @(posedge clk) begin
		sample[0]    <= ntsc_level(colour, colour_phase);
		sample[1]    <= sample[0];
		sample[2]    <= sample[1];
		sample[3]    <= sample[2];
		sample_phase <= colour_phase;

		grey[0]   <= grey_level(colour);
		rgb[0]    <= rgb_in;
		timing[0] <= {hblank_in, vblank_in, hsync_in, vsync_in};
		for (int i = 1; i < 3; i++) begin
			grey[i]   <= grey[i-1];
			rgb[i]    <= rgb[i-1];
			timing[i] <= timing[i-1];
		end

		// The burst follows the sync pulse with no breezeway.
		hsync_q <= hsync_in;
		if (hsync_q && !hsync_in) burst_seen <= colour_burst;

		// Four dots are one subcarrier cycle.  Their mean is luma; slot 0
		// less slot 2 lies on the R-Y axis and slot 1 less slot 3 on B-Y,
		// which puts colours 1, 2, 4 and 8 at magenta, dark blue, dark green
		// and brown, the names the Owner's Guide gives them.
		luma_sum    <= 12'(sample[0]) + 12'(sample[1]) + 12'(sample[2]) + 12'(sample[3]);
		red_axis    <= sample[sample_phase] - sample[sample_phase^2'd2];
		blue_axis   <= sample[sample_phase-2'd1] - sample[sample_phase+2'd1];
		luma_direct <= sample[1];

		{hblank, vblank, hsync, vsync} <= timing[2];
		case (source)
			2'd1: begin
				if (burst_seen) begin
					// White is a sum of 816, so 40/128 of it is 255.  The
					// chroma gains are the NTSC matrix at 0.8 saturation.
					red   <= clip((18'sd40 * luma_sum + 18'sd73 * red_axis) >>> 7);
					green <= clip((18'sd40 * luma_sum - 18'sd37 * red_axis - 18'sd25 * blue_axis) >>> 7);
					blue  <= clip((18'sd40 * luma_sum + 18'sd130 * blue_axis) >>> 7);
				end else begin
					red   <= clip((18'sd5 * luma_direct) >>> 2);
					green <= clip((18'sd5 * luma_direct) >>> 2);
					blue  <= clip((18'sd5 * luma_direct) >>> 2);
				end
			end
			2'd2:    {red, green, blue} <= green_phosphor ? phosphor(grey[2], P31_GREEN) : {3{grey[2]}};
			default: {red, green, blue} <= rgb[2];
		endcase
	end

endmodule
