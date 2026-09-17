`timescale 1ns / 1ps
module drive_tb;
	reg clk = 0, engine_reset = 1, active = 1, ready = 1, valid = 1;
	reg [3:0] phases = 0;
	reg write_protect = 1, write_mode = 0, write_bit = 0, write_strobe = 0;
	wire flux, bit_we;
	wire [8:0] head;
	wire [15:0] bit_addr, write_addr;
	wire [16:0] bit_position;
	reg  [ 7:0] bit_data = 8'hff;
	wire [ 7:0] write_data;
	reg  [ 7:0] timing = 32;
	wire [31:0] bit_count = 50304, flux_size = 0, flux_ticks = 0;
	wire        is_flux = 0, load_done = 0;
	always #5 clk = ~clk;
	flux_drive drive (
		.IS_35_INCH         (1'b0),
		.DRIVE_ID           (2'd0),
		.CLK_14M            (clk),
		.RESET              (engine_reset),
		.PHASES             (phases),
		.IMMEDIATE_PHASES   (phases),
		.LATCHED_SENSE_REG  (3'd0),
		.IWM_MODE           (5'd0),
		.MOTOR_ON           (active),
		.SW_MOTOR_ON        (active),
		.DISKREG_SEL        (1'b0),
		.SEL35              (1'b0),
		.DRIVE_SELECT       (1'b0),
		.DRIVE_SLOT         (1'b0),
		.DISK_MOUNTED       (ready),
		.DISK_WP            (write_protect || !valid),
		.DOUBLE_SIDED       (1'b0),
		.FLUX_TRANSITION    (flux),
		.WRITE_PROTECT      (),
		.SENSE              (),
		.DISK_SWITCHED_OUT  (),
		.STEP_BUSY_OUT      (),
		.STEP_DIR_OUT       (),
		.MOTOR_ON_SENSE_OUT (),
		.AT_TRACK0_OUT      (),
		.MOTOR_SPINNING     (),
		.DRIVE_READY        (),
		.TRACK              (),
		.HEAD_QTRACK        (head),
		.EJECT_REQ          (),
		.BIT_POSITION       (bit_position),
		.BIT_TIMER_OUT      (),
		.TRACK_BIT_COUNT    (bit_count),
		.TRACK_LOADED       (valid && ready),
		.TRACK_LOAD_COMPLETE(load_done),
		.BRAM_ADDR          (bit_addr),
		.BRAM_DATA          (bit_data),
		.OPTIMAL_BIT_TIMING (timing),
		.IS_FLUX_TRACK      (is_flux),
		.FLUX_DATA_SIZE     (flux_size),
		.FLUX_TOTAL_TICKS   (flux_ticks),
		.WRITE_BIT          (write_bit),
		.WRITE_STROBE       (write_strobe && active),
		.WRITE_MODE         (write_mode && active),
		.WRITE_BYTE_OUT     (write_data),
		.WRITE_WE_OUT       (bit_we),
		.WRITE_ADDR_OUT     (write_addr),
		.SD_TRACK_REQ       (),
		.SD_TRACK_STROBE    (),
		.SD_TRACK_ACK       (1'b0),
		.CHUNK_RELOAD_REQ   (),
		.CHUNK_NEEDED       (),
		.CHUNK_LOADED       (2'd0),
		.CHUNK_LOADING      (1'b0)
	);

	integer
		cycles = 0, last_flux = -1, pulses = 0, short_cells = 0, long_cells = 0, writes = 0, last_cell = -1, cells = 0;
	integer previous_position = 0, wraps = 0, last_wrap = 0;
	reg check_clock = 1;
	always @(negedge clk)
		if (!engine_reset) begin
			cycles = cycles + 1;
			if (flux && valid) begin
				if (check_clock && pulses > 10 && (cycles - last_flux < 56 || cycles - last_flux > 59))
					$fatal(1, "unexpected flux interval %0d", cycles - last_flux);
				last_flux = cycles;
				pulses    = pulses + 1;
			end
			if (!valid) pulses = 0;
			if (bit_position != previous_position && !write_mode) begin
				if (check_clock && cells > 10) begin
					if (cycles - last_cell == 57) short_cells = short_cells + 1;
					else if (cycles - last_cell == 58) long_cells = long_cells + 1;
					else $fatal(1, "unexpected bit interval %0d", cycles - last_cell);
				end
				last_cell = cycles;
				cells     = cells + 1;
			end
			if (previous_position > 50000 && bit_position == 0) begin
				if (check_clock && wraps > 0 && (cycles - last_wrap < 2880940 || cycles - last_wrap > 2881080))
					$fatal(1, "rotation does not honor 4us cells: %0d clocks", cycles - last_wrap);
				last_wrap = cycles;
				wraps     = wraps + 1;
			end
			previous_position = bit_position;
			if (bit_we) writes = writes + 1;
		end
	task measure_timing(input [7:0] value, input integer expected);
		integer count, start, position;
		begin
			timing = value;
			repeat (1024) @(negedge clk);
			position = bit_position;
			while (bit_position == position) @(negedge clk);
			start    = cycles;
			count    = 0;
			position = bit_position;
			while (count < 1000) begin
				@(negedge clk);
				if (bit_position != position) begin
					count++;
					position = bit_position;
				end
			end
			if (cycles - start < expected - 2 || cycles - start > expected + 2)
				$fatal(1, "timing %0d: 1000 cells took %0d clocks, expected %0d", value, cycles - start, expected);
		end
	endtask
	initial begin
		repeat (5) @(negedge clk);
		engine_reset = 0;
		wait (wraps == 2);
		if (short_cells == 0 || long_cells < 25000)
			$fatal(1, "fractional clock overflow: short=%0d long=%0d", short_cells, long_cells);
		// Missing cached data must suppress pulses without stopping rotation.
		@(negedge clk);
		valid = 0;
		repeat (1000) begin
			@(negedge clk);
			if (flux) $fatal(1, "stale flux while loading");
		end
		valid       = 1;
		check_clock = 0;
		measure_timing(28, 50113);
		measure_timing(255, 456392);
		// Protection must block the read-modify-write path.
		write_mode = 1;
		repeat (5) @(negedge clk);
		write_strobe = 1;
		@(negedge clk);
		write_strobe = 0;
		repeat (5) @(negedge clk);
		if (writes) $fatal(1, "protected write");
		write_protect = 0;
		write_bit     = 0;
		write_strobe  = 1;
		@(negedge clk);
		write_strobe = 0;
		repeat (5) @(negedge clk);
		if (writes != 1) $fatal(1, "writable bit not stored");
		if ($countones(write_data) != 7) $fatal(1, "bit write damaged adjacent bits: %02x", write_data);
		$display(
			"PASS drive: WOZ 4us/3.5us/31.875us cells, fractional timing, cache gating, write protection and bit writes");
		$finish;
	end
	initial begin
		#200000000;
		$fatal(1, "watchdog");
	end
endmodule
