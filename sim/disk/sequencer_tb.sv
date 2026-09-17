`timescale 1ns / 1ps
module sequencer_tb;
	reg clk = 0, reset = 1, q3 = 0, q6 = 0, q7 = 0, flux = 0, write_protect = 0;
	reg  [7:0] data_in = 0;
	wire [7:0] data_out;
	wire write_bit, write_strobe;
	always #5 clk = ~clk;
	apple3_disk_sequencer dut (.*);
	reg  [7:0] a;
	wire [7:0] q;
	apple3_p6 logic_prom (
		.a,
		.q
	);
	reg [7:0] prom[0:255];
	reg [7:0] reference_address = 0, reference_data = 0, op;
	reg    [31:0] random_state = 32'h12345678;
	string        path;
	initial begin
		if (!$value$plusargs("PROM=%s", path)) $fatal(1, "PROM reference required");
		$readmemh(path, prom);
		for (integer i = 0; i < 256; i++) begin
			a = i;
			#1;
			if (q !== prom[i]) $fatal(1, "P6 address %02x: %02x != %02x", i, q, prom[i]);
		end
		repeat (3) @(negedge clk);
		reset = 0;
		for (integer i = 0; i < 50000; i++) begin
			random_state  = 1664525 * random_state + 1013904223;
			q6            = random_state[29];
			q7            = random_state[28];
			write_protect = random_state[27];
			data_in       = random_state[7:0];
			q3            = 1;
			repeat (3) @(negedge clk);
			flux = random_state[31];
			@(negedge clk);
			q3 = 0;
			flux = 0;
			reference_address=(reference_address&8'he1) |
				{3'b0,!random_state[31],q7,q6,reference_data[7],1'b0};
			op = prom[reference_address];
			reference_address = (reference_address & 8'h1e) | (op & 8'hc0) | ((op & 8'h20) >> 5) | ((op & 8'h10) << 1);
			case (op & 15)
				0, 1, 2, 3, 4, 5, 6, 7: reference_data = 0;
				9:                      reference_data = reference_data << 1;
				10, 14:                 reference_data = (reference_data >> 1) | (write_protect ? 8'h80 : 0);
				11, 15:                 reference_data = data_in;
				13:                     reference_data = (reference_data << 1) | 1;
				default:                ;
			endcase
			@(posedge clk);
			#1;
			if (data_out !== reference_data) $fatal(1, "P6 cycle %0d: %02x != %02x", i, data_out, reference_data);
			repeat (3) @(negedge clk);
		end
		// A parallel-loaded byte must leave WR DATA in MSB-first order.
		// This checks the adapter's bit-cell strobes separately from PROM truth.
		for (integer value = 0; value < 256; value++) begin : write_test
			reg [7:0] emitted;
			integer count, watchdog;
			@(negedge clk);
			reset = 1;
			q3    = 0;
			flux  = 0;
			repeat (3) @(negedge clk);
			reset    = 0;
			q7       = 1;
			q6       = 1;
			data_in  = value;
			// Stop immediately after the sequencer's parallel-load operation.
			watchdog = 0;
			while (dut.state != 4'b0011 && watchdog < 32) begin
				q3 = 1;
				repeat (4) @(negedge clk);
				q3 = 0;
				repeat (3) @(negedge clk);
				watchdog++;
			end
			if (data_out !== value[7:0]) $fatal(1, "parallel write load");
			q6       = 0;
			emitted  = 0;
			count    = 0;
			watchdog = 0;
			while (count < 8 && watchdog < 80) begin
				q3 = 1;
				repeat (4) @(negedge clk);
				q3 = 0;
				@(posedge clk);
				#1;
				if (write_strobe) begin
					emitted = {emitted[6:0], write_bit};
					count++;
				end
				repeat (3) @(negedge clk);
				watchdog++;
			end
			if (count != 8 || emitted !== value[7:0])
				$fatal(1, "write stream %02x != %02x, count=%0d", emitted, value, count);
		end
		$display(
			"PASS P6: all 256 truth-table entries and 50000 sequencer cycles against original PROM, all 256 written bytes");
		$finish;
	end
endmodule
