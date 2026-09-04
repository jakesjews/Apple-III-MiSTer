`timescale 1ns/1ps

// Checks dsk_nibblizer byte-for-byte against sim/coretest/dsk2nib.h, the same
// reference tools/dsk2nib.cpp and the integration test use.  Vectors are
// generated from a real Apple /// system disk: track 0 (plain), track 12
// (inside the 9..16 synchronized-track volume-key range) and track 3 converted
// in ProDOS sector order.
module nib_tb;
	logic clk = 0, reset = 1;
	always #5 clk = ~clk;

	logic        start = 0;
	logic        prodos = 0;
	logic [5:0]  track = 0;
	wire         busy;
	wire [11:0]  src_addr;
	logic [7:0]  src_data;
	wire [12:0]  dst_addr;
	wire [7:0]   dst_data;
	wire         dst_we;

	dsk_nibblizer dut (
		.clk, .reset, .start, .busy, .track, .prodos,
		.src_addr, .src_data, .dst_addr, .dst_data, .dst_we
	);

	logic [7:0] source [0:4095];
	logic [7:0] expected [0:6655];
	logic [7:0] produced [0:6655];
	integer i, errors, written;

	// Staging RAM read port: registered, matching the dpram the core uses.
	always_ff @(posedge clk) src_data <= source[src_addr];

	always_ff @(posedge clk) begin
		if (dst_we) begin
			produced[dst_addr] <= dst_data;
			written <= written + 1;
		end
	end

	task automatic run_track(input string in_file, input string exp_file,
	                         input logic [5:0] t, input logic po);
	begin
		$readmemh(in_file, source);
		$readmemh(exp_file, expected);
		for (i = 0; i < 6656; i = i + 1) produced[i] = 8'h00;
		written = 0;
		track = t;
		prodos = po;
		@(posedge clk); start <= 1'b1;
		@(posedge clk); start <= 1'b0;
		// Wait for the conversion to finish (bounded so a hang fails the test).
		for (i = 0; i < 400000 && (busy || i < 10); i = i + 1) @(posedge clk);
		if (busy) $fatal(1, "nibblizer did not finish for track %0d", t);

		errors = 0;
		for (i = 0; i < 6656; i = i + 1) begin
			if (produced[i] !== expected[i]) begin
				if (errors < 8)
					$display("  track %0d byte %0d: got %02x expected %02x",
					         t, i, produced[i], expected[i]);
				errors = errors + 1;
			end
		end
		if (written != 6656)
			$fatal(1, "track %0d wrote %0d bytes, expected 6656", t, written);
		if (errors != 0)
			$fatal(1, "track %0d mismatched in %0d of 6656 bytes", t, errors);
		$display("  track %0d (%s order): 6656/6656 bytes match",
		         t, po ? "ProDOS" : "DOS");
	end
	endtask

	initial begin
		repeat (4) @(posedge clk); reset = 0;
		run_track("sim/gen/nib_in_t0.hex",   "sim/gen/nib_exp_t0.hex",   6'd0,  1'b0);
		run_track("sim/gen/nib_in_t12.hex",  "sim/gen/nib_exp_t12.hex",  6'd12, 1'b0);
		run_track("sim/gen/nib_in_t3po.hex", "sim/gen/nib_exp_t3po.hex", 6'd3,  1'b1);
		$display("PASS dsk_nibblizer");
		$finish;
	end
endmodule
