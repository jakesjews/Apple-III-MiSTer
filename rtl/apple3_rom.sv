// Two 4 KiB Apple /// boot-ROM banks.  The image is deliberately not part of
// the repository: build.sh converts a user-supplied 4K/8K ROM to the generated
// hex file, while MiSTer can also load one through ioctl at run time.

module apple3_rom #(
	parameter INIT_FILE = "",
	parameter integer INIT_START = 0
)(
	input  logic        clk,
	input  logic [12:0] addr,
	output logic [7:0]  q,
	input  logic        host_we,
	input  logic [12:0] host_addr,
	input  logic [7:0]  host_data
);

	(* ramstyle = "M10K" *) logic [7:0] mem [0:8191];

	initial begin
		if (INIT_FILE != "") $readmemh(INIT_FILE, mem, INIT_START);
	end

	always_ff @(posedge clk) begin
		q <= mem[addr];
		if (host_we) mem[host_addr] <= host_data;
	end

endmodule
