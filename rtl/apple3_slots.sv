// Apple /// slot 1-4 bus decoding (050-0039-H, sheet 5).
// Selects are active high and remain valid throughout a CPU transaction.
// Cards commit side effects only on the core's slot_cycle clock enable.
module apple3_slots (
	input  logic             reset,
	input  logic             io_select,
	input  logic             rom_select,
	input  logic [11:4]      addr,
	input  logic             cpu_read,
	input  logic [ 3:0][7:0] card_data,
	input  logic [ 3:0]      card_data_oe,
	output logic [ 3:0]      device_select,
	output logic [ 3:0]      io_rom_select,
	output logic             io_strobe,
	output logic             rom_deselect,
	output logic [ 7:0]      data_out,
	output logic             data_valid,
	output logic             bus_conflict
);
	logic [3:0] responders;

	always_comb begin
		device_select = 4'b0000;
		io_rom_select = 4'b0000;
		io_strobe     = !reset && rom_select && addr[11];
		rom_deselect  = !reset && io_select && (addr[7:4] == 4'h2);
		for (int i = 0; i < 4; i++) begin
			device_select[i] = !reset && io_select && (addr[7:4] == 4'(9 + i));
			io_rom_select[i] = !reset && rom_select && (addr[11:8] == 4'(1 + i));
		end

		// An empty socket reads $FF. A card may leave individual registers
		// undriven, but cannot drive another slot's private aperture or RAM.
		responders   = card_data_oe & (device_select | io_rom_select | {4{io_strobe}}) & {4{cpu_read}};
		data_out     = 8'hff;
		data_valid   = |responders;
		bus_conflict = |(responders & (responders - 4'b0001));
		for (int i = 0; i < 4; i++) begin
			if (responders[i]) data_out = data_out & card_data[i];
		end
		// Multiple C800 responders are a software/card error. The AND above
		// is deterministic; it does not model electrical bus contention.
	end
endmodule
