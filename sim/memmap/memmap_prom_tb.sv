`timescale 1ns / 1ps

// Drives apple3_mmu, configured for Apple's memory boards, with vectors derived
// from the address-decode PROM dumps and the schematic by prom_reference.py.
module memmap_prom_tb;
	logic [15:0] cpu_addr;
	logic        cpu_read;
	logic [7:0] environment, zero_page, bank_register, extended_bank;
	logic native_mode, extended_active, ram_128k;
	wire [15:0] bus_addr;
	wire [18:0] ram_byte_addr;
	wire [17:0] ram_word_addr;
	wire ram_lane, ram_select, ram_read, ram_write_allowed, rom_read, io_select;
	wire via_d_select, via_e_select, slot_rom_select;
	wire [12:0] rom_addr;

	apple3_mmu #(.RAM_BANKS(8)) dut (.*);

	string path;
	integer file, fields, vectors = 0, failures = 0;
	logic [15:0] v_bus;
	logic [18:0] v_flat;
	logic [11:0] v_flags;
	logic v_ext, v_read, v_native, v_128k;
	logic [17:0] word;
	logic        lane;

	// prom_reference.py VECTOR_FLAGS
	wire want_ramen = v_flags[0];
	wire want_ram_read = v_flags[1];
	wire want_ram_write = v_flags[2];
	wire want_rom = v_flags[3];
	wire want_io_space = v_flags[4];
	wire want_c0xx = v_flags[5];
	wire want_via_d = v_flags[6];
	wire want_via_e = v_flags[7];
	wire want_populated = v_flags[8];

	task automatic fail(input string what);
		failures++;
		if (failures <= 20)
			$display(
				"FAIL %s: %04x zp=%02x env=%02x bank=%02x ext=%b x=%02x read=%b native=%b 128k=%b -> bus %04x ram %05x sel=%b rd=%b wr=%b rom=%b io=%b/%b via=%b%b, expected bus %04x ram %05x flags %03x",
				what,
				cpu_addr,
				zero_page,
				environment,
				bank_register,
				extended_active,
				extended_bank,
				cpu_read,
				native_mode,
				ram_128k,
				bus_addr,
				ram_byte_addr,
				ram_select,
				ram_read,
				ram_write_allowed,
				rom_read,
				io_select,
				slot_rom_select,
				via_d_select,
				via_e_select,
				v_bus,
				v_flat,
				v_flags
			);
	endtask

	initial begin
		if (!$value$plusargs("VECTORS=%s", path)) $fatal(1, "+VECTORS=<file> is required");
		file = $fopen(path, "r");
		if (file == 0) $fatal(1, "cannot open %s", path);
		while (!$feof(
			file
		)) begin
			fields = $fscanf(
				file,
				"%h %h %h %h %d %h %d %d %d %h %h %h\n",
				cpu_addr,
				zero_page,
				environment,
				bank_register,
				v_ext,
				extended_bank,
				v_read,
				v_native,
				v_128k,
				v_bus,
				v_flat,
				v_flags
			);
			if (fields != 12) $fatal(1, "bad vector after %0d", vectors);
			vectors++;
			extended_active = v_ext;
			cpu_read        = v_read;
			native_mode     = v_native;
			ram_128k        = v_128k;
			#1;
			if (bus_addr !== v_bus) fail("bus address");
			if (want_ramen && want_populated && ram_byte_addr !== v_flat) fail("RAM address");
			if (ram_select !== want_ramen) fail("RAMEN");
			if (ram_read !== want_ram_read) fail("RAM read");
			if (ram_write_allowed !== want_ram_write) fail("RAM write");
			if (rom_read !== want_rom) fail("ROM");
			if ((io_select || slot_rom_select) !== want_io_space || io_select !== want_c0xx) fail("I/O");
			if (via_d_select !== want_via_d || via_e_select !== want_via_e) fail("VIA");

			// The X byte is the other byte of the same RAM word: the PROMs strobe
			// CAS0 with CAS3 for $18xx-$1Fxx, and that pair is address xor $0C00.
			if (cpu_addr[15:8] == 8'h00 && v_read && zero_page >= 8'h18 && zero_page <= 8'h1f) begin
				word      = ram_word_addr;
				lane      = ram_lane;
				zero_page = zero_page ^ 8'h0c;
				#1;
				if (ram_word_addr !== word || ram_lane === lane) fail("X byte pairing");
			end
		end
		$fclose(file);
		if (failures != 0) $fatal(1, "memory map differs from the PROM reference: %0d failures", failures);
		$display("PASS memory map against decoder PROMs (%0d vectors)", vectors);
		$finish;
	end
endmodule
