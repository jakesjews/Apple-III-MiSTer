`timescale 1ns/1ps

module disk_tb;
	logic clk_14m = 0, clk_2m = 0, phase_zero = 0, reset = 1;
	logic select = 1, cycle_strobe = 0, cpu_read = 1;
	logic [7:0] addr = 0, data_in = 0;
	logic [1:0] disk_ready = 2'b11, write_protect = 2'b10;
	wire [7:0] data_out;
	wire [3:0] motor_phase;
	wire side_two, d1_active, d2_active, d1_motor_on, d2_motor_on;
	wire d1_io_active, d2_io_active;
	logic [1:0] bitstream_flux=0, media_change=0;
	logic native_mode=1;
	wire write_mode,write_bit,write_strobe;
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
		// The external I/O selection must not stop the internal spindle.
		if (!d1_motor_on || !d2_motor_on) $fatal(1, "independent Disk III motors");
		repeat (500) @(posedge clk_14m);
		touch(8'hed); // Q6 set: write-protect sense
		addr = 8'hec; #1;
		repeat (100) @(posedge clk_14m);
		if (!data_out[7]) $fatal(1, "D2 write protect=%02x", data_out);
		touch(8'hec); // Q6 clear; reads never acknowledge the P6 register

		touch(8'hea); touch(8'hd4);
		if (!d1_active || d2_active) $fatal(1, "return to D1");
		touch(8'hd7);
		if (!side_two) $fatal(1, "side select");

        // The III's native disk-switch latch hides read pulses until a head
        // phase acknowledges insertion; Apple II emulation bypasses it.
        bitstream_flux=2'b01;
        @(negedge clk_14m);media_change=2'b01;
        @(negedge clk_14m);media_change=0;
        #1;if(dut.selected_flux) $fatal(1,"unacknowledged changed disk exposed flux");
        native_mode=0;#1;
        if(!dut.selected_flux) $fatal(1,"Apple II mode did not bypass disk-change latch");
        native_mode=1;
        touch(8'he2);touch(8'he3);
        repeat(2) @(negedge clk_14m);
        if(!dut.selected_flux) $fatal(1,"phase 1 did not acknowledge changed disk");
        touch(8'hd1);touch(8'hd3);touch(8'heb);
        if(d1_active || d2_active || dut.selected_flux) $fatal(1,"unpopulated D4 selected a drive");

        // Disk II emulation has its conventional mutually exclusive enables.
        native_mode=0;touch(8'hea);#1;
        if (!d1_motor_on || d2_motor_on) $fatal(1,"Apple II drive 1 motor mux");
        touch(8'heb);#1;
        if (d1_motor_on || !d2_motor_on) $fatal(1,"Apple II drive 2 motor mux");
        $display("PASS apple3_disk: P6 status, native/Apple II drive selection, independent motors and disk change");
		$finish;
	end
endmodule
