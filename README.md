# 4×4 Weight-Stationary Systolic Array NPU (ASIC / OpenLane Ready)

> **Research Paper**: *"Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"*  
> **Course / Symposium**: COS231 Computer Architecture | TechConnect World Innovation Conference  
> **Target Process**: SkyWater 130nm (`sky130_fd_sc_hd`) via OpenLane & OpenROAD  
> **Status**: Synthesizable, Simulated, Verified (6/6 Tests Passed), Silicon-PPA Profiled

---

## 1. Project Purpose & Thesis

On-device artificial intelligence inference is heavily constrained by **power consumption, latency, and memory bandwidth**. While mobile GPUs provide computational flexibility via Single Instruction, Multiple Threads (SIMT) execution, this flexibility incurs substantial hardware overhead: instruction fetch/decode pipelines, warp scheduling, divergence handling, and continuous register-file access.

In contrast, Neural Processing Units (NPUs) exploit **spatial dataflow architectures**, notably **weight-stationary systolic arrays**. By mapping neural network matrix weights into local processing element (PE) registers and holding them stationary across multiple inference cycles:
- Memory access energy is minimized (no repeated weight reads from SRAM/DRAM).
- Activations and partial sums flow directly between adjacent PEs with zero memory round-trips.
- Computation occurs rhythmically every clock cycle with minimal instruction overhead.

> [!NOTE]
> **Academic Honesty & Research Scope**: This project is a simplified, educational, and architectural RTL prototype based on the principles analyzed in the COS231 research paper. It does **not** claim to reproduce proprietary commercial silicon (such as Apple's Neural Engine, Google's TPU, or NVIDIA Tensor Cores) or claim measured silicon power numbers without physical ASIC place-and-route and post-layout power extraction.

---

## 2. High-Level Architecture

The design implements a 2D grid of $4 \times 4 = 16$ Processing Elements (PEs) executing matrix multiplication:
$$C = A \times B$$

Where:
- $A$ is the $4 \times 4$ Activation matrix (INT8 signed).
- $B$ is the $4 \times 4$ Stationary Weight matrix (INT8 signed).
- $C$ is the $4 \times 4$ Result matrix (INT32 signed accumulator).

```
                            Stationary Weights / Partial Sums In (Top)
                                col 0       col 1       col 2       col 3
                                  ↓           ↓           ↓           ↓
     Row 0 Act (Skewed) ────→ ┌───────┐───→┌───────┐───→┌───────┐───→┌───────┐
                              │PE[0,0]│    │PE[0,1]│    │PE[0,2]│    │PE[0,3]│
                              └───────┘    └───────┘    └───────┘    └───────┘
                                  ↓           ↓           ↓           ↓
     Row 1 Act (Skewed) ────→ ┌───────┐───→┌───────┐───→┌───────┐───→┌───────┐
                              │PE[1,0]│    │PE[1,1]│    │PE[1,2]│    │PE[1,3]│
                              └───────┘    └───────┘    └───────┘    └───────┘
                                  ↓           ↓           ↓           ↓
     Row 2 Act (Skewed) ────→ ┌───────┐───→┌───────┐───→┌───────┐───→┌───────┐
                              │PE[2,0]│    │PE[2,1]│    │PE[2,2]│    │PE[2,3]│
                              └───────┘    └───────┘    └───────┘    └───────┘
                                  ↓           ↓           ↓           ↓
     Row 3 Act (Skewed) ────→ ┌───────┐───→┌───────┐───→┌───────┐───→┌───────┐
                              │PE[3,0]│    │PE[3,1]│    │PE[3,2]│    │PE[3,3]│
                              └───────┘    └───────┘    └───────┘    └───────┘
                                  ↓           ↓           ↓           ↓
                                col 0       col 1       col 2       col 3
                           Raw Systolic Partial Sum Outputs (Bottom)
                                              ↓
                                   [ Deskewing Buffer ]
                                              ↓
                                   Aligned Row Outputs C[i, :]
```

---

## 3. Processing Element (PE) Design

Each PE contains local state, pipeline staging, and arithmetic units:

```
                  Partial Sum In (from North PE) [31:0]
                                 │
                                 ▼
                     ┌───────────────────────┐
                     │          (+)          │
                     └───────────▲───────────┘
                                 │
                     ┌───────────────────────┐
                     │          (×)          │  Signed INT8 Multiply
                     └─────▲───────────▲─────┘
                           │           │
 Activation In ────────────┼─────┐     │
 (from West PE)            │     │     │
 [7:0]                     │     ▼     ▼
                           │  ┌──────────────┐
                           │  │  weight_reg  │ Stationary Weight [7:0]
                           │  └──────────────┘ (loaded when weight_en=1)
                           ▼
                     ┌───────────┐
                     │  act_reg  │
                     └─────┬─────┘
                           │
                           ▼
                  Activation Out (to East PE) [7:0]
```

