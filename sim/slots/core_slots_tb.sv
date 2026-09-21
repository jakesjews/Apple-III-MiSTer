`timescale 1ns / 1ps
module core_slots_tb;
	logic clk = 0, reset = 1, resume_test = 0;
	logic [10:0] ps2_key = 0;
	wire [15:0] slot_addr, cpu_addr, pc;
	wire [7:0] slot_data_out, cpu_dout;
	wire [3:0][7:0] card_data;
	wire [3:0] slot_data_oe, slot_irq_n, slot_nmi_n, slot_device_select, slot_io_select, selected;
	wire slot_cpu_read, slot_cycle, slot_reset, slot_io_strobe, slot_rom_deselect, slot_bus_conflict;
	wire cpu_enable, cpu_rwn;
	integer phase = 0, cycles = 0, completed = 0;
	wire [3:0][7:0] slot_data_in = {resume_test && slot_addr == 16'hc0c0 ? 8'h99 : card_data[3], card_data[2:0]};
	always #5 clk = ~clk;
	apple3_core #(
		.ROM_INIT_FILE("sim/slots/obj_dir/diagnostic.hex")
	) dut (
		.clk_14m            (clk),
		.reset,
		.ps2_key,
		.plus_keymap        (1'b0),
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
		.slot_data_in,
		.slot_data_oe,
		.slot_irq_n,
		.slot_nmi_n,
		.slot_ready         (4'b1111),
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
	for (genvar s = 0; s < 4; s++) begin : cards
		test_card #(
			.SLOT  (s + 1),
			.LEGACY(s % 2 == 1)
		) card (
			.clk,
			.reset        (slot_reset),
			.cycle        (slot_cycle),
			.addr         (slot_addr),
			.cpu_read     (slot_cpu_read),
			.data_in      (slot_data_out),
			.device_select(slot_device_select[s]),
			.io_select    (slot_io_select[s]),
			.io_strobe    (slot_io_strobe),
			.rom_deselect (slot_rom_deselect),
			.data_out     (card_data[s]),
			.data_oe      (slot_data_oe[s]),
			.irq_n        (slot_irq_n[s]),
			.nmi_n        (slot_nmi_n[s]),
			.selected     (selected[s])
		);
	end
	always @(posedge clk) begin
		cycles <= cycles + 1;
		if (slot_bus_conflict) $fatal(1, "ROM contention at PC %04x phase %0d", pc, phase);
		if (cpu_enable && !cpu_rwn && !dut.machine_reset) begin
			if (cpu_addr == 16'h0201) begin
				phase <= int'(cpu_dout);
				$display("CPU slot diagnostic phase %0d", cpu_dout);
			end
			if (cpu_addr == 16'h0200) begin
				if (cpu_dout != 8'h5a) $fatal(1, "CPU diagnostic failed in phase %0d at PC %04x", phase, pc);
				completed <= 1;
			end
		end
		if (cycles > 1000000)
			$fatal(1, "timeout phase=%0d PC=%04x IRQ=%b IFR=%02x", phase, pc, slot_irq_n, dut.via_d_data);
	end
	task automatic key(input logic [7:0] code, input logic pressed);
		@(negedge clk);
		ps2_key = {!ps2_key[10], pressed, 1'b0, code};
		repeat (4) @(negedge clk);
	endtask
	initial begin
		repeat (100) @(negedge clk);
		reset = 0;
		wait (phase == 7);
		key(8'h06, 1);  // F2 / Reset alone: NMI, cards keep their state.
		if (slot_reset || dut.cpu_nmi_n || selected != 1) $fatal(1, "native Reset must preserve cards and assert NMI");
		repeat (400) @(negedge clk);
		if (selected != 1 || cards[0].card.registers[0] != 8'h12) $fatal(1, "native NMI changed card state");
		key(8'h14, 1);  // Control + Reset resets CPU, cards and their ROM latches.
		if (!dut.machine_reset || !slot_reset || selected != 0 || slot_irq_n != 15 || slot_nmi_n != 15)
			$fatal(1, "Control-Reset must reset all cards");
		key(8'h06, 0);
		key(8'h14, 0);
		wait (phase != 7);
		wait (phase == 7);
		resume_test = 1;
		wait (completed != 0);
		if (dut.native_mode) $fatal(1, "diagnostic did not enter Apple II mode");
		key(8'h06, 1);
		if (!slot_reset || dut.machine_reset || selected != 0 || slot_irq_n != 15 || slot_nmi_n != 15)
			$fatal(1, "Apple II Reset must reset cards without a native Control-Reset");
		key(8'h06, 0);
		if (slot_reset) $fatal(1, "slot reset did not release");
		$display("PASS real CPU slot I/O, ROM, VIA IRQ dispatch, NMI and native/II reset (%0d clocks)", cycles);
		$finish;
	end
endmodule
