// Converts one track of a 143,360-byte sector image (DSK/DO/PO) into the
// 6,656-byte 6-and-2 nibble track the Disk II datapath expects.
//
// MiSTer's host-side dsk2nib translation is gated on the core name being
// "apple-ii" or "TK2000" (user_io.cpp), so an Apple /// core has to do this
// itself.  The field layout, sector ordering and the Apple /// synchronized
// track volume key follow sim/coretest/dsk2nib.h, which is also what
// tools/dsk2nib.cpp emits; sim/nib_tb.sv checks this module byte-for-byte
// against that reference.
//
// One sector emits 38 sync + 3 address prologue + 8 address (4-and-4) +
// 3 epilogue + 8 sync + 3 data prologue + 343 data (6-and-2) + 3 epilogue
// = 409 bytes.  Sixteen sectors are 6,544 bytes; the remainder of the
// 6,656-byte track is left as sync bytes.

module dsk_nibblizer (
	input  logic        clk,
	input  logic        reset,

	input  logic        start,        // one-cycle request
	output logic        busy,
	input  logic [5:0]  track,        // physical track, 0..34
	input  logic        prodos,       // 0 = DOS 3.3 order, 1 = ProDOS order

	// Sector-data staging RAM for this track (16 x 256 bytes), read port.
	output logic [11:0] src_addr,
	input  logic [7:0]  src_data,

	// Nibble track RAM, write port.
	output logic [12:0] dst_addr,
	output logic [7:0]  dst_data,
	output logic        dst_we
);

	localparam int TRACK_BYTES = 13 * 512;   // 6656

	function automatic [7:0] gcr(input logic [5:0] index);
		case (index)
			6'd00: gcr = 8'h96; 6'd01: gcr = 8'h97; 6'd02: gcr = 8'h9a; 6'd03: gcr = 8'h9b;
			6'd04: gcr = 8'h9d; 6'd05: gcr = 8'h9e; 6'd06: gcr = 8'h9f; 6'd07: gcr = 8'ha6;
			6'd08: gcr = 8'ha7; 6'd09: gcr = 8'hab; 6'd10: gcr = 8'hac; 6'd11: gcr = 8'had;
			6'd12: gcr = 8'hae; 6'd13: gcr = 8'haf; 6'd14: gcr = 8'hb2; 6'd15: gcr = 8'hb3;
			6'd16: gcr = 8'hb4; 6'd17: gcr = 8'hb5; 6'd18: gcr = 8'hb6; 6'd19: gcr = 8'hb7;
			6'd20: gcr = 8'hb9; 6'd21: gcr = 8'hba; 6'd22: gcr = 8'hbb; 6'd23: gcr = 8'hbc;
			6'd24: gcr = 8'hbd; 6'd25: gcr = 8'hbe; 6'd26: gcr = 8'hbf; 6'd27: gcr = 8'hcb;
			6'd28: gcr = 8'hcd; 6'd29: gcr = 8'hce; 6'd30: gcr = 8'hcf; 6'd31: gcr = 8'hd3;
			6'd32: gcr = 8'hd6; 6'd33: gcr = 8'hd7; 6'd34: gcr = 8'hd9; 6'd35: gcr = 8'hda;
			6'd36: gcr = 8'hdb; 6'd37: gcr = 8'hdc; 6'd38: gcr = 8'hdd; 6'd39: gcr = 8'hde;
			6'd40: gcr = 8'hdf; 6'd41: gcr = 8'he5; 6'd42: gcr = 8'he6; 6'd43: gcr = 8'he7;
			6'd44: gcr = 8'he9; 6'd45: gcr = 8'hea; 6'd46: gcr = 8'heb; 6'd47: gcr = 8'hec;
			6'd48: gcr = 8'hed; 6'd49: gcr = 8'hee; 6'd50: gcr = 8'hef; 6'd51: gcr = 8'hf2;
			6'd52: gcr = 8'hf3; 6'd53: gcr = 8'hf4; 6'd54: gcr = 8'hf5; 6'd55: gcr = 8'hf6;
			6'd56: gcr = 8'hf7; 6'd57: gcr = 8'hf9; 6'd58: gcr = 8'hfa; 6'd59: gcr = 8'hfb;
			6'd60: gcr = 8'hfc; 6'd61: gcr = 8'hfd; 6'd62: gcr = 8'hfe; default: gcr = 8'hff;
		endcase
	endfunction

	// Physical-to-logical sector map. DOS-order images need the 3.3 interleave;
	// ProDOS-order images are first remapped through the ProDOS table.
	function automatic [3:0] dos_order(input logic [3:0] i);
		case (i)
			4'h0: dos_order = 4'h0; 4'h1: dos_order = 4'h7;
			4'h2: dos_order = 4'he; 4'h3: dos_order = 4'h6;
			4'h4: dos_order = 4'hd; 4'h5: dos_order = 4'h5;
			4'h6: dos_order = 4'hc; 4'h7: dos_order = 4'h4;
			4'h8: dos_order = 4'hb; 4'h9: dos_order = 4'h3;
			4'ha: dos_order = 4'ha; 4'hb: dos_order = 4'h2;
			4'hc: dos_order = 4'h9; 4'hd: dos_order = 4'h1;
			4'he: dos_order = 4'h8; default: dos_order = 4'hf;
		endcase
	endfunction

	function automatic [3:0] prodos_order(input logic [3:0] i);
		case (i)
			4'h0: prodos_order = 4'h0; 4'h1: prodos_order = 4'he;
			4'h2: prodos_order = 4'hd; 4'h3: prodos_order = 4'hc;
			4'h4: prodos_order = 4'hb; 4'h5: prodos_order = 4'ha;
			4'h6: prodos_order = 4'h9; 4'h7: prodos_order = 4'h8;
			4'h8: prodos_order = 4'h7; 4'h9: prodos_order = 4'h6;
			4'ha: prodos_order = 4'h5; 4'hb: prodos_order = 4'h4;
			4'hc: prodos_order = 4'h3; 4'hd: prodos_order = 4'h2;
			4'he: prodos_order = 4'h1; default: prodos_order = 4'hf;
		endcase
	endfunction

	// A sector image cannot carry the address-field volume bytes the Apple ///
	// synchronized-track check reads from tracks 9..16, so emit the same key
	// a3dsk2woz writes.
	function automatic [7:0] volume_byte(input logic [5:0] t, input logic [3:0] s);
		logic [7:0] key;
		logic [3:0] key_sector;
		begin
			case (t)
				6'd9:  begin key = 8'hb4; key_sector = 4'd2;  end
				6'd10: begin key = 8'hc1; key_sector = 4'd14; end
				6'd11: begin key = 8'he4; key_sector = 4'd10; end
				6'd12: begin key = 8'hf3; key_sector = 4'd6;  end
				6'd13: begin key = 8'h9b; key_sector = 4'd2;  end
				6'd14: begin key = 8'hbd; key_sector = 4'd14; end
				6'd15: begin key = 8'hbd; key_sector = 4'd10; end
				6'd16: begin key = 8'h7c; key_sector = 4'd6;  end
				default: begin key = 8'hfe; key_sector = 4'hf; end
			endcase
			volume_byte = ((t >= 6'd9) && (t <= 6'd16) && (s == key_sector)) ?
			              key : 8'hfe;
		end
	endfunction

	function automatic [1:0] swap_low(input logic [1:0] bits);
		case (bits)
			2'd0: swap_low = 2'd0; 2'd1: swap_low = 2'd2;
			2'd2: swap_low = 2'd1; default: swap_low = 2'd3;
		endcase
	endfunction

	typedef enum logic [4:0] {
		S_IDLE, S_SYNC1, S_ADDR_PRO, S_ADDR, S_ADDR_EPI, S_SYNC2, S_DATA_PRO,
		S_SEC_SEED_A, S_SEC_SEED_B, S_SEC_BUILD, S_SEC_MASK,
		S_EMIT_SEC, S_EMIT_PRI, S_EMIT_CHK, S_DATA_EPI, S_TAIL, S_DONE
	} state_t;

	state_t state;
	logic [3:0]  sector;
	logic [12:0] out_index;
	logic [8:0]  counter;        // general purpose step counter
	logic [7:0]  secondary [0:85];
	logic [6:0]  target;
	logic [8:0]  source;
	logic [7:0]  previous;
	logic [7:0]  addr_field [0:7];
	logic [3:0]  logical_sector;
	logic [1:0]  read_phase;

	wire [11:0] sector_base = {logical_sector, 8'h00};
	wire [7:0]  volume = volume_byte(track, sector);
	wire [7:0]  address_checksum = volume ^ {2'b00, track} ^ {4'h0, sector};

	// Emit one byte and advance the output pointer.
	task automatic emit(input logic [7:0] value);
		begin
			dst_addr <= out_index;
			dst_data <= value;
			dst_we   <= 1'b1;
			out_index <= out_index + 1'b1;
		end
	endtask

	integer i;

	always_ff @(posedge clk) begin
		dst_we <= 1'b0;

		if (reset) begin
			state <= S_IDLE;
			busy  <= 1'b0;
			dst_we <= 1'b0;
			out_index <= 13'd0;
		end
		else begin
			case (state)
				S_IDLE: begin
					busy <= 1'b0;
					if (start) begin
						busy      <= 1'b1;
						sector    <= 4'd0;
						out_index <= 13'd0;
						counter   <= 9'd0;
						state     <= S_SYNC1;
					end
				end

				// 38 sync bytes ahead of the address field.
				S_SYNC1: begin
					emit(8'hff);
					if (counter == 9'd37) begin
						counter <= 9'd0;
						state   <= S_ADDR_PRO;
					end
					else counter <= counter + 1'b1;
				end

				S_ADDR_PRO: begin
					case (counter[1:0])
						2'd0: emit(8'hd5);
						2'd1: emit(8'haa);
						default: emit(8'h96);
					endcase
					if (counter[1:0] == 2'd2) begin
						// Build the 4-and-4 address field now that volume is known.
						addr_field[0] <= (volume >> 1) | 8'haa;
						addr_field[1] <= volume | 8'haa;
						addr_field[2] <= ({2'b00, track} >> 1) | 8'haa;
						addr_field[3] <= {2'b00, track} | 8'haa;
						addr_field[4] <= ({4'h0, sector} >> 1) | 8'haa;
						addr_field[5] <= {4'h0, sector} | 8'haa;
						addr_field[6] <= (address_checksum >> 1) | 8'haa;
						addr_field[7] <= address_checksum | 8'haa;
						counter <= 9'd0;
						state   <= S_ADDR;
					end
					else counter <= counter + 1'b1;
				end

				S_ADDR: begin
					emit(addr_field[counter[2:0]]);
					if (counter[2:0] == 3'd7) begin
						counter <= 9'd0;
						state   <= S_ADDR_EPI;
					end
					else counter <= counter + 1'b1;
				end

				S_ADDR_EPI: begin
					case (counter[1:0])
						2'd0: emit(8'hde);
						2'd1: emit(8'haa);
						default: emit(8'heb);
					endcase
					if (counter[1:0] == 2'd2) begin
						counter <= 9'd0;
						state   <= S_SYNC2;
					end
					else counter <= counter + 1'b1;
				end

				// 8 sync bytes between the address and data fields.
				S_SYNC2: begin
					emit(8'hff);
					if (counter == 9'd7) begin
						counter <= 9'd0;
						state   <= S_DATA_PRO;
					end
					else counter <= counter + 1'b1;
				end

				S_DATA_PRO: begin
					case (counter[1:0])
						2'd0: emit(8'hd5);
						2'd1: emit(8'haa);
						default: emit(8'had);
					endcase
					if (counter[1:0] == 2'd2) begin
						// Resolve which logical sector supplies this physical one.
						logical_sector <= dos_order(prodos ? prodos_order(sector) : sector);
						read_phase <= 2'd0;
						state      <= S_SEC_SEED_A;
					end
					else counter <= counter + 1'b1;
				end

				// secondary[0] = swap(sector[1]), secondary[1] = swap(sector[0]).
				S_SEC_SEED_A: begin
					src_addr <= sector_base + 12'd1;
					if (read_phase == 2'd2) begin
						secondary[0] <= {6'd0, swap_low(src_data[1:0])};
						read_phase   <= 2'd0;
						state        <= S_SEC_SEED_B;
					end
					else read_phase <= read_phase + 1'b1;
				end

				S_SEC_SEED_B: begin
					src_addr <= sector_base;
					if (read_phase == 2'd2) begin
						secondary[1] <= {6'd0, swap_low(src_data[1:0])};
						read_phase   <= 2'd0;
						source       <= 9'd255;
						target       <= 7'd2;
						state        <= S_SEC_BUILD;
					end
					else read_phase <= read_phase + 1'b1;
				end

				// Walk the sector backwards, packing two swapped low bits into a
				// rotating set of 86 accumulators.
				S_SEC_BUILD: begin
					src_addr <= sector_base + source[7:0];
					if (read_phase == 2'd2) begin
						secondary[target] <= (secondary[target] << 2) |
						                     {6'd0, swap_low(src_data[1:0])};
						read_phase <= 2'd0;
						target     <= (target == 7'd85) ? 7'd0 : target + 1'b1;
						if (source == 9'd0) begin
							counter <= 9'd0;
							state   <= S_SEC_MASK;
						end
						else source <= source - 1'b1;
					end
					else read_phase <= read_phase + 1'b1;
				end

				S_SEC_MASK: begin
					for (i = 0; i < 86; i = i + 1)
						secondary[i] <= secondary[i] & 8'h3f;
					previous <= 8'h00;
					source   <= 9'd85;
					state    <= S_EMIT_SEC;
				end

				// 86 secondary bytes, most significant index first.
				S_EMIT_SEC: begin
					emit(gcr(previous[5:0] ^ secondary[source[6:0]][5:0]));
					previous <= secondary[source[6:0]];
					if (source == 9'd0) begin
						source     <= 9'd0;
						read_phase <= 2'd0;
						state      <= S_EMIT_PRI;
					end
					else source <= source - 1'b1;
				end

				// 256 primary bytes: the top six bits of each sector byte.
				S_EMIT_PRI: begin
					src_addr <= sector_base + source[7:0];
					if (read_phase == 2'd2) begin
						emit(gcr(previous[5:0] ^ src_data[7:2]));
						previous   <= {2'b00, src_data[7:2]};
						read_phase <= 2'd0;
						if (source == 9'd255) state <= S_EMIT_CHK;
						else source <= source + 1'b1;
					end
					else read_phase <= read_phase + 1'b1;
				end

				S_EMIT_CHK: begin
					emit(gcr(previous[5:0]));
					counter <= 9'd0;
					state   <= S_DATA_EPI;
				end

				S_DATA_EPI: begin
					case (counter[1:0])
						2'd0: emit(8'hde);
						2'd1: emit(8'haa);
						default: emit(8'heb);
					endcase
					if (counter[1:0] == 2'd2) begin
						counter <= 9'd0;
						if (sector == 4'hf) state <= S_TAIL;
						else begin
							sector <= sector + 1'b1;
							state  <= S_SYNC1;
						end
					end
					else counter <= counter + 1'b1;
				end

				// Pad the rest of the track with sync bytes.
				S_TAIL: begin
					emit(8'hff);
					if (out_index == TRACK_BYTES - 1) state <= S_DONE;
				end

				S_DONE: begin
					busy  <= 1'b0;
					state <= S_IDLE;
				end

				default: state <= S_IDLE;
			endcase
		end
	end

endmodule
