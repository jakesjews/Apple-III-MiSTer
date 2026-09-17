`timescale 1ns / 1ps
module cell_tb;
	reg       clk = 0;
	reg [7:0] timing = 0;
	wire [8:0] cell_base, half_base;
	wire [9:0] cell_step, half_step;
	woz_cell525 dut (.*);
	always #5 clk = ~clk;
	task check(input [7:0] value, input integer whole, input integer fraction);
		timing = value;
		repeat (2) @(negedge clk);
		if (cell_base != whole || cell_step != fraction)
			$fatal(1, "WOZ timing %0d: %0d.%03d != %0d.%03d", value, cell_base, cell_step, whole, fraction);
	endtask
	initial begin
		check(0, 57, 272);
		check(16, 28, 636);
		check(28, 50, 113);
		check(32, 57, 272);
		check(35, 62, 642);
		check(36, 64, 431);
		check(255, 456, 392);
		$display("PASS WOZ bit timing: 125ns units, default and full 8-bit range");
		$finish;
	end
endmodule
