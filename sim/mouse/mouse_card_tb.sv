// Mouse card bench: the card's bus side driven as SOS's mouse driver drives
// it ("Apple /// RAT Driver", rls 11/85), with the 68705 running its own
// program.
`timescale 1ns / 1ps
module mouse_card_tb;
	logic       clk = 1'b0;
	logic       reset = 1'b1;
	logic       cycle = 1'b0;
	logic [7:0] addr = 8'h00;
	logic       cpu_read = 1'b1;
	logic [7:0] data_in = 8'h00;
	logic       device_select = 1'b0;
	logic       io_select = 1'b0;
	wire  [7:0] data_out;
	wire data_oe, irq_n;
	logic [24:0] ps2_mouse = 25'd0;
	logic [ 1:0] speed = 2'd3;
	logic [ 7:0] eprom             [2048];
	int          failures = 0;

	always #35 clk = !clk;

	apple3_mouse_card card (
		.clk,
		.reset,
		.cycle,
		.addr,
		.cpu_read,
		.data_in,
		.device_select,
		.io_select,
		.data_out,
		.data_oe,
		.irq_n,
		.ps2_mouse,
		.speed
	);

	task automatic check(input logic ok, input string what);
		if (!ok) begin
			$display("FAIL: %s", what);
			failures++;
		end
	endtask

	// One 1 MHz CPU cycle: the selects hold for the cycle and the card
	// commits on its last clock, as apple3_core's slot bus does. A single
	// process runs the cycles; Verilator inlines a task at every call, and
	// the bench makes thousands of them.
	event bus_request, bus_complete;
	logic bus_device, bus_is_read;
	logic [7:0] bus_addr, bus_data, bus_q;
	always begin
		@(bus_request);
		addr          = bus_addr;
		cpu_read      = bus_is_read;
		data_in       = bus_data;
		device_select = bus_device;
		io_select     = !bus_device;
		repeat (13) @(posedge clk);
		cycle = 1'b1;
		bus_q = data_out;
		if (bus_is_read && !reset) check(data_oe, "the card drives a read");
		@(posedge clk);
		cycle         = 1'b0;
		device_select = 1'b0;
		io_select     = 1'b0;
		->bus_complete;
	end

	task automatic bus(input logic device, input logic read, input logic [7:0] a, input logic [7:0] d,
					   output logic [7:0] q);
		bus_device  = device;
		bus_is_read = read;
		bus_addr    = a;
		bus_data    = d;
		->bus_request;
		@(bus_complete);
		q = bus_q;
	endtask

	task automatic pia_write(input logic [1:0] r, input logic [7:0] d);
		logic [7:0] q;
		bus(1'b1, 1'b0, {6'd0, r}, d, q);
	endtask

	task automatic pia_read(input logic [1:0] r, output logic [7:0] q);
		bus(1'b1, 1'b1, {6'd0, r}, 8'h00, q);
	endtask

	task automatic rom_read(input logic [7:0] a, output logic [7:0] q);
		bus(1'b0, 1'b1, a, 8'h00, q);
	endtask

	// Poll port B until the masked bits match, as the driver's wait loops do.
	task automatic wait_port_b(input logic [7:0] mask, input logic [7:0] value, input string what);
		logic [7:0] q;
		int         polls;
		polls = 0;
		do begin
			pia_read(2'd2, q);
			polls++;
		end while (((q & mask) != value) && (polls < 200000));
		check((q & mask) == value, what);
	endtask

	// InitB: PB1-PB5 are outputs.
	task automatic init_port_b();
		logic [7:0] q;
		pia_read(2'd3, q);
		pia_write(2'd3, q & 8'hfb);
		pia_write(2'd2, 8'h3e);
		pia_read(2'd3, q);
		pia_write(2'd3, q | 8'h04);
	endtask

	// The first half of GetRDat: port A to inputs.
	task automatic port_a_in();
		logic [7:0] q;
		pia_read(2'd1, q);
		pia_write(2'd1, q & 8'hfb);
		pia_write(2'd0, 8'h00);
		pia_read(2'd1, q);
		pia_write(2'd1, q | 8'h04);
	endtask

	// SndRDat and GetRDat: one byte to the 68705, or one from it. These too
	// run in a single process.
	event byte_request, byte_complete;
	logic       byte_is_send;
	logic [7:0] byte_value;
	always begin
		logic [7:0] q;
		@(byte_request);
		if (byte_is_send) begin
			wait_port_b(8'h80, 8'h00, "PB7 low before a send");
			pia_read(2'd1, q);
			pia_write(2'd1, q & 8'hfb);
			pia_write(2'd0, 8'hff);
			pia_read(2'd1, q);
			pia_write(2'd1, q | 8'h04);
			pia_write(2'd0, byte_value);
			pia_read(2'd2, q);
			pia_write(2'd2, q | 8'h20);
			wait_port_b(8'h80, 8'h80, "PB7 high after PB5");
			pia_read(2'd2, q);
			pia_write(2'd2, q & 8'hdf);
		end else begin
			port_a_in();
			wait_port_b(8'h40, 8'h40, "PB6 high with a byte");
			pia_read(2'd0, byte_value);
			pia_read(2'd2, q);
			pia_write(2'd2, q | 8'h10);
			wait_port_b(8'h40, 8'h00, "PB6 low after PB4");
			pia_read(2'd2, q);
			pia_write(2'd2, q & 8'hef);
		end
		->byte_complete;
	end

	task automatic send(input logic [7:0] value);
		byte_is_send = 1'b1;
		byte_value   = value;
		->byte_request;
		@(byte_complete);
	endtask

	task automatic receive(output logic [7:0] value);
		byte_is_send = 1'b0;
		->byte_request;
		@(byte_complete);
		value = byte_value;
	endtask

	task automatic read_mouse(output logic [15:0] x, output logic [15:0] y, output logic [7:0] status);
		send(8'h10);
		receive(x[7:0]);
		receive(x[15:8]);
		receive(y[7:0]);
		receive(y[15:8]);
		receive(status);
	endtask

	task automatic serve(output logic [7:0] cause);
		send(8'h20);
		receive(cause);
	endtask

	// A host mouse report; Y counts upward.
	task automatic move(input int dx, input int dy, input logic button);
		ps2_mouse = {!ps2_mouse[24], 8'(dy), 8'(dx), 2'b00, dy < 0, dx < 0, 3'b100, button};
		repeat (4) @(posedge clk);
	endtask

	task automatic settle();
		wait ((card.backlog_x == 0) && (card.backlog_y == 0));
		repeat (14 * 2000) @(posedge clk);
	endtask

	task automatic expect_mouse(input int want_x, input int want_y, input logic [7:0] want_status, input string what);
		logic [15:0] x, y;
		logic [7:0] status;
		read_mouse(x, y, status);
		if ((x != 16'(want_x)) || (y != 16'(want_y)) || (status != want_status)) begin
			$display("FAIL: %s: x=%0d y=%0d status=%02x, expected %0d %0d %02x", what, x, y, status, want_x, want_y,
					 want_status);
			failures++;
		end
	endtask

	task automatic driver();
		logic [7:0] q;
		time first, second;

		$readmemh("rtl/cards/apple3_mouse_eprom.hex", eprom);
		// Let the bus process reach its first wait before asking it for a cycle.
		repeat (4) @(posedge clk);
		rom_read(8'h00, q);
		check(!data_oe, "a card in reset leaves the bus alone");
		check(irq_n, "a card in reset requests no interrupt");
		repeat (16) @(posedge clk);
		reset = 1'b0;
		repeat (64) @(posedge clk);

		// DevInit: the two bytes the driver takes for a mouse card.
		rom_read(8'h0c, q);
		check(q == 8'h20, "firmware signature $Cn0C = $20");
		rom_read(8'hfb, q);
		check(q == 8'hd6, "firmware signature $CnFB = $D6");
		check(irq_n, "no interrupt request out of reset");

		// PB1-PB3 are the EPROM's page, and PB0 reads low.
		init_port_b();
		for (int page = 0; page < 8; page++) begin
			pia_write(2'd2, 8'(page << 1));
			rom_read(8'h13, q);
			check(q == eprom[page*256+8'h13], "EPROM page follows PB1-PB3");
		end
		pia_write(2'd2, 8'h00);
		pia_read(2'd2, q);
		check(q[0] == 1'b0, "PB0 reads low");

		// InitRat: interrupt period, clamps 0..1023, the two-part init call.
		send(8'ha0);
		send(8'h01);
		send(8'h60);
		send(8'h00);
		send(8'hff);
		send(8'h00);
		send(8'h03);
		send(8'h61);
		send(8'h00);
		send(8'hff);
		send(8'h00);
		send(8'h03);
		send(8'h50);
		receive(q);
		send(8'h50);

		// Mouse on, no interrupts; clear the position.
		send(8'h01);
		send(8'h30);
		expect_mouse(0, 0, 8'h00, "cleared");

		// One count for each unit, right and down positive.
		move(100, -50, 1'b0);
		settle();
		expect_mouse(100, 50, 8'h20, "right and down");
		expect_mouse(100, 50, 8'h00, "moved flag clears with the read");
		move(-30, 20, 1'b0);
		settle();
		expect_mouse(70, 30, 8'h20, "left and up");
		move(1, 0, 1'b0);
		settle();
		move(-1, 0, 1'b0);
		settle();
		move(-1, 0, 1'b0);
		settle();
		expect_mouse(69, 30, 8'h20, "single counts through a reversal");

		// An eighth of the host's movement, with the remainder carried: 20 and
		// 4 make three counts, and the same back again.
		speed = 2'd0;
		move(20, 0, 1'b0);
		settle();
		expect_mouse(71, 30, 8'h20, "two counts of twenty eighths");
		move(4, 0, 1'b0);
		settle();
		expect_mouse(72, 30, 8'h20, "the remainder carried");
		move(-24, 0, 1'b0);
		settle();
		expect_mouse(69, 30, 8'h20, "and back");
		speed = 2'd3;

		// The clamps hold, and the button's two bits follow it.
		move(-200, 0, 1'b1);
		settle();
		expect_mouse(0, 30, 8'ha0, "clamped at the left edge, button down");
		expect_mouse(0, 30, 8'hc0, "button still down");
		move(0, 0, 1'b0);
		settle();
		expect_mouse(0, 30, 8'h40, "button up, down at the last read");
		expect_mouse(0, 30, 8'h00, "button up");

		// Position and home.
		send(8'h40);
		send(8'h2c);
		send(8'h01);
		send(8'hc8);
		send(8'h00);
		expect_mouse(300, 200, 8'h00, "position set");
		send(8'h70);
		expect_mouse(0, 0, 8'h00, "home");

		// A request every sixtieth of a second, held until it is served.
		send(8'h09);
		wait (!irq_n);
		first = $time;
		serve(q);
		check(q == 8'h08 && irq_n, "serve reports the timer and releases IRQ");
		wait (!irq_n);
		second = $time;
		serve(q);
		check((second - first) > 16_400_000 && (second - first) < 16_900_000, "requests 1/60 s apart");

		// Movement and button requests come with the next sixtieth.
		send(8'h03);
		repeat (14 * 40000) @(posedge clk);
		check(irq_n, "no request while the mouse is still");
		move(5, 0, 1'b0);
		wait (!irq_n);
		serve(q);
		check(q == 8'h02 && irq_n, "movement request");
		send(8'h05);
		move(0, 0, 1'b1);
		wait (!irq_n);
		serve(q);
		check(q == 8'h04 && irq_n, "button request");
		move(0, 0, 1'b0);
		settle();

		// Nothing is lost while the program is busy with commands and
		// requests: every mode bit on and reads back to back.
		send(8'h30);
		send(8'h0f);
		for (int i = 0; i < 6; i++) begin
			logic [15:0] x, y;
			logic [7:0] status;
			move(90, -60, 1'b0);
			do begin
				read_mouse(x, y, status);
				if (!irq_n) serve(q);
			end while ((card.backlog_x != 0) || (card.backlog_y != 0));
		end
		settle();
		if (!irq_n) serve(q);
		send(8'h01);
		expect_mouse(540, 360, 8'h20, "every count kept under load");

		// Reset releases a pending request.
		send(8'h09);
		wait (!irq_n);
		reset = 1'b1;
		repeat (16) @(posedge clk);
		check(irq_n, "reset releases IRQ");
	endtask

	initial begin
		driver();
		if (failures == 0) $display("mouse_card_tb: PASS");
		else $display("mouse_card_tb: %0d FAILURES", failures);
		$finish;
	end

	initial begin
		#2_000_000_000;
		$display("FAIL: mouse_card_tb timed out");
		$finish;
	end
endmodule
