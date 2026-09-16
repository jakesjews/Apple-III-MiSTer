`timescale 1ns/1ps
module woz_image_tb;
    reg clk=0,reset=1,img_mounted=0,img_readonly=0,active=1;
    reg [63:0] img_size=0;
    wire [31:0] sd_lba;
    wire sd_rd,sd_wr;
    reg sd_ack=0,sd_buff_wr=0;
    reg [13:0] sd_buff_addr=0;
    wire [5:0] sd_blk_cnt;
    reg [7:0] sd_buff_dout=0;
    wire [7:0] sd_buff_din;
    reg [7:0] track_id=0;
    wire ready,disk_mounted,busy;
    wire [31:0] bit_count;
    reg [15:0] bit_addr=0,bit_wr_addr=0;
    wire [7:0] bit_data;
    reg [7:0] bit_data_in=0;
    reg bit_we=0;
    wire track_load_complete,is_flux_track,track_data_valid,disk_type_mismatch,disk_write_protected;
    wire [31:0] flux_data_size,flux_total_ticks;
    wire [7:0] optimal_bit_timing;
    woz_floppy_controller dut(.*, .stable_side(1'b0),.dbg_load_sum(),.dbg_load_bytes(),.dbg_load_blocks());
    always #5 clk=~clk;
    reg [7:0] media[0:65535], original[0:65535];
    integer writes=0, reads=0, phase=0, offset=0, index=0;
    reg reading;
    integer transfer_bytes;
    // An immediate ack and sparse strobes exercise the same contract as hps_io.
    always @(negedge clk) begin
        sd_buff_wr=0;
        case(phase)
          0: if(!reset && (sd_rd || sd_wr)) begin
              if(sd_lba*512>=img_size+511) $fatal(1,"request outside image: %0d",sd_lba);
              reading=sd_rd; offset=sd_lba*512;index=0;transfer_bytes=(sd_blk_cnt+1)*512;
              if(transfer_bytes>16384) $fatal(1,"burst exceeds hps_io buffer");
              if(sd_wr) writes=writes+1; else reads=reads+1;
              sd_ack=1;phase=1;
          end
          1: begin
              sd_buff_addr=index;
              sd_buff_dout=media[offset+index];
              sd_buff_wr=reading;
              phase=2;
          end
          2: phase=3;
          3: begin
              if(!reading) media[offset+index]=sd_buff_din;
              if(index+1==transfer_bytes) phase=4;
              else begin index=index+1;phase=1;end
          end
          4: begin sd_ack=0;phase=5;end
          5: phase=0;
        endcase
    end
    task wait_track;
        integer n;
        begin
            n=0;
            while(!(ready && track_data_valid) && n<300000) begin @(posedge clk);n=n+1;end
            if(n==300000) $fatal(1,"track load timeout, state=%0d",dut.state);
            repeat(3) @(negedge clk);
        end
    endtask
    task check_byte(input integer addr, input [7:0] value);
        begin
            @(negedge clk);bit_addr=addr;
            repeat(3) @(negedge clk);
            if(bit_data!==value) $fatal(1,"track byte %0d: %02x != %02x",addr,bit_data,value);
        end
    endtask
    string path;
    integer file,size,version,n,allocation;
    initial begin
        if(!$value$plusargs("IMAGE=%s",path)) $fatal(1,"IMAGE required");
        file=$fopen(path,"rb");size=$fread(media,file);$fclose(file);
        img_size=size;version=media[3]-"0";allocation=version==2 ? media[258]+256*media[259] : 13;
        for(integer i=0;i<65536;i++) original[i]=media[i];
        repeat(5) @(negedge clk);reset=0;img_mounted=1;
        wait_track();
        if(bit_count!=50000) $fatal(1,"bit count=%0d",bit_count);
        for(integer i=0;i<6250;i=i+257) check_byte(i,(i*13)&255);
        if(version==1 && !disk_write_protected) $fatal(1,"WOZ1 must report read-only");
        if(version==2) begin
            if(allocation>32) check_byte(17000,(17000*13)&255);
            if(disk_write_protected) $fatal(1,"writable WOZ2 reports protected");
            @(negedge clk);bit_wr_addr=5;bit_data_in=8'h6e;bit_we=1;
            @(negedge clk);bit_we=0;
            repeat(4) @(negedge clk);active=0;
            n=0;
            while((writes<allocation || busy || phase!=0) && n<100000) begin @(posedge clk);n=n+1;end
            if(n==100000) $fatal(1,"writeback timeout writes=%0d",writes);
            for(integer i=0;i<size;i++) begin
                if(i==1536+5) begin
                    if(media[i]!==8'h6e) $fatal(1,"writeback byte wrong %02x",media[i]);
                end else if(media[i]!==original[i]) $fatal(1,"unrelated byte changed %0d %02x != %02x",i,media[i],original[i]);
            end
        end
        active=1;track_id=4;repeat(3) @(negedge clk);wait_track();
        check_byte(0,37);check_byte(200,77);
        track_id=2;repeat(3) @(negedge clk);wait_track();
        if(bit_count!=0) $fatal(1,"unmapped quarter track exposes old data");
        // Cold reset while mounted must recover when mount is pulsed again.
        img_mounted=0;reset=1;repeat(5) @(negedge clk);
        track_id=0;reset=0;img_mounted=1;wait_track();check_byte(0,0);
        // Invalid TMAP indices must not alias the small metadata RAM.
        img_mounted=0;reset=1;repeat(5) @(negedge clk);
        media[88]=160;reset=0;img_mounted=1;
        repeat(100000) @(negedge clk);
        if(ready || disk_mounted) $fatal(1,"invalid TMAP index accepted");
        media[88]=original[88];
        if(version==2) begin
            // Refuse a track allocation that exceeds the physical cache.
            img_mounted=0;reset=1;repeat(5) @(negedge clk);
            media[258]=65;reset=0;img_mounted=1;
            repeat(100000) @(negedge clk);
            if(ready || disk_mounted) $fatal(1,"oversized track accepted");
            media[258]=original[258];
        end
        // Invalid signature must never become a ready disk.
        img_mounted=0;reset=1;repeat(5) @(negedge clk);
        media[0]="X";reset=0;img_mounted=1;
        repeat(10000) @(negedge clk);
        if(ready || disk_mounted) $fatal(1,"invalid image accepted");
        $display("PASS WOZ%0d: block delivery, exact track data, quarter tracks, reset, rejection, writes=%0d",version,writes);
        $finish;
    end
    initial begin #10000000;$fatal(1,"watchdog");end
endmodule
