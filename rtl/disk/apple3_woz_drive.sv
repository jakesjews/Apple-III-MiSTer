// Main serves native/converted WOZ through the standard MiSTer block interface.
module apple3_woz_drive (
    input wire clk, reset, change, enabled,
    input wire [63:0] image_size,
    input wire image_readonly, protect,
    input wire active, motor_on,
    input wire [3:0] phases,
    input wire write_mode, write_bit, write_strobe,
    output wire flux, ready, write_protect,
    output wire [31:0] sd_lba,
    output wire [5:0] sd_blk_cnt,
    output wire sd_rd, sd_wr,
    input wire sd_ack,
    input wire [13:0] sd_buff_addr,
    input wire [7:0] sd_buff_dout,
    output wire [7:0] sd_buff_din,
    input wire sd_buff_wr
);
    reg present = 0, mount = 0, readonly = 1;
    reg [63:0] size = 0;
    always @(posedge clk) begin
        if (change) begin
            present <= image_size != 0;
            size <= image_size;
            readonly <= image_readonly;
        end
        // A replacement needs a low interval even if another image was mounted.
        // Presence survives machine reset so the header is parsed again.
        if (reset || !enabled || change) mount <= 0;
        else mount <= present;
    end

    // The analog card gates head/write I/O separately from spindle power.
    reg [3:0] drive_phases = 0;
    always @(posedge clk) begin
        if (reset) drive_phases <= 0;
        else if (active) drive_phases <= phases;
    end
    wire [8:0] head;
    wire [7:0] track_id = head >= 9'd2 ? head[7:0] - 8'd2 : 8'd0;
    wire [15:0] bit_addr, write_addr;
    wire [7:0] bit_data, write_data, timing;
    wire [31:0] bit_count, flux_size, flux_ticks;
    wire mounted, valid, load_done, is_flux, info_wp, mismatch, bit_we;
    wire engine_reset = reset || !enabled;
    assign ready = mounted && !mismatch;
    assign write_protect = readonly || protect || info_wp || !ready || is_flux || bit_count == 0;

    flux_drive drive (
        .IS_35_INCH(1'b0), .DRIVE_ID(2'd0), .CLK_14M(clk), .RESET(engine_reset),
        .PHASES(drive_phases), .IMMEDIATE_PHASES(drive_phases), .LATCHED_SENSE_REG(3'd0),
        .IWM_MODE(5'd0), .MOTOR_ON(motor_on), .SW_MOTOR_ON(motor_on),
        .DISKREG_SEL(1'b0), .SEL35(1'b0), .DRIVE_SELECT(1'b0), .DRIVE_SLOT(1'b0),
        .DISK_MOUNTED(ready), .DISK_WP(write_protect || !valid), .DOUBLE_SIDED(1'b0),
        .FLUX_TRANSITION(flux), .WRITE_PROTECT(), .SENSE(), .DISK_SWITCHED_OUT(),
        .STEP_BUSY_OUT(), .STEP_DIR_OUT(), .MOTOR_ON_SENSE_OUT(), .AT_TRACK0_OUT(),
        .MOTOR_SPINNING(), .DRIVE_READY(), .TRACK(), .HEAD_QTRACK(head), .EJECT_REQ(),
        .BIT_POSITION(), .BIT_TIMER_OUT(), .TRACK_BIT_COUNT(bit_count),
        .TRACK_LOADED(valid && ready), .TRACK_LOAD_COMPLETE(load_done),
        .BRAM_ADDR(bit_addr), .BRAM_DATA(bit_data), .OPTIMAL_BIT_TIMING(timing),
        .IS_FLUX_TRACK(is_flux), .FLUX_DATA_SIZE(flux_size), .FLUX_TOTAL_TICKS(flux_ticks),
        .WRITE_BIT(write_bit), .WRITE_STROBE(write_strobe && active),
        .WRITE_MODE(write_mode && active), .WRITE_BYTE_OUT(write_data),
        .WRITE_WE_OUT(bit_we), .WRITE_ADDR_OUT(write_addr), .SD_TRACK_REQ(),
        .SD_TRACK_STROBE(), .SD_TRACK_ACK(1'b0), .CHUNK_RELOAD_REQ(), .CHUNK_NEEDED(),
        .CHUNK_LOADED(2'd0), .CHUNK_LOADING(1'b0)
    );
    woz_floppy_controller #(.IS_35_INCH(0)) image (
        .clk, .reset(engine_reset), .sd_lba, .sd_blk_cnt, .sd_rd, .sd_wr, .sd_ack,
        .sd_buff_addr, .sd_buff_dout, .sd_buff_din, .sd_buff_wr,
        .img_mounted(mount), .img_readonly(readonly), .img_size(size),
        .track_id, .ready(), .disk_mounted(mounted), .busy(), .active,
        .bit_count, .bit_addr, .stable_side(1'b0), .bit_data,
        .bit_data_in(write_data), .bit_we(bit_we && !write_protect && valid),
        .bit_wr_addr(write_addr), .track_load_complete(load_done),
        .is_flux_track(is_flux), .flux_data_size(flux_size), .flux_total_ticks(flux_ticks),
        .track_data_valid(valid), .disk_type_mismatch(mismatch),
        .disk_write_protected(info_wp), .optimal_bit_timing(timing),
        .dbg_load_sum(), .dbg_load_bytes(), .dbg_load_blocks()
    );
endmodule
