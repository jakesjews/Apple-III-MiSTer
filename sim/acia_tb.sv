`timescale 1ns/1ps
// Independent CPU-bus and serial-pin driver: no byte injection or DUT internals.
module acia_tb;
	logic clk=0, reset=1, rd=0, wr=0;
	logic [1:0] addr=0;
	logic [7:0] din=0;
	wire [7:0] dout;
	logic rx=1, cts_n=0, dsr_n=0, dcd_n=0;
	wire tx, rts_n, dtr_n, irq;
	apple3_acia #(.CLOCK_HZ(1843200)) dut(
		.clk, .reset, .read_strobe(rd), .write_strobe(wr), .addr,
		.data_in(din), .data_out(dout), .rx, .cts_n, .dsr_n, .dcd_n,
		.tx, .rts_n, .dtr_n, .irq);
	always #5 clk=~clk;
	integer cycles=0, checks=0, bit_cycles=96;
	always @(posedge clk) cycles<=cycles+1;
	reg [7:0] value;
	task automatic check(input bit ok, input string message);
		begin checks++; if(!ok) $fatal(1,"%s at cycle %0d",message,cycles); end
	endtask
	task automatic tick(input integer n); repeat(n) @(negedge clk); endtask
	task automatic write_reg(input [1:0] a,input [7:0] v);
		begin @(negedge clk);addr=a;din=v;wr=1;tick(1);wr=0;tick(4);end
	endtask
	task automatic read_reg(input [1:0] a,output [7:0] v);
		begin @(negedge clk);addr=a;#1;v=dout;rd=1;@(negedge clk);rd=0;tick(4);end
	endtask
	task automatic restart;
		begin reset=1;rd=0;wr=0;rx=1;cts_n=0;dsr_n=0;dcd_n=0;tick(12);reset=0;tick(12);end
	endtask
	function automatic bit parity_bit(input [7:0] data,input integer bits,input integer mode);
		reg p;begin p=^(data & (8'hff >> (8-bits)));case(mode)
		1:parity_bit=!p;2:parity_bit=p;3:parity_bit=1;default:parity_bit=0;endcase end
	endfunction
	function automatic [7:0] command(input integer mode,input bit interrupts);
		command=((mode==0 ? 0 : (2*mode-1))<<5) | (interrupts ? 8'h09 : 8'h0b);
	endfunction
	task automatic configure(input integer bits,input integer mode,input bit extra_stop,input [3:0] baud);
		begin write_reg(3,{extra_stop,2'(8-bits),1'b1,baud});write_reg(2,command(mode,1));end
	endtask
	task automatic send_frame(input [7:0] data,input integer bits,input integer mode,input bit bad_parity,input bit bad_stop);
		begin
			@(negedge clk);rx=0;tick(bit_cycles);
			for(integer b=0;b<bits;b++)begin rx=data[b];tick(bit_cycles);end
			if(mode!=0)begin rx=parity_bit(data,bits,mode)^bad_parity;tick(bit_cycles);end
			rx=!bad_stop;tick(bit_cycles);rx=1;tick(bit_cycles);
		end
	endtask
	task automatic expect_frame(input [7:0] data,input integer bits,input integer mode,output integer started);
		integer timeout;begin
			timeout=0;
			while(tx!==0 && timeout<bit_cycles*20)begin tick(1);timeout++;end
			check(tx===0,"TX start timeout");started=cycles;
			tick(bit_cycles/2);check(tx===0,"TX start bit");
			for(integer b=0;b<bits;b++)begin tick(bit_cycles);check(tx===data[b],$sformatf("TX data bit %0d",b));end
			if(mode!=0)begin tick(bit_cycles);check(tx===parity_bit(data,bits,mode),"TX parity");end
			tick(bit_cycles);check(tx===1,"TX stop bit");
		end
	endtask
	integer start1,start2,expected,stop_halves;
	initial begin
		restart();
		read_reg(2,value);check(value==0,"Apple-compatible command reset");
		read_reg(3,value);check(value==0,"control reset");
		read_reg(1,value);check(value==8'h10 && !irq && tx && rts_n && dtr_n,"idle reset status/pins");
		write_reg(3,8'hbf);write_reg(2,8'he9);write_reg(1,8'hff);
		read_reg(3,value);check(value==8'hbf,"program reset preserves control");
		read_reg(2,value);check(value==8'he0,"program reset preserves parity");
		// 5/6/7/8 bits, all five parity modes, both stop selections.
		for(integer bits=5;bits<=8;bits++)for(integer mode=0;mode<5;mode++)for(integer extra=0;extra<2;extra++)begin
			restart();configure(bits,mode,1'(extra),15);
			fork
				begin expect_frame(8'hd5,bits,mode,start1);expect_frame(8'h2a,bits,mode,start2);end
				begin write_reg(0,8'hd5);tick(bit_cycles*2);write_reg(0,8'h2a);end
			join
			stop_halves=!extra || (bits==8 && mode!=0) ? 2 : bits==5 && mode==0 ? 3 : 4;
			expected=(1+bits+(mode!=0))*bit_cycles+stop_halves*bit_cycles/2;
			check(start2-start1>=expected-6 && start2-start1<=expected+6,$sformatf("TX frame spacing bits=%0d parity=%0d extra=%0d got=%0d expected=%0d",bits,mode,extra,start2-start1,expected));
			tick(bit_cycles*3);
			send_frame(8'hd5,bits,mode,0,0);
			read_reg(1,value);check(value[7:0]==8'h98,"RX flags, IRQ and TDRE");
			check(!irq,"status read clears IRQ while data unread");
			read_reg(0,value);check(value==(8'hd5 & (8'hff>>(8-bits))),"RX selected word length");
			read_reg(1,value);check(value==8'h10,"data read clears RX flags");
		end
		$display("PASS 40 serial word/parity/stop formats and queued TX spacing");
		restart();configure(8,2,0,15);
		send_frame(8'h35,8,2,1,0);read_reg(1,value);check(value[3:0]==9,"parity error reported");read_reg(0,value);
		send_frame(8'h69,8,2,0,1);read_reg(1,value);check(value[1],"framing error reported");read_reg(0,value);
		configure(8,0,0,15);send_frame(8'h12,8,0,0,0);send_frame(8'h34,8,0,0,0);
		read_reg(1,value);check(value[2],"overrun reported");read_reg(0,value);check(value==8'h34,"overrun retains newest received word");
		read_reg(1,value);check(value[3:0]==0,"read RDR clears receive errors");
		// Read RDR alone leaves IRQ latched; enabling RX IRQ is not retroactive.
		send_frame(8'h55,8,0,0,0);read_reg(0,value);check(irq,"data read does not acknowledge IRQ");read_reg(1,value);check(!irq,"status acknowledges RX IRQ");
		write_reg(2,8'h0b);send_frame(8'h56,8,0,0,0);check(!irq,"RX IRQ disabled");write_reg(2,8'h09);check(!irq,"RX IRQ enable is not retroactive");read_reg(0,value);
		write_reg(2,8'h08);send_frame(8'h78,8,0,0,0);read_reg(1,value);check(!value[3] && !irq,"DTR disables receive");
		write_reg(2,8'h09);dcd_n=1;tick(20);read_reg(1,value);check(value[7]&&value[5],"DCD transition IRQ/status");check(!irq,"DCD acknowledges");
		send_frame(8'h45,8,0,0,0);read_reg(1,value);check(!value[3],"no receive without carrier");dcd_n=0;tick(20);read_reg(1,value);
		dsr_n=1;tick(20);read_reg(1,value);check(value[7]&&value[6],"DSR transition IRQ/status");check(!irq,"DSR acknowledges");dsr_n=0;tick(20);read_reg(1,value);
		write_reg(2,8'h0d);tick(20);check(tx===0,"break asserted");tick(bit_cycles*12);check(tx===0,"break held");write_reg(2,8'h09);tick(20);check(tx===1,"break released");
		cts_n=1;tick(20);write_reg(0,8'h7e);tick(bit_cycles*12);check(tx===1,"CTS blocks new transmission");read_reg(1,value);check(!value[4],"CTS masks TDRE");
		fork begin expect_frame(8'h7e,8,0,start1);end begin cts_n=0;end join
		tick(bit_cycles*2);write_reg(2,8'h05);tick(20);check(irq,"TX empty IRQ enabled");write_reg(2,8'h09);read_reg(1,value);check(!irq,"TX IRQ acknowledged after disable");
		// Echo mode forwards a complete received serial frame with RTS asserted.
		write_reg(2,8'h19);
		fork begin send_frame(8'ha6,8,0,0,0);end begin expect_frame(8'ha6,8,0,start1);end join
		read_reg(1,value);read_reg(0,value);check(value==8'ha6,"echo also receives the word");
		write_reg(2,8'h09);tick(bit_cycles*2);
		// A short low glitch must not be accepted as a start bit.
		rx=0;tick(8);rx=1;tick(bit_cycles*12);read_reg(1,value);check(!value[3],"false start rejected");
		// Programmed reset clears only the documented receive overrun flag.
		send_frame(8'ha1,8,0,0,0);send_frame(8'hb2,8,0,0,0);write_reg(1,0);read_reg(1,value);check(value[3]&&!value[2],"program reset preserves unread data and clears overrun");read_reg(0,value);check(value==8'hb2,"program reset preserves received word");
		$display("PASS 6551 errors, resets, handshake and interrupt semantics (%0d checks)",checks);
		$finish;
	end
	initial begin #100000000; $fatal(1,"ACIA test timeout");end
endmodule
