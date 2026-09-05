# ==============================================================================
# OpenLane Configuration (Tcl format) for SkyWater 130nm
# Design: npu_top (4x4 Weight-Stationary Systolic Array NPU)
# ==============================================================================

set ::env(DESIGN_NAME) "npu_top"

set ::env(VERILOG_FILES) "\
    $::env(DESIGN_DIR)/../rtl/mac.v \
    $::env(DESIGN_DIR)/../rtl/processing_element.v \
    $::env(DESIGN_DIR)/../rtl/systolic_array.v \
    $::env(DESIGN_DIR)/../rtl/npu_top.v"

# Clock configuration (50 MHz = 20ns period, conservative for Sky130 HD library)
set ::env(CLOCK_PORT) "clk"
set ::env(CLOCK_PERIOD) "20.0"

# Floorplan Configuration
set ::env(FP_SIZING) "relative"
set ::env(FP_CORE_UTIL) 55
set ::env(FP_ASPECT_RATIO) 1.0
set ::env(FP_PIN_ORDER_CFG) "$::env(DESIGN_DIR)/pin_order.cfg"

# Placement & Routing
set ::env(PL_TARGET_DENSITY) 0.60
set ::env(SYNTH_STRATEGY) "AREA 0"
set ::env(SYNTH_MAX_FANOUT) 12

# Timing & Constraints
set ::env(BASE_SDC_FILE) "$::env(DESIGN_DIR)/constraints.sdc"

# Signoff Checks
set ::env(MAGIC_DRC_USE_GDS) 1
set ::env(QUIT_ON_MAGIC_DRC) 0
set ::env(RUN_KLAYOUT_XOR) 0
set ::env(RUN_KLAYOUT_DRC) 0
