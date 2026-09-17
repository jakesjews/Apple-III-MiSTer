`timescale 1ns / 1ps
module acia_baud_tb;
	localparam integer CLOCK_HZ = 14318182;
	reg clk = 0, reset = 1, wr = 0;
	reg  [1:0] addr = 0;
	reg  [7:0] din = 0;
	wire       tx;
	apple3_acia dut (
		.clk,
		.reset,
		.read_strobe (1'b0),
		.write_strobe(wr),
		.addr,
		.data_in     (din),
		.data_out    (),
		.rx          (1'b1),
		.cts_n       (1'b0),
		.dsr_n       (1'b0),
		.dcd_n       (1'b0),
		.tx,
		.rts_n       (),
		.dtr_n       (),
		.irq         ()
	);
	always #5 clk = ~clk;
	integer cycles = 0;
	always @(posedge clk) cycles <= cycles + 1;
	task automatic tick(input integer n);
		repeat (n) @(negedge clk);
	endtask
	task automatic write_reg(input [1:0] a, input [7:0] d);
		begin
			@(negedge clk);
			addr = a;
			din  = d;
			wr   = 1;
			tick(1);
			wr = 0;
			tick(4);
		end
	endtask
	function integer divisor(input integer rate);
		case (rate)
			1:       divisor = 2304;
			2:       divisor = 1536;
			3:       divisor = 1048;
			4:       divisor = 856;
			5:       divisor = 768;
			6:       divisor = 384;
			7:       divisor = 192;
			8:       divisor = 96;
			9:       divisor = 64;
			10:      divisor = 48;
			11:      divisor = 32;
			12:      divisor = 24;
			13:      divisor = 16;
			14:      divisor = 12;
			default: divisor = 6;
		endcase
	endfunction
	integer last_edge, now_edge, expected, count;
	initial begin
		for (integer rate = 1; rate < 16; rate++) begin
			reset = 1;
			tick(12);
			reset = 0;
			tick(12);
			write_reg(3, 8'h10 | 8'(rate));
			write_reg(2, 8'h0b);
			expected = $rtoi((1.0 * CLOCK_HZ * 16 * divisor(rate)) / 1843200.0);
			fork
				begin
					count = 0;
					while (tx !== 0 && count < expected * 2) begin
						tick(1);
						count++;
					end
					if (tx !== 0) $fatal(1, "baud %0d start timeout", rate);
					// Discard the first interval: starting between reference enables
					// can shorten the first start bit by one 16x tick.
					@(posedge tx);
					last_edge = cycles;
					for (integer edge_no = 0; edge_no < 7; edge_no++) begin
						@(tx);
						now_edge = cycles;
						if (now_edge - last_edge < expected || now_edge - last_edge > expected + 1)
							$fatal(
								1,
								"baud %0d period %0d expected %0d or %0d",
								rate,
								now_edge - last_edge,
								expected,
								expected + 1
							);
						last_edge = now_edge;
					end
				end
				begin
					write_reg(0, 8'h55);
				end
			join
		end
		// The motherboard ties external RxC low: baud selection zero cannot TX.
		reset = 1;
		tick(12);
		reset = 0;
		tick(12);
		write_reg(2, 8'h0b);
		write_reg(0, 8'h55);
		// No reference edges means no serial start bit.
		tick(20);
		if (tx !== 1'b1) $fatal(1, "external clock missing but TX started");
		last_edge = tx;
		repeat (2000) begin
			tick(1);
			if (tx !== 1'(last_edge)) $fatal(1, "external clock fabricated");
		end
		$display("PASS all 15 internal baud divisors at 14.318182 MHz (105 bit periods), external clock disconnected");
		$finish;
	end
	initial begin
		#200000000;
		$fatal(1, "baud test timeout");
	end
endmodule
