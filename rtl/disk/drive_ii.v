//-------------------------------------------------------------------------------
//--
//-- Disk II emulator - drive part
//--
//-- This feeds "pre-nibblized" data to the processor.
//--
//-- Original by Stephen A. Edwards, sedwards@cs.columbia.edu
//-- Write support by (c)2022 Gyorgy Szombathelyi
//--
//-------------------------------------------------------------------------------
module drive_ii(CLK_14M, CLK_2M, PHASE_ZERO, RESET, DISK_READY, D_IN, D_OUT, DISK_ACTIVE, MOTOR_PHASE, WRITE_MODE, READ_DISK, WRITE_REG, TRACK_ZERO_STEP, TRACK, TRACK_ADDR, TRACK_DI, TRACK_DO, TRACK_WE, TRACK_BUSY);
   input        CLK_14M;
   input        CLK_2M;
   input        PHASE_ZERO;
   input        RESET;
   input        DISK_READY;
   input [7:0]  D_IN;
   output [7:0] D_OUT;
   input        DISK_ACTIVE;
   input [3:0]  MOTOR_PHASE;
   input        WRITE_MODE;
   input        READ_DISK;
   input        WRITE_REG;
   output reg   TRACK_ZERO_STEP;
   output [5:0] TRACK;
   output [12:0] TRACK_ADDR;
   output [7:0] TRACK_DI;
   input [7:0]  TRACK_DO;
   output       TRACK_WE;
   reg          TRACK_WE;
   input        TRACK_BUSY;

   reg          CLK_2M_D;

   reg [7:0]    phase;

   reg [12:0]    track_byte_addr;
   reg [7:0]    data_reg;
   reg          reset_data_reg;


   always @(posedge CLK_14M or posedge RESET)
   begin: update_phase
      integer      phase_change;
      integer      new_phase;
      reg [3:0]    rel_phase;
      if (RESET == 1'b1) begin
         phase <= 8'd70;
         TRACK_ZERO_STEP <= 1'b0;
      end else
      begin
         TRACK_ZERO_STEP <= 1'b0;
         if (DISK_ACTIVE == 1'b1)
         begin
            phase_change = 0;
            new_phase = {24'd0, phase};
            rel_phase = MOTOR_PHASE;
            case (phase[2:1])
               2'b00 :
                  rel_phase = {rel_phase[1:0], rel_phase[3:2]};
               2'b01 :
                  rel_phase = {rel_phase[2:0], rel_phase[3]};
               2'b10 :
                  ;
               2'b11 :
                  rel_phase = {rel_phase[0], rel_phase[3:1]};
               default :
                  ;
            endcase

            if (phase[0] == 1'b1)
               case (rel_phase)
                  4'b0000 :
                     phase_change = 0;
                  4'b0001 :
                     phase_change = -3;
                  4'b0010 :
                     phase_change = -1;
                  4'b0011 :
                     phase_change = -2;
                  4'b0100 :
                     phase_change = 1;
                  4'b0101 :
                     phase_change = -1;
                  4'b0110 :
                     phase_change = 0;
                  4'b0111 :
                     phase_change = -1;
                  4'b1000 :
                     phase_change = 3;
                  4'b1001 :
                     phase_change = 0;
                  4'b1010 :
                     phase_change = 1;
                  4'b1011 :
                     phase_change = -3;
                  4'b1111 :
                     phase_change = 0;
                  default :
                     ;
               endcase
            else
               case (rel_phase)
                  4'b0000 :
                     phase_change = 0;
                  4'b0001 :
                     phase_change = -2;
                  4'b0010 :
                     phase_change = 0;
                  4'b0011 :
                     phase_change = -1;
                  4'b0100 :
                     phase_change = 2;
                  4'b0101 :
                     phase_change = 0;
                  4'b0110 :
                     phase_change = 1;
                  4'b0111 :
                     phase_change = 0;
                  4'b1000 :
                     phase_change = 0;
                  4'b1001 :
                     phase_change = 1;
                  4'b1010 :
                     phase_change = 2;
                  4'b1011 :
                     phase_change = -2;
                  4'b1111 :
                     phase_change = 0;
                  default :
                     ;
               endcase

            if (new_phase + phase_change <= 0) begin
               if (phase_change < 0)
                  TRACK_ZERO_STEP <= 1'b1;
               new_phase = 0;
            end else if (new_phase + phase_change > 139)
               new_phase = 139;
            else
               new_phase = new_phase + phase_change;
            phase <= new_phase[7:0];
         end
      end
   end

   assign TRACK = phase[7:2];


   always @(posedge CLK_14M or posedge RESET)
   begin: read_head
      reg [5:0]    byte_delay;
      if (RESET == 1'b1)
      begin
         track_byte_addr <= {13{1'b0}};
         byte_delay = {6{1'b0}};
         reset_data_reg <= 1'b0;
         CLK_2M_D <= CLK_2M;
         data_reg <= 8'h00;
         TRACK_WE <= 1'b0;
      end
      else
      begin
         TRACK_WE <= 1'b0;

         CLK_2M_D <= CLK_2M;
         if (CLK_2M == 1'b1 & CLK_2M_D == 1'b0 & DISK_READY == 1'b1 & DISK_ACTIVE == 1'b1)
         begin
            byte_delay = byte_delay - 6'd1;

            if (WRITE_MODE == 1'b0)
            begin
               if (reset_data_reg == 1'b1)
               begin
                  data_reg <= {8{1'b0}};
                  reset_data_reg <= 1'b0;
               end

               if (byte_delay == 0)
               begin
                  data_reg <= TRACK_DO;
                  if (track_byte_addr == 13'h19FF)
                     track_byte_addr <= {13{1'b0}};
                  else
                     track_byte_addr <= track_byte_addr + 13'd1;
               end
               if (READ_DISK == 1'b1 & PHASE_ZERO == 1'b1)
                  reset_data_reg <= 1'b1;
            end
            else
            begin
               if (WRITE_REG == 1'b1)
                  data_reg <= D_IN;
               if (READ_DISK == 1'b1 & PHASE_ZERO == 1'b1)
               begin
                  TRACK_WE <= (~TRACK_BUSY);
                  if (track_byte_addr == 13'h19FF)
                     track_byte_addr <= {13{1'b0}};
                  else
                     track_byte_addr <= track_byte_addr + 13'd1;
               end
            end
         end
      end
   end

   assign D_OUT = data_reg;
   assign TRACK_ADDR = track_byte_addr;
   assign TRACK_DI = data_reg;

endmodule
