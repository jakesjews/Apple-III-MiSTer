derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
# The Apple III video outputs are registered on the 14.318 MHz machine clock
# and sampled by video_mixer on CLK_VIDEO (4x) when ce_pix rises.  The pixel
# divider free-runs, so the capture edge can be any of the four CLK_VIDEO edges
# per machine-clock period.  Leave the crossing single-cycle constrained (the
# default relationship between the two PLL outputs) so TimeQuest verifies the
# worst case; no multicycle exception is applied.
