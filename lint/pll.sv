// Lint-only interface matching rtl/pll.v. Quartus uses the generated PLL;
// this intentionally has no implementation and must not be used for simulation.
module pll (
	input  wire refclk,
	input  wire rst,
	output wire outclk_0,
	output wire outclk_1,
	output wire locked
);
endmodule
