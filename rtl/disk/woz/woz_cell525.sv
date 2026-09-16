// WOZ INFO bit timing is in 125 ns units (32 = 4 us); WOZ1 uses 32.
// https://applesaucefdc.com/woz/reference2/
// Do not derive the bit rate from track length: that overrides intentionally
// fast/slow mastering. Quantization is one thousandth of a 14 MHz clock.
// This replaces the upstream 300-RPM normalization; see README.md.
module woz_cell525 (
    input wire clk,
    input wire [7:0] timing,
    output reg [8:0] cell_base,
    output reg [9:0] cell_step,
    output reg [8:0] half_base,
    output reg [9:0] half_step
);
    reg [37:0] timing_rom[0:255];
    function automatic [37:0] timing_entry(input integer ticks);
        reg [63:0] clocks;
        reg [8:0] full, half;
        reg [9:0] fraction, half_fraction;
        begin
            // All arithmetic is evaluated at synthesis time, not a run-time divider.
            clocks = (64'd14318181 * (ticks == 0 ? 64'd32 : ticks)) / 64'd8000;
            full = clocks / 1000;
            fraction = clocks % 1000;
            half = (clocks / 2) / 1000;
            half_fraction = (clocks / 2) % 1000;
            timing_entry = {full, fraction, half, half_fraction};
        end
    endfunction
    integer i;
    initial for (i=0;i<256;i=i+1) timing_rom[i] = timing_entry(i);
    always @(posedge clk)
        {cell_base,cell_step,half_base,half_step} <= timing_rom[timing];
endmodule
