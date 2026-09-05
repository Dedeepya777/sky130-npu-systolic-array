# ==============================================================================
# Makefile: 4x4 Weight-Stationary Systolic Array NPU (ASIC / OpenLane Ready)
# Project: COS231 Computer Architecture Research & TechConnect Poster
# Target: Icarus Verilog, Yosys, OpenLane, OpenROAD, SkyWater 130nm
# ==============================================================================

SIM_DIR    := sim
RTL_DIR    := rtl
TB_DIR     := tb
SYNTH_DIR  := synth
OPENLANE_DIR := openlane

IVERILOG   := iverilog
VVP        := vvp
GTKWAVE    := gtkwave
PYTHON     := python3

TOP_MODULE := npu_tb

SRCS       := $(RTL_DIR)/mac.v \
              $(RTL_DIR)/processing_element.v \
              $(RTL_DIR)/systolic_array.v \
              $(RTL_DIR)/npu_top.v \
              $(TB_DIR)/npu_tb.v

TARGET_VVP := $(SIM_DIR)/npu_sim.vvp
VCD_FILE   := $(SIM_DIR)/npu_sim.vcd

.PHONY: all compile sim wave ppa clean help

all: compile sim

help:
	@echo "4x4 Weight-Stationary NPU Build Targets:"
	@echo "  make compile - Compile Verilog RTL and testbench with iverilog"
	@echo "  make sim     - Run the simulation testbench using vvp"
	@echo "  make wave    - Open the generated waveform (VCD) in GTKWave"
	@echo "  make ppa     - Generate hardware resource and Sky130 PPA estimation report"
	@echo "  make clean   - Remove compilation artifacts and waveform files"
	@echo "  make all     - Compile and run simulation (default)"

$(SIM_DIR):
	mkdir -p $(SIM_DIR)

compile: $(SRCS) | $(SIM_DIR)
	@echo "[BUILD] Compiling Verilog RTL and testbench..."
	$(IVERILOG) -Wall -s $(TOP_MODULE) -o $(TARGET_VVP) $(SRCS)
	@echo "[BUILD] Compilation successful -> $(TARGET_VVP)"

sim: compile
	@echo "[SIM] Running NPU verification suite..."
	$(VVP) $(TARGET_VVP)

wave:
	@echo "[WAVE] Opening $(VCD_FILE) in GTKWave..."
	$(GTKWAVE) $(VCD_FILE) &

ppa:
	@$(PYTHON) $(SYNTH_DIR)/synth_check.py

clean:
	@echo "[CLEAN] Removing build artifacts..."
	rm -f $(TARGET_VVP) $(VCD_FILE)
