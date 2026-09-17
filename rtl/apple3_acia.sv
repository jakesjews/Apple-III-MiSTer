// Apple /// bus and MiSTer clock adapter for the imported 6551 core.
// Chip provenance and local corrections: rtl/acia/README.md.
module apple3_acia #(
	parameter integer CLOCK_HZ = 14318182
) (
	input  logic       clk,
	input  logic       reset,
	input  logic       read_strobe,
	input  logic       write_strobe,
	input  logic [1:0] addr,
	input  logic [7:0] data_in,
	output wire  [7:0] data_out,
	input  logic       rx,
	input  logic       cts_n,
	input  logic       dsr_n,
	input  logic       dcd_n,
	output wire        tx,
	output wire        rts_n,
	output wire        dtr_n,
	output wire        irq
);
	// 1.8432 MHz reference, expressed as enables in the motherboard domain.
	// Fractional division avoids a new fabric clock and cumulative baud error.
	localparam integer BAUD_CLOCK_HZ = 1843200;
	localparam integer PHASE_BITS    = $clog2(CLOCK_HZ + BAUD_CLOCK_HZ);
	logic [PHASE_BITS-1:0] baud_phase;
	wire                   baud_enable = baud_phase >= PHASE_BITS'(CLOCK_HZ - BAUD_CLOCK_HZ);
	always_ff @(posedge clk) begin
		if (reset) baud_phase <= 0;
		else if (baud_enable) baud_phase <= baud_phase - PHASE_BITS'(CLOCK_HZ - BAUD_CLOCK_HZ);
		else baud_phase <= baud_phase + PHASE_BITS'(BAUD_CLOCK_HZ);
	end

	// HPS UART signals cross into clk; power-on idle inputs must not inject data.
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [3:0]
		serial_meta, serial_sync;
	always_ff @(posedge clk) begin
		if (reset) begin
			serial_meta <= 4'b1111;
			serial_sync <= 4'b1111;
		end else begin
			serial_meta <= {dcd_n, dsr_n, cts_n, rx};
			serial_sync <= serial_meta;
		end
	end

	wire irq_n;
	assign irq = !irq_n;
	gen_uart_mos_6551 uart (
		.clk      (clk),
		.reset    (reset),
		.clk_en   (baud_enable),
		// RxC is grounded on the Apple /// motherboard (sheet 8).
		.rx_clk_en(1'b0),
		.cs       (read_strobe || write_strobe),
		.rnw      (!write_strobe),
		.rs       (addr),
		.din      (data_in),
		.dout     (data_out),
		.irq_n    (irq_n),
		.rx       (serial_sync[0]),
		.cts_n    (serial_sync[1]),
		.dsr_n    (serial_sync[2]),
		.dcd_n    (serial_sync[3]),
		.tx       (tx),
		.rts_n    (rts_n),
		.dtr_n    (dtr_n)
	);
endmodule
