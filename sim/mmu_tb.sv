`timescale 1ns / 1ps

module mmu_tb;
	logic [15:0] cpu_addr;
	logic        cpu_read;
	logic [7:0] environment, zero_page, bank_register, extended_bank;
	logic native_mode, extended_active;
	wire [18:0] ram_byte_addr;
	wire [17:0] ram_word_addr;
	wire ram_lane, ram_select, ram_read, ram_write_allowed, rom_read, io_select;
	wire via_d_select, via_e_select, slot_rom_select;
	wire    [12:0] rom_addr;
	integer        checks = 0;

	apple3_mmu #(.RAM_BANKS(16)) dut (.*);

	task automatic expect_addr(input [15:0] a, input [18:0] p);
		begin
			cpu_addr = a;
			#1;
			checks = checks + 1;
			if (ram_byte_addr !== p) begin
				$display("FAIL address %04x -> %05x, expected %05x", a, ram_byte_addr, p);
				$fatal(1);
			end
		end
	endtask

	task automatic expect_decode(input rram, input wram, input rrom, input io, input vd, input ve);
		begin
			#1;
			checks = checks + 1;
			if ({ram_read,ram_write_allowed,rom_read,io_select,via_d_select,via_e_select} !==
			{rram,wram,rrom,io,vd,ve}) begin
				$display("FAIL decode @%04x got %b%b%b%b%b%b expected %b%b%b%b%b%b", cpu_addr, ram_read,
						 ram_write_allowed, rom_read, io_select, via_d_select, via_e_select, rram, wram, rrom, io, vd,
						 ve);
				$fatal(1);
			end
		end
	endtask

	task automatic expect_ram_select(input logic value);
		#1;
		checks++;
		if (ram_select !== value)
			$fatal(1, "RAMEN @%x read=%b protected=%b got=%b", cpu_addr, cpu_read, environment[3], ram_select);
	endtask

	initial begin
		cpu_read        = 1'b1;
		environment     = 8'hff;  // stock reset environment
		zero_page       = 8'h00;
		bank_register   = 8'h00;
		native_mode     = 1'b1;
		extended_active = 1'b0;
		extended_bank   = 8'h00;

		// Fixed system-bank pieces and ordinary 32-K window.
		expect_addr(16'h0000, 19'h78000);
		expect_addr(16'h1fff, 19'h79fff);
		expect_addr(16'h2000, 19'h00000);
		expect_addr(16'h9fff, 19'h07fff);
		expect_addr(16'ha000, 19'h7a000);
		expect_addr(16'hffff, 19'h7ffff);

		// Window bank selection, including the forbidden system-bank alias.
		bank_register = 8'h0e;
		expect_addr(16'h3456, 19'h71456);
		bank_register = 8'h0f;
		expect_addr(16'h2000, 19'h10000);

		// Relocated zero page and adjacent-stack modes.
		bank_register = 8'h04;
		zero_page     = 8'h18;
		expect_addr(16'h007a, 19'h7987a);
		environment[2] = 1'b0;
		expect_addr(16'h017a, 19'h7997a);
		zero_page = 8'h43;
		expect_addr(16'h0055, 19'h22355);
		expect_addr(16'h0155, 19'h22255);
		zero_page = 8'ha2;
		expect_addr(16'h00aa, 19'h7a2aa);

		// Instruction-scoped linear addressing and special $8f mapping.
		environment     = 8'hff;
		extended_active = 1'b1;
		extended_bank   = 8'h83;
		expect_addr(16'h1234, 19'h19234);
		expect_addr(16'h9234, 19'h21234);
		extended_bank = 8'h8e;
		expect_addr(16'hffff, 19'h7ffff);
		extended_bank = 8'h8f;
		expect_addr(16'h2345, 19'h00345);
		expect_addr(16'hc123, 19'h7c123);
		expect_decode(1, 0, 0, 0, 0, 0);
		expect_ram_select(1);

		// I/O, always-RAM hole, ROM, VIA priority, and write protection.
		extended_active = 1'b0;
		cpu_read        = 1'b1;
		cpu_addr        = 16'hc010;
		expect_decode(0, 0, 0, 1, 0, 0);
		expect_ram_select(0);
		cpu_addr = 16'hc500;
		expect_decode(1, 0, 0, 0, 0, 0);
		expect_ram_select(1);
		cpu_addr = 16'hf123;
		expect_decode(0, 0, 1, 0, 0, 0);
		expect_ram_select(0);
		cpu_addr = 16'hffc5;
		expect_decode(1, 0, 0, 0, 0, 0);
		expect_ram_select(1);
		cpu_addr = 16'hffd0;
		expect_decode(0, 0, 0, 0, 1, 0);
		expect_ram_select(0);
		cpu_addr = 16'hffef;
		expect_decode(0, 0, 0, 0, 0, 1);
		expect_ram_select(0);

		cpu_read = 1'b0;
		cpu_addr = 16'hf123;
		expect_decode(0, 0, 0, 0, 0, 0);
		expect_ram_select(1);
		environment[3] = 1'b0;
		expect_decode(0, 1, 0, 0, 0, 0);
		expect_ram_select(1);

		// In funny mode, the VIA holes reveal the selected ROM/RAM overlay.
		cpu_read    = 1'b1;
		native_mode = 1'b0;
		cpu_addr    = 16'hffd0;
		expect_decode(0, 0, 1, 0, 0, 0);
		expect_ram_select(0);
		environment[0] = 1'b0;
		expect_decode(1, 0, 0, 0, 0, 0);
		expect_ram_select(1);

		// Sister bytes share a word and occupy opposite lanes.
		cpu_addr = 16'h0400;
		#1;
		if (ram_word_addr !== 18'h3c400 || ram_lane !== 1'b0) $fatal(1, "bad $0400 pairing");
		cpu_addr = 16'h0800;
		#1;
		if (ram_word_addr !== 18'h3c400 || ram_lane !== 1'b1) $fatal(1, "bad $0800 pairing");
		checks = checks + 2;

		$display("PASS apple3_mmu (%0d checks)", checks);
		$finish;
	end
endmodule
