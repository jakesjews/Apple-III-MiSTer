// Instruction-scoped Apple /// extended-addressing latch.
// A non-opcode zero-page read while ZP=$18-$1f captures the simultaneously
// fetched sister byte.  Its bit 7 redirects subsequent >=$0100 accesses until
// the next SYNC/opcode fetch.  Bits 6:4 are physically ignored.

module apple3_extaddr (
	input  logic       clk,
	input  logic       reset,
	input  logic       cycle_strobe,
	input  logic       sync,
	input  logic       cpu_read,
	input  logic [15:0] cpu_addr,
	input  logic [7:0] zero_page,
	input  logic [7:0] sister_data,
	output logic       active,
	output logic [7:0] bank
);

	always_ff @(posedge clk) begin
		if (reset) begin
			active <= 1'b0;
			bank   <= 8'h00;
		end
		else if (cycle_strobe) begin
			if (sync) begin
				active <= 1'b0;
				bank   <= 8'h00;
			end
			else if (cpu_read && (cpu_addr < 16'h0100) &&
			         (zero_page >= 8'h18) && (zero_page <= 8'h1f)) begin
				bank   <= sister_data & 8'h8f;
				active <= sister_data[7];
			end
		end
	end

endmodule
