// Apple /// integrated floppy controller.
//
// The shift/stepper portion reuses the proven MiSTer Disk II drive model, but
// the surrounding latch decode is Apple /// specific.  In native mode $C0Dx
// selects internal/external drives and side, while $C0Ex controls phases,
// motor, internal/external I/O, Q6, and Q7.  SOS 1.3's DISK3 driver and the
// 341-0028 state-machine PROM are used alongside the service schematics.

module apple3_disk (
	input  logic        clk_14m,
	input  logic        clk_2m,
	input  logic        phase_zero,
	input  logic        reset,
	input  logic        select,
	input  logic        cycle_strobe,
	input  logic        cpu_read,
	input  logic [7:0]  addr,
	input  logic [7:0]  data_in,
	input  logic [1:0]  disk_ready,
	input  logic [1:0]  write_protect,
	output logic [7:0]  data_out,

	output logic [3:0]  motor_phase,
	output logic        side_two,
	output logic        d1_active,
	output logic        d2_active,
	output logic        d1_motor_on,
	output logic        d2_motor_on,
	output logic        d1_io_active,
	output logic        d2_io_active,
	output logic        d1_track_zero_step,
	output logic        d2_track_zero_step,

	output logic [5:0]  track1,
	output logic [12:0] track1_addr,
	output logic [7:0]  track1_din,
	input  logic [7:0]  track1_dout,
	output logic        track1_we,
	input  logic        track1_busy,
	output logic [5:0]  track2,
	output logic [12:0] track2_addr,
	output logic [7:0]  track2_din,
	input  logic [7:0]  track2_dout,
	output logic        track2_we,
	input  logic        track2_busy
);

	logic [1:0] external_drive;
	logic       internal_enable;
	logic       external_io;
	logic       motor_on;
	logic       motor_real_on;
	logic       q6;
	logic       q7;
	logic       selected_internal;
	logic       selected_external;
	logic       read_disk;
	logic       write_register;
	logic [7:0] drive1_data;
	logic [7:0] drive2_data;
	logic [23:0] spindown_count;

	always_comb begin
		read_disk = select && (addr == 8'hec);
		write_register = select && !cpu_read && q7 &&
		                 ((addr == 8'hed) || (addr == 8'hef));

		selected_internal = !external_io && internal_enable;
		// The implemented external connector is D2.  D3/D4 selection remains
		// faithfully latched and simply produces no ready drive.
		selected_external = external_io && (external_drive == 2'b01);
		d1_active = motor_real_on && selected_internal;
		d2_active = motor_real_on && selected_external;
		d1_motor_on = motor_on && selected_internal;
		d2_motor_on = motor_on && selected_external;
		d1_io_active = read_disk && d1_active && disk_ready[0];
		d2_io_active = read_disk && d2_active && disk_ready[1];

		if (addr[0]) data_out = 8'hff;
		else if (q6) begin
			if (selected_external) data_out = {write_protect[1], 7'h00};
			else data_out = {write_protect[0], 7'h00};
		end
		else if (selected_external) data_out = drive2_data;
		else data_out = drive1_data;
	end

	always_ff @(posedge clk_14m) begin
		if (reset) begin
			motor_phase <= 4'h0;
			external_drive <= 2'b00;
			internal_enable <= 1'b1;
			side_two <= 1'b0;
			external_io <= 1'b0;
			motor_on <= 1'b0;
			motor_real_on <= 1'b0;
			spindown_count <= 24'd0;
			q6 <= 1'b0;
			q7 <= 1'b0;
		end
		else begin
			if (motor_on) begin
				motor_real_on <= 1'b1;
				spindown_count <= 24'd0;
			end
			else if (motor_real_on) begin
				if (spindown_count == 0) spindown_count <= 24'd14318180;
				else if (spindown_count == 1) begin
					spindown_count <= 24'd0;
					motor_real_on <= 1'b0;
				end
				else spindown_count <= spindown_count - 1'b1;
			end

			if (cycle_strobe && select) begin
				case (addr)
					8'hd0, 8'hd1: external_drive[0] <= addr[0];
					8'hd2, 8'hd3: external_drive[1] <= addr[0];
					// The latch is active low: D4 selects, D5 deselects D1.
					8'hd4, 8'hd5: internal_enable <= !addr[0];
					8'hd6, 8'hd7: side_two <= addr[0];
					8'he0, 8'he1: motor_phase[0] <= addr[0];
					8'he2, 8'he3: motor_phase[1] <= addr[0];
					8'he4, 8'he5: motor_phase[2] <= addr[0];
					8'he6, 8'he7: motor_phase[3] <= addr[0];
					8'he8, 8'he9: motor_on <= addr[0];
					8'hea, 8'heb: external_io <= addr[0];
					8'hec, 8'hed: q6 <= addr[0];
					8'hee, 8'hef: q7 <= addr[0];
					default: ;
				endcase
			end
		end
	end

	drive_ii drive1 (
		.CLK_14M(clk_14m), .CLK_2M(clk_2m), .PHASE_ZERO(phase_zero),
		.RESET(reset), .DISK_READY(disk_ready[0]), .D_IN(data_in),
		.D_OUT(drive1_data), .DISK_ACTIVE(d1_active), .MOTOR_PHASE(motor_phase),
		.WRITE_MODE(q7), .READ_DISK(read_disk), .WRITE_REG(write_register),
		.TRACK_ZERO_STEP(d1_track_zero_step), .TRACK(track1),
		.TRACK_ADDR(track1_addr), .TRACK_DI(track1_din), .TRACK_DO(track1_dout),
		.TRACK_WE(track1_we), .TRACK_BUSY(track1_busy)
	);

	drive_ii drive2 (
		.CLK_14M(clk_14m), .CLK_2M(clk_2m), .PHASE_ZERO(phase_zero),
		.RESET(reset), .DISK_READY(disk_ready[1]), .D_IN(data_in),
		.D_OUT(drive2_data), .DISK_ACTIVE(d2_active), .MOTOR_PHASE(motor_phase),
		.WRITE_MODE(q7), .READ_DISK(read_disk), .WRITE_REG(write_register),
		.TRACK_ZERO_STEP(d2_track_zero_step), .TRACK(track2),
		.TRACK_ADDR(track2_addr), .TRACK_DI(track2_din), .TRACK_DO(track2_dout),
		.TRACK_WE(track2_we), .TRACK_BUSY(track2_busy)
	);

endmodule
