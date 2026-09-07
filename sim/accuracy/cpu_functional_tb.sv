`timescale 1ns/1ps
// Runs Klaus Dormann's published 6502 binary using the core's T65 wrapper.
// The binary is supplied by +ROM=<hex>, not redistributed here.
module cpu_functional_tb;
  logic clk=0,reset_n=0;
  always #5 clk=~clk;
  wire [15:0] address;
  wire [7:0] data_out;
  wire rwn,sync;
  logic [7:0] ram[0:65535];
  string rom;
  integer cycles=0;
  t65_wrapper cpu(.clk(clk),.reset_n(reset_n),.enable(1'b1),
    .irq_n(1'b1),.nmi_n(1'b1),.data_in(ram[address]),.data_out(data_out),
    .address(address),.read_nwrite(rwn),.sync(sync),.regs());
  initial begin
    if(!$value$plusargs("ROM=%s",rom)) $fatal(1,"supply +ROM=<functional test hex>");
    $readmemh(rom,ram);
    // The suite specifies starting execution at $0400, not its reset trap.
    ram[16'hfffc]=8'h00; ram[16'hfffd]=8'h04;
    repeat(5) @(negedge clk); reset_n=1;
  end
  always @(posedge clk) begin
    if(reset_n) begin
      cycles<=cycles+1;
      if(!rwn) ram[address]<=data_out;
      if(sync && address==16'h3469) begin
        $display("PASS Klaus 6502 functional test at $3469 after %0d cycles",cycles);
        $finish;
      end
      if(cycles==100000000) $fatal(1,"functional test timeout, address=%04x",address);
    end
  end
endmodule
