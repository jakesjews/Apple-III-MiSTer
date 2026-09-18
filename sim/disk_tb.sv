`timescale 1ns / 1ps

module disk_tb;
	logic clk_14m = 0, clk_2m = 0, phase_zero = 0, reset = 1;
	logic select = 1, cycle_strobe = 0, cpu_read = 1;
	logic [7:0] addr = 0, data_in = 0;
	logic [3:0] disk_ready = 4'b1111, write_protect = 0;
	logic [3:0] bitstream_flux = 0, media_change = 0;
	logic       native_mode = 1;
	wire  [7:0] data_out;
	wire [3:0] motor_phase, drive_active, drive_motor_on, drive_io_active;
	wire side_two, write_mode, write_bit, write_strobe;
	apple3_disk dut (.*);
	always #5 clk_14m = ~clk_14m;
	always #35 clk_2m = ~clk_2m;

	task automatic touch(input [7:0] a);
		@(negedge clk_14m);
		addr         = a;
		cycle_strobe = 1;
		@(negedge clk_14m);
		cycle_strobe = 0;
	endtask

	// SOS DISK3 UNITSEL's external address: 01, 10, 11 for D2, D3, D4.
	task automatic choose(input integer drive);
		touch(drive ? 8'heb : 8'hea);
		touch(drive & 1 ? 8'hd1 : 8'hd0);
		touch(drive & 2 ? 8'hd3 : 8'hd2);
	endtask

	initial begin
		repeat (3) @(negedge clk_14m);
		reset = 0;
		touch(8'he9);
		repeat (2) @(negedge clk_14m);
		if (drive_active !== 1 || drive_motor_on !== 1) $fatal(1, "reset D1 selection");
		for (integer drive = 0; drive < 4; drive++) begin
			choose(drive);
			if (drive_active !== (4'b1 << drive)) $fatal(1, "D%0d I/O select", drive + 1);
			if (drive_motor_on !== ((4'b1 << drive) | 1)) $fatal(1, "D%0d independent spindle", drive + 1);
			addr = 8'hec;
			#1;
			if (drive_io_active !== (4'b1 << drive)) $fatal(1, "D%0d ready", drive + 1);
			disk_ready = ~(4'b1 << drive);
			#1;
			if (drive_io_active) $fatal(1, "absent drive ready");
			disk_ready = 15;
			for (integer source = 0; source < 4; source++) begin
				bitstream_flux = 4'b1 << source;
				#1;
				if (dut.selected_flux !== (source == drive)) $fatal(1, "cross-drive flux");
			end
		end
		// External address 00 selects nothing; D1 can still spin independently.
		choose(0);
		touch(8'heb);
		if (drive_active || !dut.selected_wp || drive_motor_on !== 1) $fatal(1, "external deselect");
		touch(8'hd5);
		if (drive_motor_on) $fatal(1, "internal deselect");
		touch(8'hd4);
		touch(8'hd7);
		if (!side_two) $fatal(1, "side select");

		// Mount all four; acknowledge each separately through the shared phase
		// latch, which also supplies the video fine-scroll offset.
		bitstream_flux = 15;
		@(negedge clk_14m);
		media_change = 15;
		@(negedge clk_14m);
		media_change = 0;
		for (integer drive = 0; drive < 4; drive++) begin
			choose(drive);
			if (dut.selected_flux) $fatal(1, "unacknowledged disk exposed flux");
			touch(8'he2);
			touch(8'he3);
			repeat (2) @(negedge clk_14m);
			if (!dut.selected_flux) $fatal(1, "D%0d phase acknowledgement", drive + 1);
			if (dut.disk_changed !== (4'b1110 << drive)) $fatal(1, "other disk-change latch cleared");
		end
		// A mount on D4 must not lose D1's simultaneous acknowledgement.
		choose(0);
		touch(8'he2);
		media_change = 1;
		@(negedge clk_14m);
		media_change = 0;
		touch(8'he3);
		media_change = 8;
		@(negedge clk_14m);
		media_change = 0;
		if (dut.disk_changed !== 8) $fatal(1, "simultaneous independent changes");
		// Mount wins over acknowledgement for the same drive.
		touch(8'he2);
		touch(8'he3);
		media_change = 1;
		@(negedge clk_14m);
		media_change = 0;
		if (dut.disk_changed !== 9) $fatal(1, "mount must win over acknowledgement");

		// Shared phases still latch with the motors disabled (smooth scrolling).
		touch(8'hd5);
		choose(0);
		touch(8'he1);
		touch(8'he5);
		if (motor_phase !== 7 || drive_active) $fatal(1, "shared fine-scroll phases");
		// Disk II mode ignores native selects and bypasses disk-change latches.
		native_mode = 0;
		for (integer address = 0; address < 4; address++) begin
			choose(address);
			touch(8'hea);
			if (drive_active !== 1 || drive_motor_on !== 1 || !dut.selected_flux) $fatal(1, "Disk II D1");
			touch(8'heb);
			if (drive_active !== 2 || drive_motor_on !== 2 || !dut.selected_flux) $fatal(1, "Disk II D2");
		end
		touch(8'he8);
		repeat (5) @(negedge clk_14m);
		if (drive_motor_on !== 2) $fatal(1, "motor holdover lost");
		$display("PASS apple3_disk: four drives, independent motors/flux/change, shared phases and Disk II mode");
		$finish;
	end
endmodule
