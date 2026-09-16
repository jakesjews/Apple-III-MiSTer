// Apple /// disk conditioner: P6, 74LS174 state register and 74LS323.
// SRM 12.3 / schematic 050-0039-H sheet 7. Q3* clocks the sequencer;
// reading the CPU data bus does not clear or acknowledge the shift register.
module apple3_disk_sequencer (
    input wire clk, reset, q3, q6, q7,
    input wire flux, write_protect,
    input wire [7:0] data_in,
    output reg [7:0] data_out,
    output reg write_bit, write_strobe
);
    reg q3_d;
    reg flux_pending;
    reg [3:0] state;
    wire tick = q3_d && !q3;
    // P6 A7,A6,A5,A0 are fed by Q7,Q6,Q4,Q5 respectively.
    wire [7:0] address = {state[3:1], !(flux_pending || flux),
                          q7, q6, data_out[7], state[0]};
    wire [7:0] control;
    apple3_p6 p6(.a(address), .q(control));
    always @(posedge clk) begin
        q3_d <= q3;
        write_strobe <= 1'b0;
        if (reset) begin
            q3_d <= 1'b0;
            flux_pending <= 1'b0;
            state <= 4'd0;
            data_out <= 8'd0;
            write_bit <= 1'b0;
        end else begin
            if (flux) flux_pending <= 1'b1;
            if (tick) begin
                flux_pending <= 1'b0;
                state <= {control[7:6], control[4], control[5]};
                if (!control[3]) data_out <= 8'd0;
                else case (control[1:0])
                    2'b01: data_out <= {data_out[6:0], control[2]};
                    2'b10: data_out <= {write_protect, data_out[7:1]};
                    2'b11: data_out <= data_in;
                    default: ; // hold
                endcase
                // At the end of each eight-clock write cell, QA determines
                // whether the next state toggles WR DATA (state bit 3).
                if (q7 && state[2:0] == 3'b111) begin
                    write_bit <= data_out[7];
                    write_strobe <= 1'b1;
                end
            end
        end
    end
endmodule