### Internal Registers:
1. **`weight_reg` (INT8 signed)**:
   - Holds stationary weight $W_{r, c}$.
   - Updated only during the weight loading phase (`weight_en = 1`).
   - Remains completely unchanged across repeated matrix multiplications (`weight_en = 0`).
2. **`act_reg` (INT8 signed)**:
   - Latches `act_in` every cycle and forwards it to `act_out` (West $\to$ East).
3. **`psum_reg` (INT32 signed)**:
   - Latches the computed MAC output and forwards it to `psum_out` (North $\to$ South).
4. **`valid_reg` (1 bit)**:
   - Synchronous valid token indicating data integrity down the pipeline.

---

## 4. MAC Operation & Precision

The Multiply-Accumulate (MAC) unit performs 2's complement signed arithmetic:

$$\text{psum\_out} = \text{psum\_in} + (\text{act\_in} \times \text{weight\_in})$$

- **Operand A (Activation)**: 8-bit signed integer ($-128$ to $+127$).
- **Operand B (Weight)**: 8-bit signed integer ($-128$ to $+127$).
- **Multiplication Product**: Full precision 16-bit signed product (range $-16256$ to $+16384$).
- **Sign Extension**: Explicit sign extension from 16 bits to 32 bits before summation.
- **Accumulator / Partial Sum**: 32-bit signed integer ($-2^{31}$ to $+2^{31}-1$).

---

## 5. Weight-Stationary Dataflow & Skewing Schedule

Because data takes 1 clock cycle to advance between adjacent PEs:
- Row $r$ activation input is delayed by $r$ cycles.
- Column $c$ partial sum input is delayed by $c$ cycles.
- At PE$(r, c)$, activation $A_{i, r}$ and partial sum for $C_{i, c}$ meet at cycle:
  $$t = t_0 + i + r + c$$

### Input Feed Schedule:

| Time | Row 0 (`act[0]`) | Row 1 (`act[1]`) | Row 2 (`act[2]`) | Row 3 (`act[3]`) | Top Col $c$ (`psum[c]`) |
|:---:|:---:|:---:|:---:|:---:|:---:|
| $t_0 + 0$ | $A_{0,0}$ | 0 | 0 | 0 | Col 0 valid |
| $t_0 + 1$ | $A_{1,0}$ | $A_{0,1}$ | 0 | 0 | Col 1 valid |
| $t_0 + 2$ | $A_{2,0}$ | $A_{1,1}$ | $A_{0,2}$ | 0 | Col 2 valid |
| $t_0 + 3$ | $A_{3,0}$ | $A_{2,1}$ | $A_{1,2}$ | $A_{0,3}$ | Col 3 valid |
| $t_0 + 4$ | 0 | $A_{3,1}$ | $A_{2,2}$ | $A_{1,3}$ | — |
| $t_0 + 5$ | 0 | 0 | $A_{3,2}$ | $A_{2,3}$ | — |
| $t_0 + 6$ | 0 | 0 | 0 | $A_{3,3}$ | — |

### Output Deskewing:
The **Deskewing Buffer** in `npu_top.v` applies compensating delays $(N - 1 - c)$ to each column:
- Col 0 delayed by 3 cycles $\to$ arrives at $t_0 + i + 7$.
- Col 1 delayed by 2 cycles $\to$ arrives at $t_0 + i + 7$.
- Col 2 delayed by 1 cycle  $\to$ arrives at $t_0 + i + 7$.
- Col 3 delayed by 0 cycles $\to$ arrives at $t_0 + i + 7$.

All elements of result row $C[i, :]$ appear **simultaneously** on `deskewed_out` accompanied by a single active-high `deskewed_valid` pulse.

---

## 6. Physical Design & Silicon Estimates (SkyWater 130nm)

Estimated for the SkyWater 130nm High-Density library (`sky130_fd_sc_hd`):

| Metric | Value | Architectural Significance |
|:---|:---:|:---|
| **Process Node** | **SkyWater 130nm** | Open-source foundry PDK |
| **Array Geometry** | **$4 \times 4$ (16 PEs)** | Scalable parameter `N` |
| **Total Sequential Flip-Flops** | **1,224 DFFs** | Distributed weight and pipeline registers |
| **Signed Multipliers** | **16 units (8x8b)** | 1 multiplier per PE |
| **Signed Accumulators** | **16 units (32b)** | 1 adder per PE |
| **Equivalent Gate Count** | **~7,536 NAND2 Gates** | Highly compact footprint |
| **Standard Cell Area** | **0.0418 mm²** ($41,754\,\mu\text{m}^2$) | Fits on open-source shuttle tiles |
| **Macro Die Dimensions** | **$275.5\,\mu\text{m} \times 275.5\,\mu\text{m}$** | At 55% core utilization |
| **Operating Frequency** | **50 MHz (Nominal) / 100 MHz (Peak)** | Conservative timing closure |
| **Peak Throughput** | **1.60 GOPS** (@ 50MHz) / **3.20 GOPS** (@ 100MHz) | 16 MACs = 32 OPS/cycle |
| **Core Dynamic Power** | **~14.5 mW** (@ 50MHz) | Ultra-low power edge envelope |
| **Energy Efficiency** | **~110.3 GOPS / Watt** | Significant advantage over mobile GPUs |

