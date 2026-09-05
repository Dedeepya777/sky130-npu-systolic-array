#!/usr/bin/env python3
# ==============================================================================
# Script: synth_check.py
# Description: Static Hardware Resource & PPA Estimator for 4x4 Systolic NPU
# Target: SkyWater 130nm (sky130_fd_sc_hd) and TechConnect Poster Metrics
# ==============================================================================

import sys

def compute_ppa():
    N = 4
    DATA_W = 8
    ACC_W = 32
    FREQ_MHZ = 50.0 # Standard conservative target for Sky130
    FREQ_MAX_MHZ = 100.0

    print("=" * 68)
    print(" 4x4 Weight-Stationary NPU - Static Hardware Resource & PPA Report ")
    print("=" * 68)

    # 1. Processing Element Resources
    pes = N * N
    pe_weight_dffs = pes * DATA_W
    pe_act_dffs = pes * DATA_W
    pe_psum_dffs = pes * ACC_W
    pe_valid_dffs = pes * 1
    total_pe_dffs = pe_weight_dffs + pe_act_dffs + pe_psum_dffs + pe_valid_dffs
    total_mult8x8 = pes
    total_add32 = pes

    # 2. Skew / Deskew Pipeline Registers
    # Skew stages: Row 0 (0), Row 1 (1), Row 2 (2), Row 3 (3) -> sum(1..N-1) = N*(N-1)/2
    skew_stages = (N * (N - 1)) // 2
    act_skew_dffs = skew_stages * DATA_W
    psum_skew_dffs = skew_stages * ACC_W
    valid_skew_dffs = skew_stages * 1

    # Deskew stages: Col 0 (3), Col 1 (2), Col 2 (1), Col 3 (0) -> sum(1..N-1) = N*(N-1)/2
    deskew_stages = (N * (N - 1)) // 2
    deskew_dffs = deskew_stages * ACC_W

    status_dffs = 2 # deskewed_valid_d, done

    total_dffs = total_pe_dffs + act_skew_dffs + psum_skew_dffs + valid_skew_dffs + deskew_dffs + status_dffs

    # 3. SkyWater 130nm Standard Cell Estimates (sky130_fd_sc_hd)
    # Average cell areas from Sky130 liberty / LEF:
    # sky130_fd_sc_hd__dfxtp_1 (DFF) ~ 14.5 um^2
    # sky130_fd_sc_hd__fa_1 (Full Adder) ~ 12.8 um^2
    # 8x8 signed Booth/Baugh-Wooley multiplier ~ 820 um^2
    # 32-bit fast adder (Kogge-Stone / Sklansky or ripple) ~ 340 um^2
    dff_unit_area = 14.5
    mult_unit_area = 820.0
    add_unit_area = 340.0
    glue_logic_factor = 1.15 # 15% routing / control glue logic

    dff_area = total_dffs * dff_unit_area
    mult_area = total_mult8x8 * mult_unit_area
    add_area = total_add32 * add_unit_area
    raw_cell_area = (dff_area + mult_area + add_area) * glue_logic_factor
    core_utilization = 0.55 # Target 55% density in OpenLane
    total_die_area = raw_cell_area / core_utilization

    # Equivalent Gate Count (NAND2X1 equivalent, area ~ 5.54 um^2 in Sky130)
    nand2_area = 5.54
    gate_count = int(raw_cell_area / nand2_area)

    # 4. Throughput & Computational Intensity
    # Each MAC performs 2 operations (1 Multiply + 1 Accumulate)
    ops_per_cycle = pes * 2 # 16 MACs * 2 = 32 OPS/cycle
    throughput_gops_50 = (ops_per_cycle * FREQ_MHZ) / 1000.0 # GOPS
    throughput_gops_100 = (ops_per_cycle * FREQ_MAX_MHZ) / 1000.0

    # Power Estimate (Sky130 standard dynamic power ~ 0.25 - 0.35 mW/MHz for this gate count)
    power_mw_50 = 14.5
    power_mw_100 = 28.0
    efficiency_50 = throughput_gops_50 / (power_mw_50 / 1000.0) # GOPS / Watt

    print(f"[-] Architecture Configuration:")
    print(f"    * Array Dimension (N x N)    : {N} x {N} ({pes} Processing Elements)")
    print(f"    * Activation Precision       : INT{DATA_W} signed")
    print(f"    * Weight Precision           : INT{DATA_W} signed (Weight-Stationary)")
    print(f"    * Partial Sum Precision      : INT{ACC_W} signed")
    print(f"    * Dataflow                   : Weight-Stationary Spatial Systolic")
    print()
    print(f"[-] Hardware Register & Logic Breakdown:")
    print(f"    * PE Stationary Weight DFFs  : {pe_weight_dffs} bits ({pes} x {DATA_W}b)")
    print(f"    * PE Activation Pipeline DFFs: {pe_act_dffs} bits")
    print(f"    * PE Partial Sum DFFs        : {pe_psum_dffs} bits ({pes} x {ACC_W}b)")
    print(f"    * Skew / Deskew Buffer DFFs  : {act_skew_dffs + psum_skew_dffs + valid_skew_dffs + deskew_dffs} bits")
    print(f"    * Total Sequential Flip-Flops: {total_dffs} DFFs")
    print(f"    * Signed 8x8 Multipliers     : {total_mult8x8} units")
    print(f"    * 32-bit Signed Adders       : {total_add32} units")
    print(f"    * Equivalent Gate Count (GE) : ~{gate_count:,} NAND2 gates")
    print()
    print(f"[-] Physical Design & Silicon Estimates (SkyWater 130nm - sky130_fd_sc_hd):")
    print(f"    * Standard Cell Logic Area   : {raw_cell_area:,.1f} um^2 ({raw_cell_area/1e6:.4f} mm^2)")
    print(f"    * Target Core Utilization    : {core_utilization*100:.0f}%")
    print(f"    * Recommended Floorplan Die  : {total_die_area:,.1f} um^2 ({total_die_area/1e6:.4f} mm^2)")
    print(f"    * Approximate Die Dimensions : {total_die_area**0.5:.1f} um x {total_die_area**0.5:.1f} um")
    print()
    print(f"[-] Performance & Energy Metrics:")
    print(f"    * Arithmetic Throughput @ 50MHz  : {throughput_gops_50:.2f} GOPS (16 MACs/cycle)")
    print(f"    * Arithmetic Throughput @ 100MHz : {throughput_gops_100:.2f} GOPS")
    print(f"    * Estimated Dynamic Power @ 50MHz: ~{power_mw_50:.1f} mW")
    print(f"    * Energy Efficiency              : ~{efficiency_50:.1f} GOPS / Watt")
    print("=" * 68)

if __name__ == '__main__':
    compute_ppa()
