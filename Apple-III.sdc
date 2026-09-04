derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
# Apple III pixels are produced by the 14.318 MHz machine clock and captured by
# gamma_corr only when ce_pix rises, once every four 57.273 MHz video clocks.
set apple3_machine_clock [get_clocks {*|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]
set apple3_gamma_capture_regs [get_registers -nowarn {
	*video_out|gamma|R_in*
	*video_out|gamma|G_in*
	*video_out|gamma|B_in*
	*video_out|gamma|hs
	*video_out|gamma|vs
	*video_out|gamma|hb
	*video_out|gamma|vb
	*video_out|gamma|gamma_index*
	*video_out|gamma|gamma_curve_rtl_0|*portb_address_reg*
}]

if {[get_collection_size $apple3_machine_clock] != 1} {
	post_message -type error "Apple III machine clock constraint matched [get_collection_size $apple3_machine_clock] clocks"
}
if {[get_collection_size $apple3_gamma_capture_regs] == 0} {
	post_message -type error "Apple III gamma capture constraint matched no registers"
}

set_multicycle_path -from $apple3_machine_clock -to $apple3_gamma_capture_regs -setup 4
set_multicycle_path -from $apple3_machine_clock -to $apple3_gamma_capture_regs -hold 3