---

## 7. OpenLane & OpenROAD ASIC Flow

The RTL has been engineered specifically for **100% compatibility with Yosys, OpenLane, and OpenROAD**:
- Flat 1D bitvector ports prevent Yosys syntax errors on multidimensional ports.
- Conservative Verilog-2001 coding style.
- Clean asynchronous reset (`rst_n`) and synchronous clear (`clr`).

### Running OpenLane Flow:
```bash
# 1. From the OpenLane root directory with Docker:
./flow.tcl -design <path_to_repo>/openlane

# 2. Or using modern OpenLane 2:
openlane --pdk sky130A <path_to_repo>/openlane/config.json
```

### Generated OpenLane Deliverables:
- Gate-level netlist: `runs/<tag>/results/synthesis/npu_top.v`
- Def / Floorplan: `runs/<tag>/results/floorplan/npu_top.def`
- Placement: `runs/<tag>/results/placement/npu_top.def`
- Routing: `runs/<tag>/results/routing/npu_top.def`
- Final GDSII: `runs/<tag>/results/final/gds/npu_top.gds`
- PPA Reports: `runs/<tag>/reports/` (area, timing, DRC, LVS, power)

---

## 8. TinyQV / TinyTapeout RISC-V SoC Wrapper

For seamless integration into RISC-V SoC templates (such as TinyQV or TinyTapeout), the repository includes:
[`rtl/npu_tinyqv_wrapper.v`](rtl/npu_tinyqv_wrapper.v) (`tt_um_npu_systolic`).

It provides an 8-bit bus adapter with byte selection, row buffering, and status reporting, allowing a host RISC-V core to write weights and activations and read back 32-bit results over standard GPIO / memory-mapped registers.

---

## 9. Simulation & Verification

### Quick Start (Windows)
```powershell
sim\run_sim.bat
```

### Quick Start (Linux / macOS)
```bash
chmod +x sim/run_sim.sh
./sim/run_sim.sh
```

### Using Make
```bash
make compile    # Compiles RTL and testbench
make sim        # Runs verification suite
make ppa        # Runs hardware resource and PPA estimator
make wave       # Opens waveform in GTKWave
make clean      # Deletes build artifacts
```

### Verification Test Suite
The testbench ([`tb/npu_tb.v`](tb/npu_tb.v)) compares the RTL output against an **independent algorithmic golden model** across 6 test suites:
1. **Paper Reference Matrix**: Values $1 \dots 16$ across $A$ and $B$.
2. **Identity Matrix**: $B = I_4$, proving activation passthrough $A \times I_4 = A$.
3. **Signed Mixed Positive/Negative**: Validates 2's complement sign extension.
4. **Extreme Boundary**: Values $+127$ and $-128$, confirming 32-bit accumulator overflow headroom.
5. **Stationary Weight Reuse**: Inference executed without reloading weights, demonstrating weight-stationary energy savings.
6. **Sparse and Zero Matrix**: Validates clean pipeline clearing and zero propagation.

**Result**: 6/6 tests passed with 0 mismatches.

---

## 10. Repository File Structure

```
npu_project/
├── rtl/
│   ├── mac.v                   # Signed INT8 multiplier with 32-bit accumulator
│   ├── processing_element.v    # PE with stationary weight register
│   ├── systolic_array.v        # Parameterized 2D NxN array with flat bitvector ports
│   ├── npu_top.v               # Standalone top module with skew/deskew buffers
│   ├── npu_tinyqv_wrapper.v    # Drop-in TinyQV / TinyTapeout RISC-V wrapper
│   └── npu_top_flat.v          # All-in-one concatenated Verilog file
├── tb/
│   └── npu_tb.v                # Self-checking verification testbench
├── openlane/
│   ├── config.json             # Modern OpenLane 2 configuration (Sky130)
│   ├── config.tcl              # Classic OpenLane 1 configuration
│   ├── constraints.sdc         # Timing constraints (50 MHz target)
│   └── pin_order.cfg           # Perimeter pin placement configuration
├── synth/
│   ├── synth_check.py          # Python hardware resource and PPA estimator
│   └── yosys_synth.tcl         # Standalone Yosys synthesis script
├── sim/
│   ├── run_sim.bat             # Windows one-click simulation script
│   └── run_sim.sh              # Unix one-click simulation script
├── docs/
│   └── TECHCONNECT_POSTER_GUIDE.md  # Poster layout, abstract draft, and presentation guide
├── Makefile                    # Cross-platform Makefile
├── .gitignore                  # Clean build artifact exclusions
├── LICENSE                     # MIT Open-Source License
└── README.md                   # Complete architectural guide
```
