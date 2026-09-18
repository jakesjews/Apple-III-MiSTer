// Synthetic card used by both the bus tests and the real-CPU diagnostic.
// Registers: 0 scratch, 1 IRQ, 2 NMI, 3 read counter, 4 Cnxx write, 5 C800 write.
module test_card #(
	parameter integer SLOT   = 1,
	parameter bit     LEGACY = 1'b0
) (
	input  logic        clk,
	reset,
	cycle,
	input  logic [15:0] addr,
	input  logic        cpu_read,
	input  logic [ 7:0] data_in,
	input  logic        device_select,
	io_select,
	io_strobe,
	rom_deselect,
	output logic [ 7:0] data_out,
	output logic        data_oe,
	irq_n,
	nmi_n,
	output logic        selected
);
	logic       rom_select;
	logic [7:0] registers  [6];
	apple3_slot_rom #(
		.DESELECT_C02X(!LEGACY),
		.DESELECT_CFFF(LEGACY)
	) expansion (
		.clk,
		.reset,
		.cycle_strobe(cycle),
		.io_select,
		.io_strobe,
		.rom_deselect,
		.addr        (addr[10:0]),
		.selected,
		.rom_select
	);
	assign irq_n = !registers[1][0];
	assign nmi_n = !registers[2][0];
	always_comb begin
		data_out = 8'hff;
		data_oe  = !reset && cpu_read && (device_select || io_select || rom_select);
		if (device_select && addr[3:0] < 6) data_out = registers[addr[2:0]];
		else if (io_select) data_out = (8'ha0 + 8'(SLOT)) ^ addr[7:0];
		else if (rom_select) data_out = (8'he0 + 8'(SLOT)) ^ addr[7:0] ^ {5'd0, addr[10:8]};
	end
	always_ff @(posedge clk) begin
		if (reset) begin
			for (int i = 0; i < 6; i++) registers[i] <= 8'd0;
		end else if (cycle) begin
			if (device_select && !cpu_read && addr[3:0] < 6) registers[addr[2:0]] <= data_in;
			if (device_select && cpu_read && addr[3:0] == 3) registers[3] <= registers[3] + 8'd1;
			if (io_select && !cpu_read) registers[4] <= data_in;
			if (rom_select && !cpu_read) registers[5] <= data_in;
		end
	end
endmodule
