// Boot the block-card diagnostic on the real T65, MMU and card bus with the
// card in slot 1 and a modelled host serving two images.
`timescale 1ns / 1ps
module core_block_tb;
	logic clk = 0, reset = 1;
	logic [10:0] ps2_key = 0;
	wire [15:0] slot_addr, cpu_addr, pc;
	wire [7:0] slot_data_out, cpu_dout, card_data;
	wire [3:0] slot_device_select, slot_io_select;
	wire card_oe, card_ready, card_activity;
	wire slot_cpu_read, slot_cycle, slot_reset, slot_io_strobe, slot_rom_deselect, slot_bus_conflict;
	wire cpu_enable, cpu_rwn;
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
	integer phase = 0, cycles = 0, host_transfers = 0, held = 0, longest_hold = 0;
	logic completed = 0;
	always #5 clk = ~clk;

	apple3_core #(
		.ROM_INIT_FILE("sim/blockdev/obj_dir/diagnostic.hex")
	) dut (
		.clk_14m            (clk),
		.reset,
		.ps2_key,
		.plus_keymap        (1'b0),
		.ram_128k           (1'b0),
		.interlace          (1'b0),
		.host_rtc           (65'd0),
		.joy_a_x            (8'd128),
		.joy_a_y            (8'd128),
		.joy_b_x            (8'd128),
		.joy_b_y            (8'd128),
		.joy_a_button       (1'b0),
		.joy_a_switch       (1'b0),
		.joy_b_button       (1'b0),
		.joy_b_switch       (1'b0),
		.slot_data_in       ({24'hffffff, card_data}),
		.slot_data_oe       ({3'b000, card_oe}),
		.slot_irq_n         (4'b1111),
		.slot_nmi_n         (4'b1111),
		.slot_ready         ({3'b111, card_ready}),
		.slot_addr,
		.slot_data_out,
		.slot_cpu_read,
		.slot_cycle,
		.slot_reset,
		.slot_device_select,
		.slot_io_select,
		.slot_io_strobe,
		.slot_rom_deselect,
		.slot_bus_conflict,
		.serial_rx          (1'b1),
		.serial_cts_n       (1'b0),
		.serial_dsr_n       (1'b0),
		.serial_tx          (),
		.serial_rts_n       (),
		.serial_dtr_n       (),
		.rom_we             (1'b0),
		.rom_host_addr      (13'd0),
		.rom_host_data      (8'd0),
		.disk_ready         (4'd0),
		.disk_write_protect (4'hf),
		.disk_flux          (4'd0),
		.disk_media_change  (4'd0),
		.disk_phases        (),
		.disk_write_mode    (),
		.disk_write_bit     (),
		.disk_write_strobe  (),
		.disk_motors        (),
		.video_r            (),
		.video_g            (),
		.video_b            (),
		.video_hblank       (),
		.video_vblank       (),
		.video_hsync        (),
		.video_vsync        (),
		.audio              (),
		.disk_activity      (),
		.disk_active        (),
		.debug_pc           (pc),
		.debug_cpu_addr     (cpu_addr),
		.debug_cpu_enable   (cpu_enable),
		.debug_cpu_rwn      (cpu_rwn),
		.debug_cpu_dout     (cpu_dout),
		.debug_environment  (),
		.debug_zero_page    (),
		.debug_bank         (),
		.debug_video_mode   (),
		.debug_cpu_sync     (),
		.debug_cpu_din      (),
		.debug_e_pa_o       (),
		.debug_e_pa_ddr     (),
		.debug_a            (),
		.debug_x            (),
		.debug_y            (),
		.debug_sp           (),
		.debug_p            (),
		.debug_ram_byte_addr(),
		.debug_ram_write    ()
	);

	apple3_block_card card (
		.clk,
		.reset        (slot_reset),
		.cycle        (slot_cycle),
		.addr         (slot_addr[7:0]),
		.cpu_read     (slot_cpu_read),
		.data_in      (slot_data_out),
		.device_select(slot_device_select[0]),
		.io_select    (slot_io_select[0]),
		.data_out     (card_data),
		.data_oe      (card_oe),
		.ready        (card_ready),
		.activity     (card_activity),
		.image_change,
		.image_size,
		.image_readonly,
		.sd_lba,
		.sd_rd,
		.sd_wr,
		.sd_ack,
		.sd_buff_addr,
		.sd_buff_dout,
		.sd_buff_din,
		.sd_buff_wr
	);

	// Drive 1: 40 blocks, byte i of block b = b * 17 + i * 3. Drive 2: 24
	// blocks, byte i of block b = b * 5 + i, mounted read-only.
	logic [7:0] image0[40*512], image1[24*512];
	initial begin
		for (int b = 0; b < 40; b++) for (int i = 0; i < 512; i++) image0[b*512+i] = 8'(b * 17 + i * 3);
		for (int b = 0; b < 24; b++) for (int i = 0; i < 512; i++) image1[b*512+i] = 8'(b * 5 + i);
	end

	// Host model with 5,000 clocks of latency per request and four clocks
	// per byte, roughly MiSTer's SD path.
	always begin
		integer unit, base;
		logic read;
		@(negedge clk);
		if (sd_rd | sd_wr) begin
			unit = sd_rd[1] | sd_wr[1];
			read = sd_rd[unit];
			base = sd_lba * 512;
			repeat (5000) @(negedge clk);
			sd_ack[unit] = 1;
			repeat (4) @(negedge clk);
			for (int i = 0; i < 512; i++) begin
				sd_buff_addr = i[8:0];
				if (read) begin
					if (unit) sd_buff_dout = base + i < 24 * 512 ? image1[base+i] : 8'h00;
					else sd_buff_dout = base + i < 40 * 512 ? image0[base+i] : 8'h00;
					repeat (3) @(negedge clk);
					sd_buff_wr = 1;
					@(negedge clk);
					sd_buff_wr = 0;
				end else begin
					repeat (4) @(negedge clk);
					if (unit && base + i < 24 * 512) image1[base+i] = sd_buff_din;
					if (!unit && base + i < 40 * 512) image0[base+i] = sd_buff_din;
				end
			end
			repeat (4) @(negedge clk);
			sd_ack[unit] = 0;
			host_transfers++;
		end
	end

	always @(posedge clk) begin
		cycles <= cycles + 1;
		if (slot_bus_conflict) $fatal(1, "bus contention at PC %04x", pc);
		if (!card_ready) begin
			held++;
			if (held > longest_hold) longest_hold = held;
			if (slot_cycle) $fatal(1, "completion while the card holds RDY");
		end else held = 0;
		if (cpu_enable && !cpu_rwn && !dut.machine_reset) begin
			if (cpu_addr == 16'h0201) begin
				phase <= int'(cpu_dout);
				$display("block diagnostic phase %0d at %0d clocks", cpu_dout, cycles);
			end
			if (cpu_addr == 16'h0202) begin
				case (cpu_dout)
					8'd4: begin
						// The write of block 5 must already be in the host image.
						for (int i = 0; i < 256; i++) begin
							if (image0[5*512+i] != 8'(i ^ 8'h5a) || image0[5*512+256+i] != 8'(i ^ 8'ha5))
								$fatal(1, "host block 5 byte %0d not written", i);
						end
					end
					8'd6: begin
						image_size   <= 64'd0;
						image_change <= 2'b10;
					end
					default: $fatal(1, "unknown bench request %0d", cpu_dout);
				endcase
			end
			if (cpu_addr == 16'h0200) begin
				if (cpu_dout != 8'h5a) $fatal(1, "diagnostic failed in phase %0d at PC %04x", phase, pc);
				completed <= 1;
			end
		end else if (image_change != 0) image_change <= 0;
		if (cycles > 3000000) $fatal(1, "timeout phase=%0d PC=%04x", phase, pc);
	end

	initial begin
		// Mount both images while the machine is still in reset.
		repeat (10) @(negedge clk);
		image_size     = 64'd40 * 512;
		image_readonly = 0;
		image_change   = 2'b01;
		@(negedge clk);
		image_change = 0;
		@(negedge clk);
		image_size     = 64'd24 * 512;
		image_readonly = 1;
		image_change   = 2'b10;
		@(negedge clk);
		image_change = 0;
		image_size   = 0;
		repeat (100) @(negedge clk);
		reset = 0;
		wait (completed != 0);
		// Three reads and one write of drive 1, one read of drive 2; errors
		// never reach the host.
		if (host_transfers != 5) $fatal(1, "expected 5 host transfers, saw %0d", host_transfers);
		if (longest_hold < 5000) $fatal(1, "RDY held the CPU for only %0d clocks", longest_hold);
		$display("PASS real CPU block-card firmware: signature scan, status, reads, writes, errors,",
				 " bank-switched buffers (%0d clocks, %0d host transfers, longest RDY hold %0d)", cycles,
				 host_transfers, longest_hold);
		$finish;
	end
endmodule
