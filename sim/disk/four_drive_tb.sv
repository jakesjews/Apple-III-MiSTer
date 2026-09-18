`timescale 1ns / 1ps
// Exercise four real WOZ engines sharing the MiSTer data bus. Only the drive
// receiving sd_ack may consume a transfer; mounts and writes remain local.
module four_drive_tb;
	logic clk = 0, reset = 1;
	always #5 clk = ~clk;
	logic [3:0] change = 0, active = 0, motor_on = 15, protect = 0, phases = 0;
	logic [63:0] image_size = 0;
	logic image_readonly = 0, write_mode = 0, write_bit = 0, write_strobe = 0;
	wire [3:0] ready, write_protect, flux, valid, bit_we, busy;
	wire [ 3:0] saved_phases[4];
	wire [ 7:0] cached_byte [4];
	wire [31:0] sd_lba      [4];
	wire [ 5:0] sd_blk_cnt  [4];
	wire [3:0] sd_rd, sd_wr;
	logic [ 3:0] sd_ack = 0;
	logic [13:0] sd_buff_addr = 0;
	logic [ 7:0] sd_buff_dout = 0;
	wire  [ 7:0] sd_buff_din      [4];
	logic        sd_buff_wr = 0;
	for (genvar d = 0; d < 4; d++) begin : drives
		apple3_woz_drive woz (
			.clk,
			.reset,
			.change       (change[d]),
			.enabled      (1'b1),
			.image_size,
			.image_readonly,
			.protect      (protect[d]),
			.active       (active[d]),
			.motor_on     (motor_on[d]),
			.phases,
			.write_mode,
			.write_bit,
			.write_strobe,
			.flux         (flux[d]),
			.ready        (ready[d]),
			.write_protect(write_protect[d]),
			.sd_lba       (sd_lba[d]),
			.sd_blk_cnt   (sd_blk_cnt[d]),
			.sd_rd        (sd_rd[d]),
			.sd_wr        (sd_wr[d]),
			.sd_ack       (sd_ack[d]),
			.sd_buff_addr,
			.sd_buff_dout,
			.sd_buff_din  (sd_buff_din[d]),
			.sd_buff_wr
		);
		assign valid[d]        = woz.valid;
		assign busy[d]         = woz.image.busy;
		assign bit_we[d]       = woz.bit_we;
		assign saved_phases[d] = woz.drive_phases;
		assign cached_byte[d]  = woz.image.track_ram_side0.mem[100];
	end

	logic [7:0] fixture[65536], media[4][65536];
	integer reads[4] = '{default: 0}, writes[4] = '{default: 0}, bit_writes[4] = '{default: 0};
	integer state = 0, disk = 0, offset = 0, index = 0, count = 0;
	logic reading;
	always @(negedge clk) begin
		for (integer d = 0; d < 4; d++) if (bit_we[d]) bit_writes[d]++;
		sd_buff_wr = 0;
		case (state)
			0:
			if (!reset && |(sd_rd | sd_wr)) begin
				for (disk = 0; !((sd_rd | sd_wr) & (1 << disk)); disk++) begin
				end
				reading = sd_rd[disk];
				offset  = sd_lba[disk] * 512;
				count   = (sd_blk_cnt[disk] + 1) * 512;
				if (count > 16384 || offset + count > 65536) $fatal(1, "invalid transfer");
				index = 0;
				if (reading) reads[disk]++;
				else writes[disk]++;
				sd_ack = 1 << disk;
				state  = 1;
			end
			1: begin
				sd_buff_addr = index;
				sd_buff_dout = media[disk][offset+index];
				sd_buff_wr   = reading;
				state        = 2;
			end
			2: state = 3;
			3: begin
				if (!reading) media[disk][offset+index] = sd_buff_din[disk];
				if (index + 1 == count) state = 4;
				else begin
					index++;
					state = 1;
				end
			end
			4: begin
				sd_ack = 0;
				state  = 5;
			end
			5: state = 0;
		endcase
	end

	task mount(input integer d, input integer size, input logic readonly);
		@(posedge clk);
		#1;
		image_size     = size;
		image_readonly = readonly;
		change         = 1 << d;
		@(posedge clk);
		#1;
		change = 0;
	endtask
	task settle(input [3:0] expected);
		integer n;
		repeat (5) @(posedge clk);
		#1;
		n = 0;
		while ((ready !== expected || (valid & expected) !== expected || |busy || state != 0 || |sd_rd || |sd_wr) && n < 500000) begin
			@(posedge clk);
			#1;
			n++;
		end
		if (n == 500000) $fatal(1, "mount timeout ready=%x valid=%x", ready, valid);
		repeat (5) @(posedge clk);
	endtask
	task write_bits(input integer d);
		@(posedge clk);
		#1;
		active     = 1 << d;
		write_mode = 1;
		repeat (10) @(posedge clk);
		for (integer bitnum = 0; bitnum < 32; bitnum++) begin
			#1;
			write_strobe = 1;
			@(posedge clk);
			#1;
			write_strobe = 0;
			repeat (56) @(posedge clk);
		end
		#1;
		write_mode = 0;
		active     = 0;
		settle(15);
	endtask

	integer file, size;
	initial begin
		file = $fopen("sim/obj_dir/disk/fixture2.woz", "rb");
		if (!file) $fatal(1, "missing fixture");
		size = $fread(fixture, file);
		$fclose(file);
		for (integer d = 0; d < 4; d++)
		for (integer i = 0; i < 65536; i++)
		// Zero CRC denotes unchecked data after changing the test pattern.
		media[d][i] = (i >= 8 && i < 12) ? 0 : i < 1536 ? fixture[i] : fixture[i] ^ (d * 57);
		repeat (5) @(posedge clk);
		#1;
		reset = 0;
		// All four header reads overlap on the one host bus.
		for (integer d = 0; d < 4; d++) mount(d, size, d == 2);
		settle(15);
		if (write_protect !== 4'b0100) $fatal(1, "per-mount read-only state=%x", write_protect);
		for (integer d = 0; d < 4; d++) begin
			if (!reads[d] || cached_byte[d] !== (8'h14 ^ (d * 57))) $fatal(1, "D%0d cache cross-talk", d + 1);
		end
		// Only selected heads see the shared phases, even with all motors on.
		for (integer d = 0; d < 4; d++) begin
			@(posedge clk);
			#1;
			active = 1 << d;
			phases = 1;
			repeat (3) @(posedge clk);
			#1;
			for (integer other = 0; other < 4; other++)
			if (saved_phases[other] !== (other <= d ? 1 : 0)) $fatal(1, "phase cross-talk");
		end
		active = 0;
		for (integer d = 0; d < 4; d++) write_bits(d);
		for (integer d = 0; d < 4; d++) begin
			if (d == 2 ? (bit_writes[d] != 0 || writes[d] != 0) : (bit_writes[d] != 32 || writes[d] != 13))
				$fatal(1, "D%0d write isolation bits=%0d blocks=%0d", d + 1, bit_writes[d], writes[d]);
		end
		// OSD protection is independent of the mounted file's permissions.
		protect = 8;
		write_bits(3);
		if (bit_writes[3] != 32 || writes[3] != 13) $fatal(1, "OSD protection");
		protect = 0;
		mount(2, 0, 0);
		settle(11);
		if (write_protect !== 4) $fatal(1, "ejected disk protection");
		media[2][1536+100] = 8'ha7;
		mount(2, size, 0);
		settle(15);
		if (write_protect || cached_byte[2] !== 8'ha7) $fatal(1, "replacement disk state");
		for (integer d = 0; d < 4; d++)
		if (d != 2 && cached_byte[d] !== (8'h14 ^ (d * 57))) $fatal(1, "replacement changed another cache");
		// Machine reset reparses every mount, preserving presence and permissions.
		@(posedge clk);
		#1;
		reset = 1;
		repeat (5) @(posedge clk);
		#1;
		reset = 0;
		settle(15);
		if (write_protect || cached_byte[2] !== 8'ha7) $fatal(1, "reset lost media state");
		$display("PASS four WOZ drives: shared transfers, phase/write isolation, protection, eject/replace and reset");
		$finish;
	end
	initial begin
		#30000000;
		$fatal(1, "four-drive watchdog");
	end
endmodule
