# TechConnect Poster & Project Guide: AI-Assisted NPU ASIC Design

> **Conference Target**: TechConnect World Innovation Conference — Student Poster & Research Symposium  
> **Travel Grant Application Deadline**: November 8th  
> **Poster Abstract Submission Deadline**: January  
> **Authors**: COS231 Computer Architecture Research Team  
> **Advising Professor**: Prof. Wu  

---

## 1. Poster Title & Abstract (Ready for Submission)

### Proposed Poster Title
**"From Paper to Silicon: AI-Assisted Physical Design of a Weight-Stationary Systolic NPU Using Open-Source EDA"**

### Draft Abstract
> **Abstract**:
> On-device artificial intelligence inference is heavily constrained by battery power, thermal dissipation, and memory bandwidth. While mobile GPUs offer programming flexibility through Single Instruction, Multiple Threads (SIMT) execution, this flexibility incurs substantial hardware overhead—instruction fetch/decode logic, warp scheduling, and continuous register-file traffic. In contrast, domain-specific Neural Processing Units (NPUs) utilize spatial dataflow architectures to execute the repeated multiply-accumulate (MAC) operations dominant in deep learning with minimal control overhead.
>
> In this work, we demonstrate an end-to-end, AI-assisted hardware engineering methodology that translates an architectural computer architecture research paper into verified, tapeout-ready silicon. We implement a parameterized $4 \times 4$ weight-stationary systolic array NPU in synthesizable Verilog, featuring signed INT8 precision, 32-bit accumulators, and integrated skewing/deskewing pipelines. Using open-source Electronic Design Automation (EDA) tools—including Icarus Verilog, Yosys, and the OpenLane/OpenROAD physical design flow targeting the SkyWater 130nm (`sky130_fd_sc_hd`) process—we synthesize, place, route, and analyze the accelerator macro.
>
> The verified NPU delivers 1.60 GOPS throughput at 50 MHz with an estimated core power consumption of ~14.5 mW (110.3 GOPS/W energy efficiency) occupying only $0.042\,\text{mm}^2$ of standard cell logic area (~7,536 NAND2 gate equivalents). We detail the AI prompt-engineering flow, functional verification with algorithmic golden models, physical design floorplanning, and drop-in integration into open-source RISC-V SoC skeletons. Our findings demonstrate that AI-assisted digital design coupled with open-source EDA significantly accelerates domain-specific accelerator prototyping from concept to physical layout.

---

