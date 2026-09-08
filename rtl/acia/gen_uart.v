//============================================================================
//
//  8-bit UART modules
//  MOS 6551/MC6850/AY-31015/TR-1602
//  Copyright (C) 2025 Gyorgy Szombathelyi
//  Apple III adaptations (2026): see README.md for provenance and changes.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

///////////////////////////////////////////////////////////
///////////////////////// MOS 6551 ////////////////////////
///////////////////////////////////////////////////////////

module gen_uart_mos_6551(
	input        reset,
	input        clk,
	input        clk_en,
	input        rx_clk_en, // external RxC input as an enable
	input  [7:0] din,
	output reg [7:0] dout,
	input        rnw,
	input        cs,
	input  [1:0] rs,
	output       irq_n,
	input        cts_n,
	input        dcd_n,
	input        dsr_n,
	output       dtr_n,
	output       rts_n,
	input        rx,
	output       tx
);

reg  [3:0] clk_div;
reg        rec_clk;

reg        tx_start;
reg  [2:0] parity;
reg        echo;
reg  [1:0] tx_ctrl;
reg        dtr;
reg        stop;
reg  [1:0] wordlen;
reg  [7:0] tdr;
reg        tdr_full;
wire       tx_busy;

wire [7:0] rx_data;
wire       rx_full;
wire       rx_ovr;
wire       rx_fe;
wire       rx_pe;
reg        rx_nie;


reg        ext_irq;
reg        dcdb_latch;
reg        dsrb_latch;

wire [7:0] cmd = {parity, echo, tx_ctrl, rx_nie, dtr};
wire [7:0] ctrl = {stop, wordlen, rec_clk, clk_div};
wire [7:0] status = {~irq_n, dsrb_latch, dcdb_latch, (~tdr_full & ~cts_n), rx_full, rx_ovr, rx_fe, rx_pe};

assign     dtr_n = ~dtr;
assign     rts_n = tx_ctrl == 0;

// IRQ is a latch: reading RDR does not acknowledge it, reading status does.
// Apple boot ROM requires command=$00 (Rockwell behavior); the SY6551
// table in the service manual instead shows $02. See README.md.
wire div_en;
wire rx_event;
wire read_data = cs && rnw && rs == 0;
wire read_status = cs && rnw && rs == 1;
wire program_reset = cs && !rnw && rs == 1;
wire write_data = cs && !rnw && rs == 0;
wire tx_transfer = tdr_full && !tx_busy && !tx_start && !cts_n && !rts_n &&
                   tx_ctrl != 3 && !echo && !write_data && div_en;
reg irq_pending;

always @(posedge clk) begin
	if (reset) begin
		irq_pending <= 0;
		tx_start <= 0;
		dtr <= 0;
		rx_nie <= 0;
		tx_ctrl <= 0;
		echo <= 0;
		tdr_full <= 0;
		tdr <= 0;
		parity <= 0;
		rec_clk <= 0;
		clk_div <= 0;
		stop <= 0;
		wordlen <= 0;
		dcdb_latch <= dcd_n;
		dsrb_latch <= dsr_n;
		ext_irq <= 0;
	end else begin
		tx_start <= 0;
		if (read_status) begin
			irq_pending <= 0;
			ext_irq <= 0;
		end
		// Preserve modem status until software acknowledges the transition.
		if (!ext_irq || read_status) begin
			dcdb_latch <= dcd_n;
			dsrb_latch <= dsr_n;
			if (dtr && !read_status && ((dcdb_latch ^ dcd_n) || (dsrb_latch ^ dsr_n))) begin
				ext_irq <= 1;
				irq_pending <= 1;
			end
		end
		if (rx_event && dtr && !rx_nie && !read_status) irq_pending <= 1;
		// A transmitter-empty request persists while enabled. CTS masks TDRE.
		if (!tdr_full && !cts_n && dtr && tx_ctrl == 1 && !read_status)
			irq_pending <= 1;
		if (tx_transfer) begin
			tx_start <= 1;
			tdr_full <= 0;
		end
		if (cs && !rnw) begin
			case (rs)
				0: begin tdr <= din; tdr_full <= 1; end
				1: begin
					dtr <= 0;
					rx_nie <= 0;
					tx_ctrl <= 0;
					echo <= 0;
					irq_pending <= 0;
					ext_irq <= 0;
				end
				2: {parity, echo, tx_ctrl, rx_nie, dtr} <= din;
				3: {stop, wordlen, rec_clk, clk_div} <= din;
			endcase
		end
	end
end

assign irq_n = ~irq_pending;

always @(*) begin
	dout = 8'hff;
	begin
		case (rs)
			0: dout = rx_data;
			1: dout = status;
			2: dout = cmd;
			3: dout = ctrl;
			default: ;
		endcase
	end
end

wire baud_div_en;
gen_uart_mos_6551_baud_gen baud_gen(reset, clk, clk_en, clk_div, baud_div_en);
assign div_en = clk_div == 0 ? rx_clk_en : baud_div_en;

