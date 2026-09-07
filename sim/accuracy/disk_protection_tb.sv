`timescale 1ns/1ps
// SRM printed p.12.7 (PDF p.258): write protection physically blocks writing.
module disk_protection_tb;
  logic clk_14m=0,clk_2m=0,phase_zero=1,reset=1;
  always #5 clk_14m=~clk_14m;
  always #35 clk_2m=~clk_2m;
  logic select=1,cycle_strobe=0,cpu_read=1;
  logic [7:0] addr=0,data_in=8'ha5;
  logic [1:0] disk_ready=3,write_protect=3;
  wire [7:0] data_out;
  wire [3:0] motor_phase;
  wire side_two,d1_active,d2_active,d1_motor_on,d2_motor_on;
  wire d1_io_active,d2_io_active,d1_track_zero_step,d2_track_zero_step;
  wire [5:0] track1,track2;
  wire [12:0] track1_addr,track2_addr;
  wire [7:0] track1_din,track2_din;
  logic [7:0] track1_dout=0,track2_dout=0;
  wire track1_we,track2_we;
  logic track1_busy=0,track2_busy=0;
  apple3_disk dut(.*);
  integer writes=0, other_writes=0;
  logic [7:0] cache1[0:8191],cache2[0:8191];
  always @(posedge clk_14m) begin
    if(track1_we) cache1[track1_addr]<=track1_din;
    if(track2_we) cache2[track2_addr]<=track2_din;
  end
  task automatic touch(input [7:0] a);
    @(negedge clk_14m); addr=a; cycle_strobe=1;
    @(negedge clk_14m); cycle_strobe=0;
  endtask
  initial begin
    repeat(3) @(negedge clk_14m); reset=0;
    touch(8'he9); touch(8'hef); // motor on, write mode
    cpu_read=0; touch(8'hed); // load data register
    touch(8'hec);
    for(integer drive=0;drive<2;drive++) begin
      if(drive==1) begin touch(8'hd1); touch(8'heb); touch(8'hec); end
      for(integer protected_media=0;protected_media<2;protected_media++) begin
        @(negedge clk_14m); write_protect=protected_media?2'b11:(drive?2'b01:2'b10);
        for(integer i=0;i<8192;i++) begin cache1[i]=8'h5a; cache2[i]=8'h5a; end
        writes=0; other_writes=0;
        repeat(1024) begin
          @(negedge clk_14m);
          if(drive?track2_we:track1_we) writes++;
          if(drive?track1_we:track2_we) other_writes++;
        end
        if(other_writes || (protected_media ? writes!=0 : writes==0))
          $fatal(1,"drive %0d protection=%0d writes=%0d other=%0d",drive+1,protected_media,writes,other_writes);
        if(protected_media)
          for(integer i=0;i<8192;i++)
            if(cache1[i]!==8'h5a || cache2[i]!==8'h5a) $fatal(1,"protected cache changed at %0d",i);
        $display("PASS: drive %0d protection=%0d writes=%0d, other drive untouched",drive+1,protected_media,writes);
      end
    end
    $finish;
  end
endmodule
