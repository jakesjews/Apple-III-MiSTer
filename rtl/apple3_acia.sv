// Minimal functional MOS 6551 ACIA.  The Apple /// boot path only requires
// register-presence and transmitter-ready behavior; receive injection is kept
// explicit so a future MiSTer UART bridge does not require changing the bus.

module apple3_acia (
	input  logic       clk,
	input  logic       reset,
	input  logic       read_strobe,
	input  logic       write_strobe,
	input  logic [1:0] addr,
	input  logic [7:0] data_in,
	input  logic       rx_strobe,
	input  logic [7:0] rx_data,
	output logic [7:0] data_out,
	output logic [7:0] tx_data,
	output logic       tx_strobe,
	output logic       irq
);

	logic [7:0] receive_data;
	logic [7:0] command;
	logic [7:0] control;
	logic       receive_full;
	logic       overrun;

	always_comb begin
		irq = receive_full && !command[1];
		case (addr)
			2'd0: data_out = receive_data;
			2'd1: data_out = {irq, 1'b0, 1'b0, 1'b1, receive_full,
			                       overrun, 1'b0, 1'b0};
			2'd2: data_out = command;
			default: data_out = control;
		endcase
	end

	always_ff @(posedge clk) begin
		tx_strobe <= 1'b0;
		if (reset) begin
			receive_data <= 8'h00;
			command <= 8'h00;
			control <= 8'h00;
			receive_full <= 1'b0;
			overrun <= 1'b0;
			tx_data <= 8'h00;
		end
		else begin
			if (rx_strobe) begin
				if (receive_full) overrun <= 1'b1;
				receive_data <= rx_data;
				receive_full <= 1'b1;
			end
			if (read_strobe && (addr == 2'd0)) begin
				receive_full <= 1'b0;
				overrun <= 1'b0;
			end
			if (write_strobe) begin
				case (addr)
					2'd0: begin tx_data <= data_in; tx_strobe <= 1'b1; end
					2'd1: begin command <= 8'h00; receive_full <= 1'b0; overrun <= 1'b0; end
					2'd2: command <= data_in;
					2'd3: control <= data_in;
				endcase
			end
		end
	end

endmodule