wire rx_echo, tx_out;
assign tx = tx_ctrl == 3 ? 1'b0 : echo ? ((dtr && !rts_n) ? rx_echo : 1'b1) : tx_out;

gen_uart_rx #(.ALT_OVR(1'b1)) gen_uart_rx(
	.reset(reset),
	.enable(dtr && !dcd_n),
	.clear_overrun(program_reset),
	.event_ready(rx_event),
	.reset_flags(read_data),
	.clk(clk),
	.clk_en(rec_clk ? baud_div_en : rx_clk_en),
	.clk_mult(2'd1),
	.wordlen(wordlen),
	.parity_en(parity[0]),
	.parity_ctrl(parity[2:1]),
	.rx_data(rx_data),
	.rx(rx),
	.rx_echo(rx_echo),
	.fe(rx_fe),
	.pe(rx_pe),
	.ovr(rx_ovr),
	.full(rx_full)
);

gen_uart_tx gen_uart_tx(
	.reset(reset),
	.clk(clk),
	.clk_en(div_en),
	.clk_mult(2'd1),
	.wordlen(wordlen),
	.stop_len(!stop || (wordlen == 0 && parity[0]) ? 2'd0 :
	          wordlen == 3 && !parity[0] ? 2'd1 : 2'd2),
	.parity_en(parity[0]),
	.parity_ctrl(parity[2:1]),
	.tx_data(tdr),
	.start(tx_start),
	.busy(tx_busy),
	.tx(tx_out)
);

endmodule

module gen_uart_mos_6551_baud_gen(
	input        reset,
	input        clk,
	input        clk_en,
	input  [3:0] clk_div,
	output       div_en
);

reg  [11:0] cnt;
reg  [11:0] cnt_val;
always @(*) begin
	case (clk_div)
	 1: cnt_val = 2303; // 50
	 2: cnt_val = 1535; // 75
	 3: cnt_val = 1047; // 109.92
	 4: cnt_val = 855;  // 134.58
	 5: cnt_val = 767;  // 150
	 6: cnt_val = 383;  // 300
	 7: cnt_val = 191;  // 600
	 8: cnt_val = 95;   // 1200
	 9: cnt_val = 63;   // 1800
	10: cnt_val = 47;   // 2400
	11: cnt_val = 31;   // 3600
	12: cnt_val = 23;   // 4800
	13: cnt_val = 15;   // 7200
	14: cnt_val = 11;   // 9600
	15: cnt_val = 5;    // 19200
	default: cnt_val = 0;
	endcase
end

assign div_en = clk_en && cnt == cnt_val;

always @(posedge clk) begin
	if (reset)
		cnt <= 0;
	else if (clk_en) begin
		cnt <= cnt + 1'd1;
		if (cnt == cnt_val) cnt <= 0;
	end
end

endmodule

///////////////////////////////////////////////////////////
////////////////// Generic UART receiver //////////////////
///////////////////////////////////////////////////////////

module gen_uart_rx(
	input        reset,
	input        enable,
	input        clear_overrun,
	output reg   event_ready,
	input        reset_flags,
	input        clk,
	input        clk_en,
	input  [1:0] clk_mult, // 0 - 1x, 1 - 16x, 2 - 64x
	input  [1:0] wordlen, // 8,7,6,5
	input        parity_en,
	input  [1:0] parity_ctrl, // odd, even, mark, space
	output reg [7:0] rx_data,
	input        rx,
	output reg   rx_echo,
	output reg   pe,
	output reg   fe,
	output reg   ovr,
	output reg   full
);

// alternate overrun handling
// default - if overrun, don't copy the shift register to rx_data
// AY-31015 copies anyway
parameter ALT_OVR = 1'b0;

reg  [5:0] cnt;
reg  [5:0] start_pos;
reg  [7:0] shift_reg;
reg  [3:0] bit_cnt;
reg        bit_en;
reg        parity;
reg        parity_err;
reg  [7:0] rx_next;

reg  [3:0] rx_filter;
reg        rx_filtered;
wire       rx_in = |clk_mult ? rx_filtered : rx;

always @(posedge clk) begin
	if (reset) begin
		cnt <= 0;
		bit_en <= 0;
		rx_filter <= 4'b1111;
		rx_filtered <= 1;
	end else begin
		bit_en <= 0;
		if (clk_en) begin
			rx_filter <= { rx, rx_filter[3:1] };
			if ({ rx, rx_filter[3:1] }  == 4'b0000) rx_filtered <= 0;
			if ({ rx, rx_filter[3:1] }  == 4'b1111) rx_filtered <= 1;
			cnt <= cnt + 1'd1;
			case (clk_mult)
				1: bit_en <= cnt[3:0] == (start_pos[3:0] + 4'd7);
				2: bit_en <= cnt == (start_pos + 6'd31);
				default: bit_en <= 1;
			endcase
		end
	end
end

always @(*)
	case (wordlen)
		1: rx_next = { 1'd0, shift_reg[7:1] };
		2: rx_next = { 2'd0, shift_reg[7:2] };
		3: rx_next = { 3'd0, shift_reg[7:3] };
		default: rx_next = shift_reg[7:0];
	endcase

always @(*)
	case (parity_ctrl)
		0: parity_err = ~(^rx_next ^ parity); // odd
		1: parity_err = ^rx_next ^ parity; // even
		default: parity_err = 0;
	endcase

always @(posedge clk) begin
	if (reset) begin
		pe <= 0;
		fe <= 0;
		ovr <= 0;
		full <= 0;
		bit_cnt <= 0;
		event_ready <= 0;
		rx_data <= 0;
		rx_echo <= 1;
		start_pos <= 0;
	end else begin
		event_ready <= 0;
		if (clear_overrun) ovr <= 0;
		if (reset_flags) begin
			fe <= 0;
			ovr <= 0;
			pe <= 0;
			full <= 0;
		end
		if (bit_en) rx_echo <= rx_in;
		if (enable && bit_cnt == 0 && !rx_in) begin
			// start bit detected
			bit_cnt <= 4'd10 - wordlen + parity_en;
			start_pos <= cnt; // mark the position for middle sampling
		end
		if (!enable) bit_cnt <= 0;
		if (enable && bit_en && bit_cnt != 0) begin
			bit_cnt <= bit_cnt - 1'd1;
			shift_reg <= { rx_in, shift_reg[7:1] };
			if (bit_cnt == 2) begin
				parity <= rx_in;
				if (parity_en) shift_reg <= shift_reg; // don't shift in parity bit
			end
			// Reject a pulse that has returned high at the start-bit midpoint.
			if (bit_cnt == 4'd10 - wordlen + parity_en && rx_in) bit_cnt <= 0;
			if (bit_cnt == 1) begin
				event_ready <= 1;
				full <= 1;
				if (!rx_in) // check for valid stop bit
					fe <= 1;
				if (ALT_OVR) begin
					if (full) ovr <= 1;
					rx_data <= rx_next;
					pe <= parity_err & parity_en;
				end else begin
					if (full)
						// If the previous word wasn't read by the CPU, signal overrun,
						// and don't copy the shift register to the receive data register.
						ovr <= 1;
					else begin
						rx_data <= rx_next;
						pe <= parity_err & parity_en;
					end
				end
			end
		end
	end
end

endmodule

///////////////////////////////////////////////////////////
//////////////// Generic UART transmitter /////////////////
///////////////////////////////////////////////////////////

module gen_uart_tx(
	input        reset,
	input        clk,
	input        clk_en,
	input  [1:0] clk_mult, // 0 - 1x, 1 - 16x, 2 - 64x
	input  [1:0] wordlen, // 8,7,6,5
	input  [1:0] stop_len, // 0 - 1 stop, 1 - 1.5 stops, 2 - 2 stops
	input        parity_en,
	input  [1:0] parity_ctrl, // odd, even, mark, space
	input  [7:0] tx_data,
	input        start,
	output       busy,
	output       tx
);
reg  [6:0] cnt;
reg [10:0] shift_reg;
reg  [3:0] bit_cnt;
reg        stopping;
reg        parity;
reg  [6:0] stop_ticks;
wire [6:0] ticks_per_bit = clk_mult == 0 ? 7'd1 : clk_mult == 1 ? 7'd16 : 7'd64;
wire [7:0] word_mask = 8'hff >> wordlen;

always @(*) begin
	if (!parity_en) parity = 1;
	else case (parity_ctrl)
		0: parity = ~^(tx_data & word_mask);
		1: parity = ^(tx_data & word_mask);
		2: parity = 1;
		default: parity = 0;
	endcase
end

assign busy = bit_cnt != 0 || stopping;
assign tx = shift_reg[0];

always @(posedge clk) begin
	if (reset) begin
		cnt <= 0;
		bit_cnt <= 0;
		stopping <= 0;
		stop_ticks <= 0;
		shift_reg <= 11'h7ff;
	end else if (start && !busy) begin
		cnt <= 0;
		bit_cnt <= 4'd9 - wordlen + parity_en; // start + data + optional parity
		shift_reg <= {2'b11, tx_data, 1'b0};
		case (wordlen)
			0: shift_reg[10:9] <= {1'b1, parity};
			1: shift_reg[10:8] <= {2'b11, parity};
			2: shift_reg[10:7] <= {3'b111, parity};
			3: shift_reg[10:6] <= {4'b1111, parity};
		endcase
		stop_ticks <= stop_len == 2 ? (ticks_per_bit << 1) - 1'b1 :
		              stop_len == 1 ? ticks_per_bit + (ticks_per_bit >> 1) - 1'b1 :
		              ticks_per_bit - 1'b1;
	end else if (clk_en && busy) begin
		cnt <= cnt + 1'b1;
		if (stopping) begin
			if (cnt == stop_ticks) begin stopping <= 0; cnt <= 0; end
		end else if (cnt == ticks_per_bit - 1'b1) begin
			cnt <= 0;
			bit_cnt <= bit_cnt - 1'b1;
			shift_reg <= {1'b1, shift_reg[10:1]};
			if (bit_cnt == 1) stopping <= 1;
		end
	end
end
endmodule
