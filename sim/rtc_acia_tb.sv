`timescale 1ns / 1ps

module rtc_acia_tb;
	logic clk = 0, reset = 1;
	logic [64:0] host_rtc = 0;
	logic rtc_read = 0, rtc_write = 0;
	logic [4:0] rtc_addr = 0;
	logic [7:0] data_in = 0;
	wire  [7:0] rtc_data;
	wire        rtc_irq;

	apple3_rtc #(
		.CLOCKS_PER_MS(4)
	) rtc (
		.clk,
		.reset,
		.host_rtc,
		.read_strobe (rtc_read),
		.write_strobe(rtc_write),
		.addr        (rtc_addr),
		.data_in,
		.data_out    (rtc_data),
		.irq         (rtc_irq)
	);
	always #5 clk = ~clk;

	initial begin
		repeat (2) @(posedge clk);
		reset           = 0;
		// Host clock: 12:34:56, Friday, 09/04/26.
		host_rtc[6:0]   = 7'h56;
		host_rtc[14:8]  = 7'h34;
		host_rtc[21:16] = 6'h12;
		host_rtc[50:48] = 3'd5;
		host_rtc[29:24] = 6'h04;
		host_rtc[36:32] = 5'h09;
		host_rtc[47:40] = 8'h26;
		host_rtc[64]    = 1;
		@(posedge clk);
		#1;
		rtc_addr = 5'h02;
		#1;
		if (rtc_data !== 8'h56) $fatal(1, "RTC host seconds=%02x", rtc_data);
		rtc_addr = 5'h06;
		#1;
		if (rtc_data !== 8'h04) $fatal(1, "RTC host day=%02x", rtc_data);

		// Ten milliseconds advances the hundredths/tenths register once.
		repeat (40) @(posedge clk);
		#1;
		rtc_addr = 5'h01;
		#1;
		if (rtc_data !== 8'h01) $fatal(1, "RTC ten milliseconds=%02x", rtc_data);

		$display("PASS apple3_rtc");
		$finish;
	end
endmodule
