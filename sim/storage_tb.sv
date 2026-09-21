`timescale 1ns / 1ps

module storage_tb;
	logic clk = 0;
	logic [17:0] cpu_addr = 0, video_addr = 0;
	logic cpu_lane = 0, cpu_we = 0;
	logic [7:0] cpu_din = 0;
	wire [15:0] cpu_q, video_q;

	logic reset = 1, cycle_strobe = 0, sync = 0, cpu_read = 1;
	logic [15:0] ext_cpu_addr = 0;
	logic [7:0] zero_page = 0, sister_data = 0, bank_register = 8'hf1;
	wire active;
	wire [7:0] bank, window_bank;

	apple3_ram ram (.*);
	apple3_extaddr ext (
		.clk,
		.reset,
		.cycle_strobe,
		.sync,
		.cpu_read,
		.cpu_addr(ext_cpu_addr),
		.zero_page,
		.bank_register,
		.sister_data,
		.active,
		.bank,
		.window_bank
	);
	always #5 clk = ~clk;

	task automatic pulse_cycle;
		begin
			cycle_strobe = 1;
			@(posedge clk);
			#1;
			cycle_strobe = 0;
		end
	endtask

	initial begin
		repeat (2) @(posedge clk);
		reset = 0;

		// Both lanes of the same paired word retain independent bytes.
		cpu_addr = 18'h01234;
		cpu_lane = 0;
		cpu_din  = 8'h5a;
		cpu_we   = 1;
		@(posedge clk);
		#1;
		cpu_lane = 1;
		cpu_din  = 8'ha5;
		@(posedge clk);
		#1;
		cpu_we = 0;
		repeat (2) @(posedge clk);
		#1;
		if (cpu_q !== 16'ha55a) $fatal(1, "paired CPU RAM read=%04x", cpu_q);
		video_addr = 18'h01234;
		repeat (2) @(posedge clk);
		#1;
		if (video_q !== 16'ha55a) $fatal(1, "video RAM read=%04x", video_q);

		// Only a qualifying zero-page operand fetch captures the X byte.
		zero_page    = 8'h18;
		ext_cpu_addr = 16'h0042;
		sister_data  = 8'hb3;
		pulse_cycle();
		if (!active || bank !== 8'h83) $fatal(1, "extended capture=%02x/%b", bank, active);
		ext_cpu_addr = 16'h3456;
		sister_data  = 8'h00;
		pulse_cycle();
		if (!active || bank !== 8'h83) $fatal(1, "extended latch did not persist");
		sync         = 1;
		ext_cpu_addr = 16'hf000;
		#1;
		if (active || bank !== 8'h00) $fatal(1, "SYNC opcode fetch remained extended");
		pulse_cycle();
		if (active || bank !== 8'h00) $fatal(1, "SYNC did not clear extended latch");

		zero_page    = 8'h17;
		sync         = 0;
		ext_cpu_addr = 16'h0010;
		sister_data  = 8'h8a;
		pulse_cycle();
		if (active) $fatal(1, "non-extended ZP captured an X byte");

		// A9 is a register clocked at the end of a read: a store to the bank
		// register reaches the map only after the next read, so the opcode
		// fetch that follows it still sees the old bank.
		if (window_bank !== 8'h01) $fatal(1, "bank latch=%02x after a read", window_bank);
		bank_register = 8'hf2;
		cpu_read      = 0;
		ext_cpu_addr  = 16'hffef;
		pulse_cycle();
		if (window_bank !== 8'h01) $fatal(1, "a write clocked the bank latch");
		cpu_read     = 1;
		sync         = 1;
		ext_cpu_addr = 16'h3005;
		#1;
		if (window_bank !== 8'h01) $fatal(1, "opcode fetch after the store saw bank %02x", window_bank);
		pulse_cycle();
		sync         = 0;
		ext_cpu_addr = 16'h3006;
		#1;
		if (window_bank !== 8'h02) $fatal(1, "operand fetch saw bank %02x", window_bank);

		// An opcode fetched from a zero page of $18-$1F latches its X byte like
		// any other zero-page read, and a redirected cycle leaves it alone.
		zero_page    = 8'h1a;
		sync         = 1;
		ext_cpu_addr = 16'h00ff;
		sister_data  = 8'h81;
		pulse_cycle();
		sync         = 0;
		ext_cpu_addr = 16'h0100;
		sister_data  = 8'h00;
		#1;
		if (!active || bank !== 8'h81 || window_bank !== 8'h01) $fatal(1, "opcode fetch X byte=%02x/%b", bank, active);
		pulse_cycle();
		if (!active) $fatal(1, "a redirected read clocked the latch");
		// A zero-page read with bit 7 clear returns the latch to the bank register.
		ext_cpu_addr = 16'h0020;
		pulse_cycle();
		if (active || window_bank !== 8'h02) $fatal(1, "X byte without bit 7 kept the latch: %02x", window_bank);
		// Ending at SYNC reloads the live bank register, with no lag.
		sister_data = 8'h83;
		pulse_cycle();
		bank_register = 8'hf4;
		sync          = 1;
		ext_cpu_addr  = 16'h4000;
		#1;
		if (active || window_bank !== 8'h04) $fatal(1, "SYNC reload gave %02x", window_bank);
		sync = 0;

		$display("PASS apple3 storage and extended addressing");
		$finish;
	end
endmodule
