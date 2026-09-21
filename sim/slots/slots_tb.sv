`timescale 1ns / 1ps
module slots_tb;
	logic clk = 0, reset = 1, cycle = 0;
	logic [15:0] addr = 0;
	logic        cpu_read = 1;
	logic [7:0] data_in = 0, environment = 8'hff, extended_bank = 8'h8f;
	logic native_mode = 1, extended_active = 0;
	wire io_select, rom_select, ram_select, ram_read, ram_write_allowed;
	wire [3:0] device_select, io_rom_select, selected;
	wire io_strobe, rom_deselect, data_valid, bus_conflict;
	wire    [7:0]      data_out;
	wire    [3:0][7:0] card_data;
	wire    [3:0]      card_oe;
	logic   [3:0]      present = 4'b1111;
	logic              rogue_oe = 0;
	integer            checks = 0;
	always #5 clk = ~clk;
	apple3_mmu mmu (
		.cpu_addr       (addr),
		.cpu_read,
		.environment,
		.zero_page      (8'd0),
		.bank_register  (8'd0),
		.native_mode,
		.extended_active,
		.extended_bank,
		.ram_128k       (1'b0),
		.bus_addr       (),
		.ram_byte_addr  (),
		.ram_word_addr  (),
		.ram_lane       (),
		.ram_select,
		.ram_read,
		.ram_write_allowed,
		.rom_read       (),
		.rom_addr       (),
		.io_select,
		.slot_rom_select(rom_select),
		.via_d_select   (),
		.via_e_select   ()
	);
	apple3_slots dut (
		.reset,
		.io_select,
		.rom_select,
		.addr        (addr[11:4]),
		.cpu_read,
		.card_data,
		.card_data_oe(rogue_oe ? 4'b1111 : (card_oe & present)),
		.device_select,
		.io_rom_select,
		.io_strobe,
		.rom_deselect,
		.data_out,
		.data_valid,
		.bus_conflict
	);
	for (genvar s = 0; s < 4; s++) begin : cards
		test_card #(
			.SLOT  (s + 1),
			.LEGACY(s % 2 == 1)
		) card (
			.clk,
			.reset,
			.cycle,
			.addr,
			.cpu_read,
			.data_in,
			.device_select(device_select[s]),
			.io_select    (io_rom_select[s]),
			.io_strobe,
			.rom_deselect,
			.data_out     (card_data[s]),
			.data_oe      (card_oe[s]),
			.irq_n        (),
			.nmi_n        (),
			.selected     (selected[s])
		);
	end
	task automatic check(input logic ok, input string message);
		checks++;
		if (!ok) $fatal(1, "%s at %04x data=%02x selected=%b", message, addr, data_out, selected);
	endtask
	task automatic access (input logic [15:0] a, input logic rd, input logic [7:0] value);
		@(negedge clk);
		addr     = a;
		cpu_read = rd;
		data_in  = value;
		cycle    = 1;
		@(negedge clk);
		cycle = 0;
	endtask
	task automatic read_byte(input logic [15:0] a, input logic [7:0] value);
		@(negedge clk);
		addr     = a;
		cpu_read = 1;
		cycle    = 1;
		#1;
		check(data_out === value, "read data");
		@(negedge clk);
		cycle = 0;
	endtask
	task automatic deselect_all;
		access (16'hc020, 1, 0);
		access (16'hcfff, 1, 0);
		check(selected == 0, "SOS deselect sequence");
	endtask
	initial begin
		repeat (2) @(negedge clk);
		reset = 0;
		// Exhaustive address decode in native/II, I/O hidden/visible, both
		// directions and extended system-bank accesses. No CPU strobe occurs.
		for (int config_bits = 0; config_bits < 16; config_bits++) begin
			native_mode     = config_bits[0];
			environment[6]  = config_bits[1];
			extended_active = config_bits[2];
			cpu_read        = config_bits[3];
			for (int a = 0; a < 65536; a++) begin
				addr = 16'(a);
				#1;
				for (int s = 0; s < 4; s++) begin
					check(
						device_select[s] == (environment[6] && !extended_active &&
						a >= 'hc090 + s * 16 && a <= 'hc09f + s * 16),
						"device aperture");
					check(
						io_rom_select[s] == (environment[6] && !extended_active &&
						a >= 'hc100 + s * 256 && a <= 'hc1ff + s * 256),
						"ROM aperture");
				end
				check(io_strobe == (environment[6] && !extended_active && a >= 'hc800 && a <= 'hcfff),
					  "shared ROM aperture");
				check(rom_deselect == (environment[6] && !extended_active && a >= 'hc020 && a <= 'hc02f),
					  "C02x decode");
				if (a >= 'hc500 && a <= 'hc7ff) check(ram_select, "C500-C7FF always RAM");
			end
		end
		check(selected == 0, "address changes without a CPU cycle must not select ROM");
		environment     = 8'hff;
		native_mode     = 1;
		extended_active = 0;
		cpu_read        = 1;
		for (int s = 0; s < 4; s++) begin
			deselect_all();
			access (16'('hc090 + 16 * s), 0, 8'('h30 + s));
			read_byte(16'('hc090 + 16 * s), 8'('h30 + s));
			check(selected == 0, "device access does not claim C800");
			read_byte(16'('hc100 + 256 * s), 8'('ha1 + s));
			check(selected == (4'b0001 << s), "private ROM selects its own card");
			read_byte(16'hc800, 8'('he1 + s));
			read_byte(16'hcffe, 8'('he1 + s) ^ 8'hfe ^ 8'h07);
			read_byte(16'hcfff, 8'('he1 + s) ^ 8'hff ^ 8'h07);
			check(selected == ((s % 2 == 0) ? (4'b0001 << s) : 4'd0), "card-specific CFFF release");
			// Either access direction selects/releases, and writes reach both
			// ROM apertures (cards can map RAM or registers there).
			access (16'('hc100 + 256 * s), 0, 8'h71);
			access (16'hc800, 0, 8'h93);
			read_byte(16'('hc094 + 16 * s), 8'h71);
			read_byte(16'('hc095 + 16 * s), 8'h93);
			access (16'hc02f, 0, 0);
			check(selected == ((s % 2 == 1) ? (4'b0001 << s) : 4'd0), "card-specific C02x release");
			access (16'hcfff, 0, 0);
			check(selected == 0, "write deselect sequence");
		end
		// Independent card latches, not a global last-selected-slot shortcut.
		access (16'hc100, 1, 0);
		access (16'hc300, 1, 0);
		addr = 16'hc800;
		#1;
		check(selected == 4'b0101 && bus_conflict, "detect competing C800 responders");
		deselect_all();
		// I/O hiding and both indirect bank mappings must preserve ownership.
		access (16'hc100, 1, 0);
		environment[6] = 0;
		access (16'hc020, 1, 0);
		access (16'hcfff, 0, 0);
		check(selected == 1 && !data_valid && ram_select, "hidden ROM survives RAM accesses");
		environment[6]  = 1;
		extended_active = 1;
		for (int bank = 0; bank < 2; bank++) begin
			extended_bank = bank == 0 ? 8'h80 : 8'h8f;
			access (16'hc020, 1, 0);
			access (16'hc400, 1, 0);
			access (16'hcfff, 0, 0);
			check(selected == 1 && !data_valid && ram_select, "extended RAM bypasses cards");
		end
		extended_active = 0;
		read_byte(16'hc800, 8'he1);
		present = 0;
		read_byte(16'hc800, 8'hff);
		read_byte(16'hc100, 8'hff);
		read_byte(16'hc090, 8'hff);
		check(!data_valid, "empty slots do not drive bus");
		// A broken card asserting OE outside its aperture must not replace
		// another card, motherboard I/O, ROM or the RAM underneath.
		rogue_oe = 1;
		addr     = 16'h2000;
		#1;
		check(!data_valid, "stray card OE cannot drive RAM");
		addr = 16'hc060;
		#1;
		check(!data_valid, "stray card OE cannot drive motherboard I/O");
		addr = 16'hf000;
		#1;
		check(!data_valid, "stray card OE cannot drive motherboard ROM");
		addr = 16'hc100;
		#1;
		check(data_valid && !bus_conflict, "private aperture excludes other cards' OE");
		cpu_read = 0;
		#1;
		check(!data_valid, "cards cannot drive write cycles");
		cpu_read = 1;
		rogue_oe = 0;
		present  = 15;
		access (16'hc093, 0, 0);
		addr     = 16'hc093;
		cpu_read = 1;
		repeat (20) @(negedge clk);
		check(data_out == 0, "read side effects wait for CPU strobe");
		read_byte(16'hc093, 0);
		read_byte(16'hc093, 1);
		reset = 1;
		#1;
		check(!data_valid && !io_strobe && device_select == 0, "reset releases bus");
		@(negedge clk);
		check(selected == 0, "reset clears all ROM latches");
		$display("PASS slot decode and ROM selection (%0d checks)", checks);
		$finish;
	end
endmodule
