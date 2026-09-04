module tb(input clk, input rst_n, output [15:0] pc_out, output [7:0] m10, m11, m12, m13, output sync_o);
  wire [23:0] A; wire [7:0] DI, DO; wire RW_n; wire Sync;
  reg [7:0] ram[0:65535];
  T65 cpu(.Mode(2'b00), .BCD_en(1'b1), .Res_n(rst_n), .Enable(1'b1), .Clk(clk), .Rdy(1'b1), .Abort_n(1'b1),
          .IRQ_n(1'b1), .NMI_n(1'b1), .SO_n(1'b1), .R_W_n(RW_n), .Sync(Sync), .EF(), .MF(), .XF(), .ML_n(), .VP_n(), .VDA(), .VPA(),
          .A(A), .DI(DI), .DO(DO), .Regs(), .NMI_ack());
  assign DI = ram[A[15:0]];
  always @(posedge clk) if (!RW_n) ram[A[15:0]] <= DO;
  assign pc_out = A[15:0]; assign sync_o = Sync;
  assign m10 = ram[16'h10]; assign m11 = ram[16'h11]; assign m12 = ram[16'h12]; assign m13 = ram[16'h13];
  initial begin
    integer i; for (i=0;i<65536;i=i+1) ram[i]=8'hEA;
    ram[16'hFFFC]=8'h00; ram[16'hFFFD]=8'h02;
    // $0200: LDA #$12; STA $10; LDX #0; L: INX; STX $11; CPX #$FF; BNE L;
    ram[16'h0200]=8'hA9; ram[16'h0201]=8'h12; ram[16'h0202]=8'h85; ram[16'h0203]=8'h10;
    ram[16'h0204]=8'hA2; ram[16'h0205]=8'h00; ram[16'h0206]=8'hE8; ram[16'h0207]=8'h86; ram[16'h0208]=8'h11;
    ram[16'h0209]=8'hE0; ram[16'h020A]=8'hFF; ram[16'h020B]=8'hD0; ram[16'h020C]=8'hF9;
    // LDA #$00 STA $20; LDA #$03 STA $21; LDY #$05; LDA ($20),Y ; STA $12 ; SED; CLC; LDA #$19; ADC #$01; STA $13; JMP *
    ram[16'h020D]=8'hA9; ram[16'h020E]=8'h00; ram[16'h020F]=8'h85; ram[16'h0210]=8'h20;
    ram[16'h0211]=8'hA9; ram[16'h0212]=8'h03; ram[16'h0213]=8'h85; ram[16'h0214]=8'h21;
    ram[16'h0215]=8'hA0; ram[16'h0216]=8'h05; ram[16'h0217]=8'hB1; ram[16'h0218]=8'h20; ram[16'h0219]=8'h85; ram[16'h021A]=8'h12;
    ram[16'h021B]=8'hF8; ram[16'h021C]=8'h18; ram[16'h021D]=8'hA9; ram[16'h021E]=8'h19; ram[16'h021F]=8'h69; ram[16'h0220]=8'h01;
    ram[16'h0221]=8'h85; ram[16'h0222]=8'h13; ram[16'h0223]=8'h4C; ram[16'h0224]=8'h23; ram[16'h0225]=8'h02;
    ram[16'h0305]=8'h77;
  end
endmodule
