`timescale 1ns / 1ps
// P6 write-protect sense follows the I/O-selected Disk III, even with both motors on.
module disk_protection_tb;
	logic clk_14m = 0, clk_2m = 0, phase_zero = 1, reset = 1;
	always #5 clk_14m = ~clk_14m;
	always #35 clk_2m = ~clk_2m;
	logic select = 1, cycle_strobe = 0, cpu_read = 1;
	logic [7:0] addr = 0, data_in = 0;
	logic [3:0] disk_ready = 15, write_protect = 15, bitstream_flux = 0, media_change = 0;
	logic       native_mode = 1;
	wire  [7:0] data_out;
	wire  [3:0] motor_phase;
	wire        side_two;
	wire [3:0] drive_active, drive_motor_on, drive_io_active;
	wire write_mode, write_bit, write_strobe;
	apple3_disk dut (.*);
	task automatic touch(input [7:0] a);
		@(negedge clk_14m);
		addr         = a;
		cycle_strobe = 1;
		@(negedge clk_14m);
		cycle_strobe = 0;
	endtask
	initial begin
		repeat (3) @(negedge clk_14m);
		reset = 0;
		touch(8'he9);
		touch(8'hd1);
		touch(8'hed);
		for (integer drive = 0; drive < 4; drive++) begin
			touch(drive ? 8'heb : 8'hea);
			touch(drive & 1 ? 8'hd1 : 8'hd0);
			touch(drive & 2 ? 8'hd3 : 8'hd2);
			for (integer wp = 0; wp < 2; wp++) begin
				write_protect = wp ? (4'b1 << drive) : ~(4'b1 << drive);
				addr          = 8'hec;
				repeat (160) @(negedge clk_14m);
				if (data_out[7] !== wp[0])
					$fatal(1, "D%0d protection sense=%02x expected=%0d", drive + 1, data_out, wp);
				if (drive_motor_on !== ((4'b1 << drive) | 1)) $fatal(1, "other motor stopped");
			end
		end
		$display("PASS Disk III: independent drive write-protect sense with both motors running");
		$finish;
	end
endmodule
