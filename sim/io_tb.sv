`timescale 1ns / 1ps

module io_tb;
	logic clk = 0, reset = 1, cycle_strobe = 0, select = 1, cpu_read = 1;
	logic [7:0] addr = 0;
	logic [4:0] rtc_register = 0;
	logic [7:0] key_code = 8'hcb;
	logic key_strobe = 1, any_key_down = 1, shift = 0, control_key = 1;
	logic alpha_lock = 0, open_apple = 1, solid_apple = 0;
	logic [7:0] joy_a_x = 8'h10, joy_a_y = 8'h20, joy_b_x = 8'h30, joy_b_y = 8'h40;
	logic joy_a_button = 0, joy_a_switch = 1, joy_b_button = 0, joy_b_switch = 1;
	logic via_cb1_drive = 0, via_cb1_out = 0, via_cb2_drive = 0, via_cb2_out = 0;
	logic slot1_irq_n = 1, slot2_irq_n = 0;
	logic [7:0] rtc_data = 8'h12, disk_data = 8'ha5, acia_data = 8'h10;
	wire clear_key_strobe, rtc_read, rtc_write, disk_strobe, acia_read, acia_write;
	wire [4:0] rtc_addr;
	wire [7:0] data_out;
	wire [3:0] video_mode;
	wire smooth_scroll, character_write, external_select, serial_enable, speaker;
	wire margin_switch, serial_clock;
	wire [2:0] analog_select;

	apple3_io dut (.*);
	always #5 clk = ~clk;

	task automatic access (input [7:0] a, input rd);
		begin
			addr         = a;
			cpu_read     = rd;
			cycle_strobe = 1;
			@(posedge clk);
			#1;
			cycle_strobe = 0;
		end
	endtask

	initial begin
		repeat (2) @(posedge clk);
		reset = 0;
		addr  = 8'h00;
		#1;
		if (data_out !== 8'hcb) $fatal(1, "KA port=%02x", data_out);
		addr = 8'h08;
		#1;
		if (data_out !== 8'he9) $fatal(1, "KB port=%02x", data_out);
		access (8'h10, 1);
		if (!clear_key_strobe) $fatal(1, "keyboard clear pulse");

		access (8'h51, 1);
		access (8'h53, 0);
		access (8'h55, 1);
		access (8'h57, 0);
		if (video_mode !== 4'hf) $fatal(1, "video switches=%x", video_mode);
		access (8'h50, 0);
		if (video_mode !== 4'he) $fatal(1, "video clear=%x", video_mode);
		access (8'hd9, 1);
		access (8'hdb, 0);
		if (!smooth_scroll || !character_write) $fatal(1, "video aux switches");

		addr = 8'h64;
		#1;
		if (data_out !== 8'h00) $fatal(1, "slot IRQ polarity");
		addr = 8'h60;
		#1;
		if (data_out !== 8'h80) $fatal(1, "joystick switch");

		rtc_register = 5'h17;
		addr         = 8'h70;
		cpu_read     = 1;
		cycle_strobe = 1;
		#1;
		if (!rtc_read || rtc_addr != 5'h17 || data_out != 8'h12) $fatal(1, "RTC decode");
		cycle_strobe = 0;
		addr         = 8'hec;
		cycle_strobe = 1;
		#1;
		if (!disk_strobe || data_out != 8'ha5) $fatal(1, "disk decode");
		cycle_strobe = 0;
		addr         = 8'hf1;
		cycle_strobe = 1;
		#1;
		if (!acia_read || data_out != 8'h10) $fatal(1, "ACIA decode");
		cycle_strobe = 0;
		// The ACIA decodes A0-A1 across all of $C0Fx.
		for (int a = 8'hf4; a <= 8'hff; a++) begin
			addr         = 8'(a);
			cycle_strobe = 1;
			#1;
			if (!acia_read || data_out != 8'h10) $fatal(1, "ACIA mirror %02x read", a);
			cpu_read = 0;
			#1;
			if (!acia_write) $fatal(1, "ACIA mirror %02x write", a);
			cpu_read     = 1;
			cycle_strobe = 0;
		end
		@(negedge clk);  // keep the next clocked access clear of an edge

		access (8'h30, 1);
		if (!speaker) $fatal(1, "speaker toggle");
		$display("PASS apple3_io");
		$finish;
	end
endmodule
