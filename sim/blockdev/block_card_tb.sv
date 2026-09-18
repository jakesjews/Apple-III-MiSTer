// Register-level test of the block card with a modelled host and slot bus.
`timescale 1ns / 1ps
module block_card_tb;
	logic clk = 0;
	always #5 clk = ~clk;
	logic reset = 1, cycle = 0, cpu_read = 1, device_select = 0, io_select = 0;
	logic [15:0] addr = 0;
	logic [ 7:0] data_in = 0;
	wire  [ 7:0] data_out;
	wire data_oe, ready, activity;
	logic [ 1:0] image_change = 0;
	logic [63:0] image_size = 0;
	logic        image_readonly = 0;
	wire  [31:0] sd_lba;
	wire [1:0] sd_rd, sd_wr;
	logic [1:0] sd_ack = 0;
	logic [8:0] sd_buff_addr = 0;
	logic [7:0] sd_buff_dout = 0;
	wire  [7:0] sd_buff_din;
	logic       sd_buff_wr = 0;
	apple3_block_card dut (
		.addr(addr[7:0]),
		.*
	);

	// Host images: drive 1 has eight blocks, drive 2 four.
	logic [7:0] image0[8*512], image1[4*512], firmware[256];
	integer host_latency = 20, host_transfers = 0, last_lba = -1, last_unit = -1;
	integer waited, execute_wait, checks = 0;
	logic [7:0] value;
	logic       host_pause = 0;

	initial begin
		for (int i = 0; i < 8 * 512; i++) image0[i] = 8'(i * 7 + (i >> 9));
		for (int i = 0; i < 4 * 512; i++) image1[i] = 8'(i * 3 + 5);
		$readmemh("rtl/cards/apple3_block_firmware.hex", firmware);
	end

	// Host model: acknowledges one request at a time after a latency, then
	// moves 512 bytes at four clocks per byte, as hps_io does over SPI.
	always begin
		integer unit;
		@(negedge clk);
		if (!host_pause && (sd_rd | sd_wr)) begin
			unit      = sd_rd[1] | sd_wr[1];
			last_unit = unit;
			last_lba  = sd_lba;
			repeat (host_latency) @(negedge clk);
			sd_ack[unit] = 1;
			repeat (4) @(negedge clk);
			for (int i = 0; i < 512; i++) begin
				sd_buff_addr = i[8:0];
				if (sd_rd[unit] || dut.state == 2 && dut.command == 1) begin
					sd_buff_dout = unit ? (sd_lba * 512 + i < 4 * 512 ? image1[sd_lba*512+i] : 8'h00) :
						(sd_lba * 512 + i < 8 * 512 ? image0[sd_lba*512+i] : 8'h00);
					repeat (3) @(negedge clk);
					sd_buff_wr = 1;
					@(negedge clk);
					sd_buff_wr = 0;
				end else begin
					repeat (4) @(negedge clk);
					if (sd_lba * 512 + i < (unit ? 4 * 512 : 8 * 512)) begin
						if (unit) image1[sd_lba*512+i] = sd_buff_din;
						else image0[sd_lba*512+i] = sd_buff_din;
					end
				end
			end
			repeat (4) @(negedge clk);
			sd_ack[unit] = 0;
			host_transfers++;
		end
	end

	task automatic bus_read(input logic [15:0] a, output logic [7:0] d);
		@(negedge clk);
		addr          = a;
		cpu_read      = 1;
		device_select = (a[15:4] == 12'hc09);
		io_select     = (a[15:8] == 8'hc1);
		waited        = 0;
		repeat (3) @(negedge clk);
		// The core completes no cycle while RDY is low or during reset.
		while (!ready || reset) begin
			waited++;
			if (cycle) $fatal(1, "cycle while RDY low");
			@(negedge clk);
		end
		cycle = 1;
		#1;
		if (!data_oe) $fatal(1, "read of %04x has no data enable", a);
		d = data_out;
		@(negedge clk);
		cycle         = 0;
		device_select = 0;
		io_select     = 0;
	endtask

	task automatic bus_write(input logic [15:0] a, input logic [7:0] d);
		@(negedge clk);
		addr          = a;
		data_in       = d;
		cpu_read      = 0;
		device_select = (a[15:4] == 12'hc09);
		io_select     = (a[15:8] == 8'hc1);
		repeat (3) @(negedge clk);
		if (!ready) $fatal(1, "write of %04x held by RDY", a);
		if (data_oe) $fatal(1, "write drives data");
		cycle = 1;
		@(negedge clk);
		cycle         = 0;
		device_select = 0;
		io_select     = 0;
		cpu_read      = 1;
	endtask

	task automatic expect_read(input logic [15:0] a, input logic [7:0] want, input string what);
		logic [7:0] got;
		bus_read(a, got);
		checks++;
		if (got !== want) $fatal(1, "%s: %04x read %02x, expected %02x", what, a, got, want);
	endtask

	task automatic command(input logic [7:0] cmd, input logic [7:0] unit, input logic [15:0] block,
						   input logic [7:0] want, input string what);
		bus_write(16'hc092, cmd);
		bus_write(16'hc093, unit);
		bus_write(16'hc094, block[7:0]);
		bus_write(16'hc095, block[15:8]);
		expect_read(16'hc090, want, what);
		execute_wait = waited;
		expect_read(16'hc091, want, {what, " error register"});
	endtask

	task automatic mount(input integer unit, input logic [63:0] size, input logic protect);
		@(negedge clk);
		image_size     = size;
		image_readonly = protect;
		image_change   = 2'b01 << unit;
		@(negedge clk);
		image_change = 0;
		image_size   = 0;
	endtask

	initial begin
		repeat (10) @(negedge clk);
		if (!ready || data_oe) $fatal(1, "card must release RDY and the bus in reset");
		reset = 0;
		repeat (10) @(negedge clk);

		// Firmware: signature, entry offset and the whole image.
		expect_read(16'hc101, 8'h20, "signature");
		expect_read(16'hc103, 8'h00, "signature");
		expect_read(16'hc105, 8'h03, "signature");
		expect_read(16'hc107, 8'h3c, "signature");
		expect_read(16'hc1fe, 8'hd7, "status byte");
		for (int i = 0; i < 256; i++) expect_read(16'hc100 + 16'(i), firmware[i], "firmware byte");
		if (firmware[255] == 8'h00 || firmware[255] == 8'hff) $fatal(1, "entry offset looks like a Disk II");

		// Nothing mounted: every command reports no device.
		command(8'h00, 8'h10, 16'd0, 8'h28, "status without image");
		command(8'h01, 8'h10, 16'd0, 8'h28, "read without image");
		command(8'h00, 8'h90, 16'd0, 8'h28, "status without second image");
		if (host_transfers != 0) $fatal(1, "host request without an image");

		mount(0, 64'd8 * 512, 0);
		mount(1, 64'd4 * 512, 1);
		command(8'h00, 8'h10, 16'd0, 8'h00, "status drive 1");
		expect_read(16'hc096, 8'h08, "drive 1 block count");
		expect_read(16'hc097, 8'h00, "drive 1 block count");
		command(8'h00, 8'h90, 16'd0, 8'h00, "status drive 2");
		expect_read(16'hc096, 8'h04, "drive 2 block count");
		expect_read(16'hc097, 8'h00, "drive 2 block count");

		// Read block 3 of drive 1: RDY holds the CPU through the host latency.
		command(8'h01, 8'h10, 16'd3, 8'h00, "read block 3");
		if (execute_wait < host_latency) $fatal(1, "execute read waited only %0d clocks", execute_wait);
		if (last_lba != 3 || last_unit != 0 || host_transfers != 1) $fatal(1, "wrong host request");
		for (int i = 0; i < 512; i++) expect_read(16'hc098, image0[3*512+i], "block 3 data");
		expect_read(16'hc098, image0[3*512], "pointer wraps after 512 bytes");
		// Writing the command register rewinds the pointer.
		bus_write(16'hc092, 8'h01);
		expect_read(16'hc098, image0[3*512], "rewound pointer");
		expect_read(16'hc098, image0[3*512+1], "rewound pointer");

		// Write block 5 of drive 1, then read it back through the host.
		bus_write(16'hc092, 8'h02);
		for (int i = 0; i < 512; i++) bus_write(16'hc099, 8'(i ^ 8'h5a));
		bus_write(16'hc093, 8'h10);
		bus_write(16'hc094, 8'd5);
		bus_write(16'hc095, 8'd0);
		expect_read(16'hc090, 8'h00, "write block 5");
		if (waited < host_latency || last_lba != 5 || host_transfers != 2) $fatal(1, "write request wrong");
		for (int i = 0; i < 512; i++)
		if (image0[5*512+i] !== 8'(i ^ 8'h5a)) $fatal(1, "host image byte %0d is %02x", i, image0[5*512+i]);
		command(8'h01, 8'h10, 16'd5, 8'h00, "read block 5");
		for (int i = 0; i < 512; i++) expect_read(16'hc098, 8'(i ^ 8'h5a), "block 5 data");

		// Errors: protection, range, unknown command, the other drive.
		command(8'h02, 8'h90, 16'd1, 8'h2b, "write to protected drive 2");
		command(8'h01, 8'h90, 16'd3, 8'h00, "read block 3 of drive 2");
		if (last_unit != 1 || last_lba != 3) $fatal(1, "drive 2 request wrong");
		for (int i = 0; i < 512; i++) expect_read(16'hc098, image1[3*512+i], "drive 2 data");
		command(8'h01, 8'h90, 16'd4, 8'h27, "read past drive 2");
		command(8'h01, 8'h10, 16'd8, 8'h27, "read past drive 1");
		command(8'h02, 8'h10, 16'd8, 8'h27, "write past drive 1");
		command(8'h03, 8'h10, 16'd0, 8'h00, "format drive 1");
		command(8'h03, 8'h90, 16'd0, 8'h2b, "format protected drive 2");
		command(8'h07, 8'h10, 16'd0, 8'h27, "unknown command");
		if (host_transfers != 4) $fatal(1, "errors must not reach the host");

		// A reset during a transfer releases RDY, drops the request and clears
		// the registers, so the interrupted read completes as a status call. A
		// new command then waits for the abandoned transfer before requesting.
		fork
			command(8'h01, 8'h10, 16'd2, 8'h00, "read interrupted by reset");
			begin
				wait (sd_ack[0]);
				repeat (100) @(negedge clk);
				if (ready || dut.state != 2) $fatal(1, "transfer not in progress before reset");
				reset = 1;
				#1;
				if (!ready) $fatal(1, "reset must release RDY");
				@(negedge clk);
				if (sd_rd != 0 || dut.state != 0) $fatal(1, "reset must drop the request");
				repeat (5) @(negedge clk);
				reset = 0;
			end
		join
		if (!sd_ack[0]) $fatal(1, "the abandoned transfer should still be running");
		command(8'h01, 8'h10, 16'd2, 8'h00, "read after reset");
		if (host_transfers != 6) $fatal(1, "expected the abandoned and the new transfer, got %0d", host_transfers);
		for (int i = 0; i < 512; i++) expect_read(16'hc098, image0[2*512+i], "block 2 data after reset");
		host_latency = 20;

		// Capacity caps at 65,535 blocks; unmounting reports no device again.
		mount(1, 64'h4000000, 0);
		command(8'h00, 8'h90, 16'd0, 8'h00, "status of a 64 MiB image");
		expect_read(16'hc096, 8'hff, "capped block count");
		expect_read(16'hc097, 8'hff, "capped block count");
		command(8'h01, 8'h90, 16'hfffe, 8'h00, "read block 65534");
		if (last_lba != 65534) $fatal(1, "lba %0d", last_lba);
		command(8'h01, 8'h90, 16'hffff, 8'h27, "read block 65535");
		mount(1, 64'd0, 0);
		command(8'h00, 8'h90, 16'd0, 8'h28, "status after unmount");
		command(8'h00, 8'h10, 16'd0, 8'h00, "drive 1 still mounted");

		// Undriven offsets read $FF; writes to read-only offsets change nothing.
		bus_write(16'hc090, 8'h55);
		bus_write(16'hc091, 8'h55);
		bus_write(16'hc096, 8'h55);
		expect_read(16'hc096, 8'h08, "block count is read-only");
		expect_read(16'hc09a, 8'hff, "undriven register");
		expect_read(16'hc09f, 8'hff, "undriven register");
		if (activity) $fatal(1, "activity stuck");
		$display("PASS block card registers, firmware image, transfers, errors, reset and capacity (%0d checks)",
				 checks);
		$finish;
	end

	initial begin
		#20000000;
		$fatal(1, "timeout");
	end
endmodule
