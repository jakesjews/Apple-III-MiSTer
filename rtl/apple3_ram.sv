// 512 KiB Apple /// RAM arranged as 256K words of sister-byte pairs.
// Addresses which differ by $0c00 share a word.  This mirrors the two DRAM
// output buses described in Apple patent US4383296 and the service manual.

module apple3_ram (
	input  logic        clk,

	input  logic [17:0] cpu_addr,
	input  logic        cpu_lane,
	input  logic        cpu_we,
	input  logic [7:0]  cpu_din,
	output logic [15:0] cpu_q,

	input  logic [17:0] video_addr,
	output logic [15:0] video_q
);

	(* ramstyle = "M10K, no_rw_check" *) logic [15:0] mem [0:262143];

	always_ff @(posedge clk) begin
		cpu_q   <= mem[cpu_addr];
		video_q <= mem[video_addr];

		if (cpu_we) begin
			if (cpu_lane) mem[cpu_addr][15:8] <= cpu_din;
			else          mem[cpu_addr][7:0]  <= cpu_din;
		end
	end

endmodule
