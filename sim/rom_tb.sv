`timescale 1ns / 1ps

// Boot ROM selection: Apple's ROM in both banks, the soshdboot ROM in both
// banks when selected, and a ROM from the host in place of Apple's only.
module rom_tb;
	logic clk = 0;
	logic [12:0] addr = 0, host_addr = 0;
	logic [7:0] host_data = 0;
	logic host_we = 0, soshdboot = 0;
	wire [7:0] q;

	apple3_rom rom (.*);
	always #5 clk = ~clk;

	logic [7:0] stock[4096], hdboot[4096];
	initial begin
		$readmemh("rtl/apple3_rom.hex", stock);
		$readmemh("rtl/soshdboot/apple3hdboot.hex", hdboot);
	end

	task automatic read(input logic [12:0] a, output logic [7:0] value);
		begin
			addr = a;
			@(posedge clk);
			@(posedge clk);
			#1 value = q;
		end
	endtask

	// Every address of both banks against the image expected there.
	task automatic check_image(input string name, input logic use_hdboot, input logic uploaded);
		logic [7:0] value, expected;
		begin
			for (int a = 0; a < 8192; a++) begin
				read(13'(a), value);
				expected = uploaded ? 8'((a % 4096) * 7 + 3) : use_hdboot ? hdboot[a%4096] : stock[a%4096];
				if (value !== expected)
					$fatal(1, "%s: bank %0d $F%03x = %02x, expected %02x", name, a / 4096, a % 4096, value, expected);
			end
		end
	endtask

	initial begin
		@(posedge clk);
		check_image("Apple", 0, 0);
		soshdboot = 1;
		check_image("soshdboot", 1, 0);
		soshdboot = 0;
		check_image("Apple again", 0, 0);
		// The two ROMs must differ where soshdboot searches the slots.
		if (stock[12'h6a0] == hdboot[12'h6a0] && stock[12'h6b0] == hdboot[12'h6b0])
			$fatal(1, "soshdboot image matches Apple's at $F6A0 and $F6B0");

		// A 4 KiB upload replaces Apple's ROM in both banks; soshdboot, as
		// with games/Apple-III/boot.rom sent at every start, stays selected.
		soshdboot = 1;
		for (int i = 0; i < 4096; i++) begin
			@(negedge clk);
			host_addr = 13'(i);
			host_data = 8'(i * 7 + 3);
			host_we   = 1;
		end
		@(negedge clk);
		host_we = 0;
		check_image("soshdboot after an upload", 1, 0);
		soshdboot = 0;
		check_image("upload", 0, 1);
		$display("PASS boot ROM selection: Apple, soshdboot, and an uploaded ROM in place of Apple's");
		$finish;
	end
endmodule
