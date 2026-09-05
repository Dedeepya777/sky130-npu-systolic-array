# ==============================================================================
# Synopsys Design Constraints (SDC) for npu_top
# Target Library: SkyWater 130nm (sky130_fd_sc_hd)
# Clock: 50 MHz (20.0 ns period)
# ==============================================================================

set clk_period 20.0
set clk_port   "clk"

create_clock -name clk -period $clk_period [get_ports $clk_port]

# Clock uncertainty and jitter (ASIC conservative estimates)
set_clock_uncertainty 0.25 [get_clocks clk]
set_clock_transition  0.15 [get_clocks clk]

# Input / Output Delays (20% of clock period)
set in_delay  [expr 0.20 * $clk_period]
set out_delay [expr 0.20 * $clk_period]

set_input_delay  $in_delay  -clock [get_clocks clk] [all_inputs -no_clocks]
set_output_delay $out_delay -clock [get_clocks clk] [all_outputs]

# Load and drive specifications for Sky130 HD standard cells
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 [all_inputs -no_clocks]
set_load 0.035 [all_outputs]
