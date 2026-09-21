`timescale 1ns / 1ps
module core_timing_tb;
	logic clk = 0, reset = 1;
	logic [10:0] ps2_key = 0;
	wire [15:0] slot_addr, cpu_addr, pc;
	wire [7:0] slot_data_out, cpu_dout;
	wire  [3:0][7:0] slot_data_in = {8'h00, 8'h00, 8'ha5, 8'h5a};
	wire  [3:0]      slot_data_oe = slot_device_select;
	wire  [3:0]      slot_irq_n = 4'hf;
	logic [3:0]      slot_nmi_n = 4'hf;
	wire [3:0] slot_device_select, slot_io_select;
	wire slot_cpu_read, slot_cycle, slot_reset, slot_io_strobe, slot_rom_deselect, slot_bus_conflict;
	wire cpu_enable, cpu_rwn;
	logic [3:0] slot_ready = 4'hf;
	integer cycles = 0, phase = 0, via_edges = 0, via_accesses = 0;
	integer card_reads = 0, card_writes = 0, held_clocks = 0, stalled_ticks = 0;
	integer scan_before;
	logic completed = 0, holding = 0, old_rwn;
	logic [15:0] old_addr;
	logic [63:0] old_regs;
	always #5 clk = ~clk;
	apple3_core #(
		.ROM_INIT_FILE("sim/timing/obj_dir/diagnostic.hex")
	) dut (
		.clk_14m            (clk),
		.reset,
		.ps2_key,
		.plus_keymap        (1'b0),
		.ram_128k           (1'b0),
		.interlace          (1'b0),
		.euro               (1'b0),
		.host_rtc           (65'd0),
		.joy_a_x            (8'd128),
		.joy_a_y            (8'd128),
		.joy_b_x            (8'd128),
		.joy_b_y            (8'd128),
		.joy_a_button       (1'b0),
		.joy_a_switch       (1'b0),
		.joy_b_button       (1'b0),
		.joy_b_switch       (1'b0),
		.slot_data_in,
		.slot_data_oe,
		.slot_irq_n,
		.slot_nmi_n,
		.slot_ready         (slot_ready),
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
	always @(posedge clk) begin
		cycles <= cycles + 1;
		if (cycles > 3000000) $fatal(1, "timeout phase=%0d pc=%04x", phase, pc);
		if (!reset) begin
			if (dut.via_falling && dut.peripheral_select && (dut.via_d_select || dut.via_e_select))
				via_edges = via_edges + 1;
			if (holding) begin
				held_clocks++;
				if (dut.via_falling) stalled_ticks++;
				if (cpu_enable || slot_cycle || dut.debug_ram_write || dut.rtc_read || dut.rtc_write ||
					dut.acia_read || dut.acia_write || dut.disk_strobe)
					$fatal(1, "bus side effect while RDY holds read");
				if (cpu_addr != old_addr || cpu_rwn != old_rwn || dut.cpu_regs != old_regs)
					$fatal(1, "CPU state changed during RDY");
			end
			if (cpu_enable) begin
				if (dut.via_d_select || dut.via_e_select) begin
					if (via_edges != 1) $fatal(1, "VIA %04x had %0d strobes", cpu_addr, via_edges);
					via_accesses++;
				end
				via_edges = 0;
				if (!cpu_rwn && cpu_addr == 16'h0201) phase <= int'(cpu_dout);
				if (!cpu_rwn && cpu_addr == 16'h0200) begin
					if (cpu_dout != 8'h5a) $fatal(1, "diagnostic failed phase=%0d PC=%04x", phase, pc);
					completed <= 1;
				end
				if (slot_device_select[0]) begin
					if (cpu_rwn) card_reads++;
					else begin
						if (slot_ready != 0) $fatal(1, "write did not test low RDY");
						card_writes++;
					end
				end
			end
		end
	end
	// A card may pull down any of the four open-collector RDY pins. Exercise
	// each independently, and also hold RDY across both writes of INC abs.
	initial begin
		repeat (100) @(negedge clk);
		reset = 0;
		for (integer card = 0; card < 4; card++) begin
			wait (slot_cpu_read && slot_device_select[0]);
			@(negedge clk);
			slot_ready = 4'hf ^ (4'b0001 << card);
			holding    = 1;
			old_addr   = cpu_addr;
			old_rwn    = cpu_rwn;
			old_regs   = dut.cpu_regs;
			for (integer count = 0; count < 4500; count++) begin
				@(negedge clk);
				// Pulse NMI wholly inside the first stalled read. T65 must
				// observe it even though no bus transaction is completing.
				if (card == 0 && count == 700) slot_nmi_n[0] = 0;
				if (card == 0 && count == 750) slot_nmi_n[0] = 1;
			end
			holding    = 0;
			slot_ready = 4'hf;
			wait (slot_cycle);
			@(posedge clk);
			@(negedge clk);
		end
		// Leave RDY low during writes; release for reads so the final checks
		// can execute. Any incorrect "stall all cycles" implementation hangs.
		while (!completed) begin
			@(negedge clk);
			slot_ready = cpu_rwn ? 4'hf : 4'h0;
		end
		if (card_reads != 5 || card_writes != 3 || held_clocks != 18000 || stalled_ticks < 1000)
			$fatal(1, "read=%0d write=%0d held=%0d VIA ticks=%0d", card_reads, card_writes, held_clocks, stalled_ticks);
		// Reset must recover even from a card holding every RDY input down,
		// without disturbing the scan chain or waiting for another CPU cycle.
		@(negedge clk);
		slot_ready = 0;
		repeat (30) @(negedge clk);
		if (cpu_enable || !cpu_rwn) $fatal(1, "final read did not stall");
		scan_before = int'(dut.v_count) * 912 + int'(dut.h_count);
		reset       = 1;
		repeat (100) @(negedge clk);
		if (!slot_reset || !dut.cpu_ready) $fatal(1, "reset blocked by card RDY");
		if (int'(dut.v_count) * 912 + int'(dut.h_count) != (scan_before + 100) % (912 * 262))
			$fatal(1, "reset disturbed the scanner");
		reset      = 0;
		slot_ready = 4'hf;
		wait (cpu_addr == 16'hfffc && cpu_enable);
		$display("PASS T65 peripheral alignment (%0d VIA accesses), four RDY inputs, RMW writes, stalled NMI and reset",
				 via_accesses);
		$finish;
	end
endmodule
