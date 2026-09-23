`timescale 1ns / 1ps
// diagnostic.s on the whole core, configured as the stock 256 KiB machine.
module core_memmap_tb;
	logic clk = 0, reset = 1, ram_128k = 0;
	wire [3:0] slot_device_select;
	wire [15:0] cpu_addr, pc;
	wire [7:0] cpu_dout;
	wire cpu_enable, cpu_rwn;
	integer cycles = 0, phase = 0;
	always #5 clk = ~clk;
	apple3_core #(
		.ROM_INIT_FILE("sim/memmap/obj_dir/diagnostic.hex"),
		.RAM_BANKS    (8)
	) dut (
		.clk_14m            (clk),
		.reset,
		.ps2_key            (11'd0),
		.plus_keymap        (1'b0),
		.ram_128k,
		.soshdboot          (1'b0),
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
		.slot_data_in       ({8'h00, 8'h00, 8'h00, 8'h5a}),
		.slot_data_oe       (slot_device_select),
		.slot_irq_n         (4'hf),
		.slot_nmi_n         (4'hf),
		.slot_ready         (4'hf),
		.slot_addr          (),
		.slot_data_out      (),
		.slot_cpu_read      (),
		.slot_cycle         (),
		.slot_reset         (),
		.slot_device_select,
		.slot_io_select     (),
		.slot_io_strobe     (),
		.slot_rom_deselect  (),
		.slot_bus_conflict  (),
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
		if (cycles > 2000000) $fatal(1, "timeout phase=%0d PC=%04x", phase, pc);
		if (cpu_enable && !cpu_rwn && !dut.machine_reset) begin
			if (cpu_addr == 16'h0201) phase <= int'(cpu_dout);
			if (cpu_addr == 16'h0200) begin
				if (cpu_dout != 8'h5a) $fatal(1, "memory-map diagnostic failed in phase %0d at PC %04x", phase, pc);
				if (!ram_128k || phase != 13) $fatal(1, "diagnostic ended in phase %0d", phase);
				$display(
					"PASS real CPU memory map: pairs, $8F/$87, absent banks, stacks, latch timing, zero-page decode, 128K (%0d clocks)",
					cycles);
				$finish;
			end
			// The memory board is changed with the power off.
			if (cpu_addr == 16'h0203) swap <= 1;
		end
	end
	logic swap = 0;
	initial begin
		repeat (100) @(negedge clk);
		reset = 0;
		wait (swap);
		ram_128k = 1;
		reset    = 1;
		repeat (100) @(negedge clk);
		reset = 0;
	end
endmodule
