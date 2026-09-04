// 
// Apple ][ track read/write interface to MiST
//
// Based on the work of
// Copyright (c) 2016 Sorgelig
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
/////////////////////////////////////////////////////////////////////////

module floppy_track
(
	input         clk,
	input         reset,

	output [31:0] sd_lba,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,

	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	input         change,
	input         mount,
	// A 143,360-byte sector image is nibblized on the fly; a 232,960-byte NIB
	// is used as-is.  MiSTer's own dsk2nib is gated on the core being named
	// "apple-ii"/"TK2000", so the conversion has to happen here.
	input         dsk_mode,
	input         prodos,
	input   [5:0] track,
	output reg    ready = 0,
	input         active,

	input  [12:0] ram_addr,
	output  [7:0] ram_do,
	input   [7:0] ram_di,
	input         ram_we,
	output reg    busy
);

assign sd_lba = lba;

reg  [31:0] lba;
reg   [3:0] rel_lba;

// Blocks per track: 13 (6656-byte nibble track) or 8 (4096-byte sector track).
wire [3:0] last_rel_lba = dsk_mode ? 4'd7 : 4'd12;
wire [31:0] track_lba = dsk_mode ? (track * 8'd8) : (track * 8'd13);

reg  nibblize;
reg  nib_seen;          // converter has actually started
reg  nib_start;         // one-cycle request
reg  [5:0] nib_track;   // cur_track is local to the process below
wire nib_busy;
wire [11:0] nib_src_addr;
wire  [7:0] nib_src_data;
wire [12:0] nib_dst_addr;
wire  [7:0] nib_dst_data;
wire        nib_dst_we;

always @(posedge clk) begin
	reg old_ack;
	reg [5:0] cur_track = 0;
	reg old_change;
	reg saving = 0;
	reg dirty = 0;

	old_change <= change;
	old_ack <= sd_ack;

	if(sd_ack) {sd_rd,sd_wr} <= 0;

	if(ready && ram_we && !dsk_mode) dirty <= 1;

	if(~old_change & change) begin
		ready <= mount;
		cur_track <= 'b111111;
		busy  <= 0;
		sd_rd <= 0;
		sd_wr <= 0;
		saving<= 0;
		dirty <= 0;
		nibblize <= 0;
		nib_seen <= 0;
		nib_start <= 0;
	end
	else
	if(reset) begin
		cur_track <= 'b111111;
		busy  <= 0;
		sd_rd <= 0;
		sd_wr <= 0;
		saving<= 0;
		dirty <= 0;
		nibblize <= 0;
		nib_seen <= 0;
		nib_start <= 0;
	end
	else

	if(nibblize) begin
		// Hold busy across the conversion so the drive sees an empty latch
		// rather than the previous track's bytes.  Wait for the converter to
		// raise busy before testing for completion.
		nib_start <= 0;
		if(nib_busy) nib_seen <= 1;
		else if(nib_seen) begin
			nibblize <= 0;
			nib_seen <= 0;
			busy <= 0;
			dirty <= 0;
		end
	end
	else
	if(busy) begin
		if(old_ack && ~sd_ack) begin
			if(rel_lba != last_rel_lba) begin
				lba <= lba + 1'd1;
				rel_lba <= rel_lba + 1'd1;
				if(saving) sd_wr <= 1;
					else sd_rd <= 1;
			end
			else
			if(saving && (cur_track != track)) begin
				saving <= 0;
				cur_track <= track;
				rel_lba <= 0;
				lba <= track_lba;
				sd_rd <= 1;
			end
			else
			if(dsk_mode && !saving) begin
				nibblize  <= 1;
				nib_start <= 1;
				nib_seen  <= 0;
				nib_track <= cur_track;
			end
			else
			begin
				busy <= 0;
				dirty <= 0;
			end
		end
	end
	else
	if(ready && ((cur_track != track) || (old_change && ~change) || (dirty && ~active)))
		if (dirty && cur_track != 'b111111) begin
			saving <= 1;
			lba <= cur_track * 8'd13;
			rel_lba <= 0;
			sd_wr <= 1;
			busy <= 1;
		end
		else
		begin
			saving <= 0;
			cur_track <= track;
			rel_lba <= 0;
			lba <= track_lba;
			sd_rd <= 1;
			busy <= 1;
			dirty <= 0;
		end
end


// Sector-image staging buffer: one 4096-byte track of raw sectors.
dpram #(12,8) sector_dpram
(
        .clock_a(clk),
        .address_a({rel_lba[2:0], sd_buff_addr}),
        .wren_a(sd_buff_wr & sd_ack & dsk_mode),
        .data_a(sd_buff_dout),
        .q_a(),

        .clock_b(clk),
        .address_b(nib_src_addr),
        .wren_b(1'b0),
        .data_b(8'd0),
        .q_b(nib_src_data)
);

dsk_nibblizer nibblizer
(
        .clk(clk),
        .reset(reset),
        .start(nib_start),
        .busy(nib_busy),
        .track(nib_track),
        .prodos(prodos),
        .src_addr(nib_src_addr),
        .src_data(nib_src_data),
        .dst_addr(nib_dst_addr),
        .dst_data(nib_dst_data),
        .dst_we(nib_dst_we)
);

wire [12:0] host_addr = dsk_mode ? nib_dst_addr : {rel_lba, sd_buff_addr};
wire        host_we   = dsk_mode ? nib_dst_we   : (sd_buff_wr & sd_ack);
wire  [7:0] host_data = dsk_mode ? nib_dst_data : sd_buff_dout;

dpram #(13,8) floppy_dpram
(
        .clock_a(clk),
        .address_a(host_addr),
        .wren_a(host_we),
        .data_a(host_data),
        .q_a(sd_buff_din),

        .clock_b(clk),
        .address_b(ram_addr),
        .wren_b(ram_we),
        .data_b(ram_di),
        .q_b(ram_do)

);

/*
// Dual port track buffer
reg   [7:0] track_ram[13*512];

// IO controller side
always @(posedge clk) begin
	sd_buff_din <= track_ram[{rel_lba, sd_buff_addr}];
	if (sd_buff_wr & sd_ack) track_ram[{rel_lba, sd_buff_addr}] <= sd_buff_dout;
end

// Disk controller side
always @(posedge clk) begin
	ram_do <= track_ram[ram_addr];
	if (ram_we) track_ram[ram_addr] <= ram_di;
end
*/
endmodule
