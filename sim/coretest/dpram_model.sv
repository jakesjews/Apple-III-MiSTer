// Simulation model for rtl/disk/dpram.vhd.  Port B registers its address on
// clock_b and presents unregistered data, matching the Cyclone V altsyncram
// used by the synthesized core.  Both clocks are the same in this testbench.
module dpram #(
	parameter integer addr_width_g = 8,
	parameter integer data_width_g = 8
) (
	input  logic [addr_width_g-1:0] address_a,
	input  logic [addr_width_g-1:0] address_b,
	input  logic                    clock_a,
	input  logic                    clock_b,
	input  logic [data_width_g-1:0] data_a,
	input  logic [data_width_g-1:0] data_b,
	input  logic                    wren_a,
	input  logic                    wren_b,
	output logic [data_width_g-1:0] q_a,
	output logic [data_width_g-1:0] q_b
);

	logic [data_width_g-1:0] memory [0:(1 << addr_width_g)-1];
	logic [addr_width_g-1:0] address_b_q;

	// The production instance ties clock_a and clock_b together.  A single
	// process gives deterministic same-address write behavior in Verilator.
	always_ff @(posedge clock_a) begin
		address_b_q <= address_b;
		if (wren_a) memory[address_a] <= data_a;
		if (wren_b) memory[address_b] <= data_b;
	end

	always_comb begin
		q_a = memory[address_a];
		q_b = memory[address_b_q];
	end

	// clock_b is intentionally present to keep the simulation port-compatible.
	wire unused_clock_b = clock_b;

endmodule
