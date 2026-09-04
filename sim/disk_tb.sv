`timescale 1ns/1ps

module disk_tb;
	logic clk_14m = 0, clk_2m = 0, phase_zero = 0, reset = 1;
	logic select = 1, cycle_strobe = 0, cpu_read = 1;
	logic [7:0] addr = 0, data_in = 0;
	logic [1:0] disk_ready = 2'b11, write_protect = 2'b10;
	wire [7:0] data_out;
	wire [3:0] motor_phase;
	wire side_two, d1_active, d2_active, d1_motor_on, d2_motor_on;
	wire d1_io_active, d2_io_active, d1_track_zero_step, d2_track_zero_step;
	wire [5:0] track1, track2;
	wire [12:0] track1_addr, track2_addr;
	wire [7:0] track1_din, track2_din;
	logic [7:0] track1_dout = 8'ha5, track2_dout = 8'h5a;
	wire track1_we, track2_we;
	logic track1_busy = 0, track2_busy = 0;

	apple3_disk dut (.*);
	always #5 clk_14m = ~clk_14m;
	always #35 clk_2m = ~clk_2m;

	task automatic touch(input [7:0] a);
	begin
		addr = a; cycle_strobe = 1;
		@(posedge clk_14m); #1; cycle_strobe = 0;
	end
	endtask

	initial begin
		repeat (2) @(posedge clk_14m); reset = 0;
		touch(8'he9); // motor on, internal selected after reset
		@(posedge clk_14m); #1;
		if (!d1_active || !d1_motor_on || d2_active) $fatal(1, "D1 selection");

		touch(8'he1); touch(8'he3); touch(8'he5);
		if (motor_phase !== 4'b0111) $fatal(1, "phase latch=%x", motor_phase);

		// SOS D2 sequence: external I/O, external address 01.
		touch(8'hd1); touch(8'hd2); touch(8'heb);
		if (!d2_active || d1_active) $fatal(1, "D2 selection");
		// The WOZ state machine presents one nibble byte every 32 CPU clocks.
		repeat (500) @(posedge clk_14m);
		touch(8'hed); // Q6 set: write-protect sense
		addr = 8'hec; #1;
		if (data_out !== 8'h80) $fatal(1, "D2 write protect=%02x", data_out);
		touch(8'hec); // Q6 clear: data register
		addr = 8'hec; #1;
		if (data_out !== 8'h5a) $fatal(1, "D2 data=%02x", data_out);

		touch(8'hea); touch(8'hd4);
		if (!d1_active || d2_active) $fatal(1, "return to D1");
		touch(8'hd7);
		if (!side_two) $fatal(1, "side select");

		$display("PASS apple3_disk");
		$finish;
	end
endmodule