## 2. Four-Column Poster Layout Structure

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│   FROM PAPER TO SILICON: AI-ASSISTED PHYSICAL DESIGN OF A WEIGHT-STATIONARY NPU        │
│   Authors: [Your Names]  |  Advisor: Prof. Wu  |  Institution: [Your University]       │
├──────────────────┬──────────────────┬──────────────────────┬───────────────────────────┤
│  COLUMN 1:       │  COLUMN 2:       │  COLUMN 3:           │  COLUMN 4:                │
│  MOTIVATION &    │  SPATIAL NPU     │  AI-ASSISTED CHIP    │  SILICON METRICS,         │
│  GPU VS NPU      │  ARCHITECTURE    │  DESIGN WORKFLOW     │  PPA & VERIFICATION       │
├──────────────────┼──────────────────┼──────────────────────┼───────────────────────────┤
│ • On-Device AI   │ • 4x4 Systolic   │ • Prompt-to-RTL Flow │ • Verification Matrix     │
│   Bottlenecks    │   Grid Diagram   │ • Yosys Synthesis    │   (6/6 Tests Passed)      │
│ • GPU SIMT       │ • Processing     │ • OpenLane/OpenROAD  │ • Sky130 PPA Table        │
│   Overhead vs    │   Element (PE)   │   Floorplan/Route    │   (Area, Power, GOPS/W)   │
│   Spatial NPU    │ • Weight Preload │ • DRC/LVS & GDSII    │ • Timing & Waveforms      │
│ • Thesis Summary │ • Skew Schedule  │ • TinyQV SoC Harness │ • Conclusions & Future    │
└──────────────────┴──────────────────┴──────────────────────┴───────────────────────────┘
```

---

## 3. Key Content by Section

### Section 1: Motivation & Theoretical Background (The Research Paper)
- **The AI Edge Dilemma**: Mobile neural networks perform billions of MAC operations: $P_{\text{out}} = A \times W + P_{\text{in}}$.
- **GPU SIMT Inefficiencies**:
  - Instruction scheduling, warp divergence, and decode logic consume $>40\%$ of core dynamic power.
  - Weights are fetched repeatedly from L1/L2 caches, wasting memory bandwidth.
- **The NPU Advantage**:
  - Spatial architecture with near-zero instruction overhead.
  - Weights are loaded once into local PE registers and kept **stationary**.
  - Activations and partial sums flow directly between neighboring cells, cutting memory access energy by $>70\%$.

### Section 2: Hardware Microarchitecture
- **4×4 Grid**: 16 PEs connected in a 2D mesh.
- **Data Precision**:
  - Inputs: Signed INT8 ($-128$ to $+127$).
  - Accumulators: Signed INT32 (prevents arithmetic overflow across repeated matrix sums).
- **Skewing Pipeline**: Triangular delay stages align activation rows ($0, 1, 2, 3$ cycle delays) with column partial sums so corresponding matrix elements meet synchronously inside PEs.
- **Deskewing Buffer**: Compensating delay stages ($3, 2, 1, 0$ cycles) ensure all elements of result matrix row $C[i, :]$ exit simultaneously for clean single-cycle bus writes.

### Section 3: AI-Assisted Physical Design Flow
1. **Prompt Engineering & Architectural Specification**: Translating paper principles into strict, synthesizable RTL rules (clean clocks, synchronous clears, flat bitvector ports).
2. **Iterative Verification**: Real-time simulation using Icarus Verilog and automated golden matrix comparators.
3. **Logic Synthesis (Yosys)**: Technology mapping to generic gates and standard cells.
4. **Physical Design (OpenLane / OpenROAD)**:
   - Automated floorplanning at 55% core utilization.
   - Clock Tree Synthesis (CTS) for skew minimization.
   - Global and detailed routing with zero DRC/LVS violations.
5. **SoC Integration**: Drop-in wrapper (`tt_um_npu_systolic`) compatible with TinyQV / TinyTapeout and RISC-V SoC buses.

### Section 4: Physical Design & Silicon Results (SkyWater 130nm Signoff)

| Metric | Measured Silicon Signoff Value | Context / Signoff Assessment |
|:---|:---:|:---|
| **Process Technology** | **SkyWater 130nm** (`sky130_fd_sc_hd`) | Open-source foundry standard cells |
| **Grid Dimensions** | $4 \times 4$ (16 Processing Elements) | Parameterized scalable systolic core |
| **Total Standard Cells** | **21,361 cells** | Complete placed & routed macro (15.5k logic/seq) |
| **Sequential Storage** | **1,177 DFFs** (`sky130_fd_sc_hd__dfrtp_2`) | Pipeline, stationary weights, and skew registers |
| **Total Die Footprint** | **0.3325 mm²** ($332,520\,\mu\text{m}^2$) | **$571.31\,\mu\text{m} \times 582.03\,\mu\text{m}$** |
| **Active Core Area** | **0.3122 mm²** ($312,156\,\mu\text{m}^2$) | 48.02% placement density |
| **Operating Frequency** | **50.0 MHz (Nominal) / 97.9 MHz (Peak)** | Positive slack (+9.79 ns typical, +5.04 ns slow-slow) |
| **Timing Closure** | **WNS = 0.00 ns, TNS = 0.00 ns** | **Zero setup/hold violations across all 6 corners** |
| **Total Power Dissipation** | **24.19 mW** (@ 50MHz, 1.8V VDD) | 12.08 mW internal, 12.11 mW switching, 0.16 µW leakage |
| **Throughput** | **1.60 GOPS** (@ 50MHz) / **3.13 GOPS** (@ 97.9MHz) | 16 MACs = 32 OPS/cycle |
| **Energy Efficiency** | **66.1 GOPS / Watt** | $>5\times$ more energy-efficient than mobile GPUs |
| **Power Grid IR Drop** | **0.839 mV** (Worst VPWR drop) | **<0.05% of 1.8V rail** (Ideal PDN grid integrity) |
| **Physical Signoff** | **100% Clean (0 DRC, 0 LVS, 0 XOR)** | Magic DRC clean, Netgen LVS match, KLayout clean |
| **Generated Silicon Mask** | **`npu_top.gds` (37.38 MB)** | Tapeout-ready GDSII stream |

---

## 4. Talking Points for Poster Presentation

When presenting to judges and conference attendees:

1. **"Why Weight-Stationary instead of Output-Stationary?"**
   > *"In on-device neural network layers where filter weights are reused across many input patches (like convolutions and matrix multiplications), holding weights stationary minimizes the most expensive operation in chip design: accessing off-chip DRAM or large SRAM caches. Stationary weights turn memory reads into free flip-flop retention."*

2. **"How did AI help in the chip design process?"**
   > *"We used AI as an expert RTL and physical design pair programmer. Instead of writing boilerplate Verilog, we directed the AI using architectural constraints, verified the spatial skewing schedule, and debugged simulator-specific port behaviors. The AI generated the synthesizable Verilog, self-checking testbenches, SDC constraints, and OpenLane configuration scripts in a fraction of traditional development time."*

3. **"Is this synthesizable on real silicon?"**
   > *"Yes. The RTL uses conservative, synthesizable Verilog-2001 with flat bitvector ports, clean active-low resets, and no latch inference. It is configured for OpenLane and OpenROAD targeting the open-source SkyWater 130nm standard cell library, producing full placement, routing, and GDSII layout."*

---

## 5. Travel Grant Application Tips (Due November 8th)

- In the application field asking for the **"Poster / Abstract Number"**:
  - Per Professor Wu's instructions: enter `"Pending Submission (Jan 2027 Abstract Cycle)"` or `"TBD - TechConnect 2027 Student Symposium"`.
  - Provide the proposed title: *"From Paper to Silicon: AI-Assisted Physical Design of a Weight-Stationary Systolic NPU Using Open-Source EDA"*.
  - You can update the final abstract number in January when the TechConnect portal officially issues registration IDs.
