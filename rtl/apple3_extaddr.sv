// The Apple /// bank latch: A9 (LS399) with its select gate E8 and clock gate
// H4 (LS51), drawing 050-0039-H sheet 3.
//
// A9 holds either the bank register (BCKSW, word 0) or the X byte (DA, word
// 1), and ABK4 tells which.  E8 picks the X byte when S399 and DA7 are both
// high: a zero-page read while the zero page register is $18-$1F, with bit 7
// of the sister byte set.  H4 clocks the latch at the end of every read that
// is not itself redirected, so:
//  * a store to the bank register reaches the map one read later.  The opcode
//    fetch that follows the store still sees the old bank;
//  * an opcode fetched from such a zero page latches its X byte like any
//    other zero-page read.
// H4's second term reloads the latch early in an opcode fetch that IND would
// otherwise hold off, which is what ends extended addressing at SYNC.
//
// Apple's boards wire three bits of each word; a 512 KiB upgrade adds the
// fourth, so all four are kept here and the MMU masks them.

module apple3_extaddr (
	input  logic        clk,
	input  logic        reset,
	input  logic        cycle_strobe,
	input  logic        sync,
	input  logic        cpu_read,
	// Only the page, Z7-Z3, BCKSW and DA7, DA3-DA0 reach the latch.
	/* verilator lint_off UNUSEDSIGNAL */
	input  logic [15:0] cpu_addr,
	input  logic [ 7:0] zero_page,
	input  logic [ 7:0] bank_register,
	input  logic [ 7:0] sister_data,
	/* verilator lint_on UNUSEDSIGNAL */
	output logic        active,
	output logic [ 7:0] bank,
	output logic [ 7:0] window_bank
);
	logic [3:0] abk_q, abk;
	logic abk4_q, abk4;
	logic zero_page_access, s399, reload_at_sync, x_byte;

	always_comb begin
		// -ZPAGE with PA8 low.  The alternate stack never qualifies: S399 and
		// -IND both need PA8 low.
		zero_page_access = (cpu_addr[15:8] == 8'h00);
		s399             = zero_page_access && (zero_page[7:3] == 5'b00011);

		// /Q3*PH0*SYNC fires before the access when R/W*-IND*PH0 is held off.
		// S399 is low for any address IND applies to, so word 0 loads.
		reload_at_sync = sync && abk4_q && !zero_page_access;
		abk4           = abk4_q && !reload_at_sync;
		abk            = reload_at_sync ? bank_register[3:0] : abk_q;

		active      = abk4;
		bank        = abk4 ? {4'h8, abk} : 8'h00;
		window_bank = {4'h0, abk};
		x_byte      = s399 && sister_data[7];
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			abk4_q <= 1'b0;
			abk_q  <= 4'hf;
		end else if (cycle_strobe && ((cpu_read && !(abk4 && !zero_page_access)) || sync)) begin
			abk4_q <= x_byte;
			abk_q  <= x_byte ? sister_data[3:0] : bank_register[3:0];
		end
	end

endmodule
