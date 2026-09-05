# ==============================================================================
# Script: yosys_synth.tcl
# Description: Standalone Yosys Synthesis Script for npu_top
# Target: Generic Technology Mapping and Standard Cell Statistics
# ==============================================================================

# 1. Read Verilog Design Files
read_verilog rtl/mac.v
read_verilog rtl/processing_element.v
read_verilog rtl/systolic_array.v
read_verilog rtl/npu_top.v

# 2. Elaborate Top Module
hierarchy -check -top npu_top

# 3. High-Level Synthesis & Optimization
proc
opt
wreduce
opt

# 4. Arithmetic & Multiplier Mapping
alumacc
share
opt
fsm
opt

# 5. Technology Mapping to Generic Gates
techmap
opt

# 6. Flip-Flop Mapping
dfflegalize -cell $_DFF_P_ 01
opt

# 7. Print Hardware Statistics
stat

# 8. Write Gate-Level Netlist
write_verilog -noattr sim/npu_synth_netlist.v
