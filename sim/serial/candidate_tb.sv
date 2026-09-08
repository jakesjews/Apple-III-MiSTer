`timescale 1ns/1ps
module candidate_tb;
reg clk=0, reset=1, cs=0, rnw=1;
reg [1:0] rs=0;
reg [7:0] din=0;
wire [7:0] dout;
reg rx=1, cts=0, dsr=0, dcd=0;
wire tx, rts, dtr, irq_n;
reg [2:0] divider=0;
always #5 clk=~clk;
always @(posedge clk) divider<=divider+1'b1;
`ifdef OLD
 glb6551 dut(.RESET_N(!reset),.PH_2(~clk),.XTAL_CLK_IN(divider[2]),.RX_CLK_IN(divider[2]),.RX_CLK(),
 .DI(din),.DO(dout),.CS({1'b0,cs}),.RW_N(rnw),.RS(rs),.IRQ(irq_n),
 .RXDATA_IN(rx),.TXDATA_OUT(tx),.CTS(cts),.DSR(dsr),.DCD(dcd),.RTS(rts),.DTR(dtr));
`else
 gen_uart_mos_6551 dut(.reset(reset),.clk(clk),.clk_en(divider==7),.din(din),.dout(dout),.rnw(rnw),.cs(cs),.rs(rs),
 .irq_n(irq_n),.cts_n(cts),.dsr_n(dsr),.dcd_n(dcd),.dtr_n(dtr),.rts_n(rts),.rx(rx),.tx(tx));
`endif
integer failures=0;
reg [7:0] val;
task check(input bit ok,input string what); begin if(!ok) begin $display("FAIL %s",what);failures++;end else $display("PASS %s",what);end endtask
task wr(input [1:0] a,input [7:0] v);begin @(negedge clk);cs=1;rnw=0;rs=a;din=v;repeat(2)@(negedge clk);cs=0;rnw=1;repeat(4)@(negedge clk);end endtask
task rd(input [1:0] a);begin @(negedge clk);cs=1;rnw=1;rs=a;#1;val=dout;repeat(2)@(negedge clk);cs=0;repeat(4)@(negedge clk);end endtask
task send(input [7:0] v);begin rx=0;repeat(768)@(negedge clk);for(integer b=0;b<8;b++)begin rx=v[b];repeat(768)@(negedge clk);end rx=1;repeat(1536)@(negedge clk);end endtask
initial begin
 repeat(20)@(negedge clk);reset=0;repeat(30)@(negedge clk);
 rd(2);check(val==0,"Apple-compatible hardware reset command = 00");
 wr(3,8'h9f);wr(2,8'he9);wr(1,0);rd(3);check(val==8'h9f,"program reset preserves control");rd(2);check(val==8'he0,"program reset preserves parity, resets low command bits");
 wr(3,8'h1f);wr(2,8'h09);send(8'ha5);rd(1);check(val[3]&&val[7],"receive byte raises IRQ");check(irq_n,"status read acknowledges IRQ with unread data");rd(0);check(val==8'ha5,"receive data byte");
 dsr=1;repeat(2000)@(negedge clk);check(!irq_n,"DSR transition raises IRQ");rd(1);check(irq_n,"DSR IRQ acknowledges");
 wr(2,8'h0d);repeat(2000)@(negedge clk);check(tx==0,"transmit break holds line low");
 $display("Candidate failures: %0d",failures);$finish;
end
endmodule
