// Optional card-side expansion-ROM latch. The motherboard broadcasts C800
// and C02x; it does not arbitrate ownership between cards. SOS SELC800 first
// deselects every card, then accesses Cnxx on the desired card.
module apple3_slot_rom #(
	parameter bit DESELECT_C02X = 1'b1,
	parameter bit DESELECT_CFFF = 1'b0
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        cycle_strobe,
	input  logic        io_select,
	input  logic        io_strobe,
	input  logic        rom_deselect,
	input  logic [10:0] addr,
	output logic        selected,
	output logic        rom_select
);
	assign rom_select = !reset && io_strobe && selected;

	always_ff @(posedge clk) begin
		if (reset) selected <= 1'b0;
		else if (cycle_strobe) begin
			// Native cards use pin 39 (C02x). Apple II cards generally decode
			// CFFF instead. This is a property of the card, not the CPU mode.
			// A CFFF read still returns the selected card's last ROM byte.
			if ((DESELECT_C02X && rom_deselect) || (DESELECT_CFFF && io_strobe && (&addr))) selected <= 1'b0;
			else if (io_select) selected <= 1'b1;
		end
	end
endmodule
