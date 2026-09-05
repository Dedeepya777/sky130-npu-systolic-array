#!/usr/bin/env bash
# ==============================================================================
# Script: run_sim.sh
# Description: Bash simulation script for 4x4 Weight-Stationary Systolic Array NPU
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

echo "================================================================"
echo " COS231 Research: 4x4 Weight-Stationary NPU Simulation Runner"
echo "================================================================"

mkdir -p sim

if ! command -v iverilog &> /dev/null; then
    echo "[ERROR] iverilog (Icarus Verilog) not found in PATH."
    echo "Please install iverilog (e.g., sudo apt install iverilog or conda install -c conda-forge iverilog)."
    exit 1
fi

echo "[STEP 1/2] Compiling Verilog RTL and Testbench..."
iverilog -Wall -s npu_tb \
    -o sim/npu_sim.vvp \
    rtl/mac.v \
    rtl/processing_element.v \
    rtl/systolic_array.v \
    rtl/npu_top.v \
    tb/npu_tb.v

echo "[STEP 1/2] Compilation successful!"

echo "[STEP 2/2] Executing Simulation..."
vvp sim/npu_sim.vvp

echo ""
echo "[COMPLETE] Simulation finished. Waveform written to sim/npu_sim.vcd"
echo "To view waveforms: gtkwave sim/npu_sim.vcd"
