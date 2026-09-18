// Apple /// integrated floppy controller.
//
// The Apple /// latch decode surrounds a 341-0028 P6 sequencer. Native WOZ
// drives supply flux pulses; Main handles all image formats and file writes.
// SOS DISK3, the original PROM and service schematics define the interface.

module apple3_disk (
	input  logic       clk_14m,
	input  logic       clk_2m,
	input  logic       phase_zero,
	input  logic       reset,
	input  logic       select,
	input  logic       cycle_strobe,
	input  logic       cpu_read,
	input  logic [7:0] addr,
	input  logic [7:0] data_in,
	input  logic [3:0] disk_ready,
	input  logic [3:0] write_protect,
	input  logic [3:0] bitstream_flux,
	input  logic [3:0] media_change,
	input  logic       native_mode,
	output wire        write_mode,
	output wire        write_bit,
	output wire        write_strobe,
	output logic [7:0] data_out,

	output logic [3:0] motor_phase,
	output logic       side_two,
	output logic [3:0] drive_active,
	output logic [3:0] drive_motor_on,
	output logic [3:0] drive_io_active

);

	logic [ 1:0] external_drive;
	logic        internal_enable;
	logic        external_io;
	logic        motor_on;
	logic        motor_real_on;
	logic        q6;
	logic        q7;
	logic        read_disk;
	logic [23:0] spindown_count;
	reg   [ 3:0] disk_changed;
	reg          phase1_d;
	wire         selected_flux = |(bitstream_flux & drive_active & (native_mode ? ~disk_changed : 4'b1111));
	wire         selected_wp = !(|drive_active) || |(write_protect & drive_active);
	wire  [ 7:0] sequencer_data;
	reg   [ 7:0] last_write;
	always @(posedge clk_14m) begin
		if (reset) last_write <= 0;
		else if (cycle_strobe && select && !cpu_read) last_write <= data_in;
	end
	assign write_mode = q7;
	apple3_disk_sequencer sequencer (
		.clk          (clk_14m),
		.reset,
		.q3           (clk_2m),
		.q6,
		.q7,
		.flux         (selected_flux),
		.write_protect(selected_wp),
		.data_in      (last_write),
		.data_out     (sequencer_data),
		.write_bit,
		.write_strobe
	);
	// Rev-D analog card: insertion/removal inhibits RD DATA until a phase-1
	// edge acknowledges the change. Apple II mode bypasses this latch.
	always @(posedge clk_14m) begin
		phase1_d <= motor_phase[1];
		if (reset) begin
			phase1_d     <= 0;
			disk_changed <= 0;
		end else begin
			disk_changed <= (disk_changed & ~((!phase1_d && motor_phase[1]) ? drive_active : 4'b0000)) | media_change;
		end
	end


	always_comb begin
		read_disk         = select && (addr == 8'hec);
		// Disk III selects spindle power independently from its I/O bus.
		// SOS deliberately leaves D1 spinning while accessing an external drive.
		drive_motor_on[0] = motor_real_on && (native_mode ? internal_enable : !external_io);
		drive_motor_on[1] = motor_real_on && (native_mode ? external_drive == 2'b01 : external_io);
		drive_motor_on[2] = motor_real_on && native_mode && external_drive == 2'b10;
		drive_motor_on[3] = motor_real_on && native_mode && external_drive == 2'b11;
		drive_active      = drive_motor_on & {{3{external_io}}, !external_io};
		drive_io_active   = drive_active & disk_ready & {4{read_disk}};

		if (addr[0]) data_out = 8'hff;
		else data_out = sequencer_data;
	end

	always_ff @(posedge clk_14m) begin
		if (reset) begin
			motor_phase     <= 4'h0;
			external_drive  <= 2'b00;
			internal_enable <= 1'b1;
			side_two        <= 1'b0;
			external_io     <= 1'b0;
			motor_on        <= 1'b0;
			motor_real_on   <= 1'b0;
			spindown_count  <= 24'd0;
			q6              <= 1'b0;
			q7              <= 1'b0;
		end else begin
			if (motor_on) begin
				motor_real_on  <= 1'b1;
				spindown_count <= 24'd0;
			end else if (motor_real_on) begin
				if (spindown_count == 0) spindown_count <= 24'd9545454;
				else if (spindown_count == 1) begin
					spindown_count <= 24'd0;
					motor_real_on  <= 1'b0;
				end else spindown_count <= spindown_count - 1'b1;
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
					default:      ;
				endcase
			end
		end
	end

endmodule
