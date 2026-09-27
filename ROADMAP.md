# Project Roadmap & Technical Milestones

> **Project**: `sky130-npu-systolic-array` (Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI)  
> **Target Process**: SkyWater 130nm (`sky130_fd_sc_hd`)  
> **Host Architecture**: 32-bit RISC-V SoC (TinyQV / TinyTapeout)  
> **Maintainer**: Dedeepya Nallamothu ([@Dedeepya777](https://github.com/Dedeepya777))  
> **Target Symposium**: TechConnect World Innovation Conference — Student Poster Symposium  

---

## Roadmap Overview

This roadmap defines the engineering milestones to evolve `sky130-edge-npu` from an educational proof-of-concept into a production-grade, open-source AI silicon macro with full software-hardware co-design tooling.

```
[Phase 1: Architecture Scale-Up (16x16)] ───► [Phase 2: Cloud CI Regression]
                       │
                       ▼
[Phase 3: RISC-V C Driver & Tiny MLP Demo] ──► [Phase 4: OpenLane RTL-to-GDSII]
                       │
                       ▼
[Phase 5: PyTorch Weight Compiler] ────────► [Phase 6: TechConnect Poster Signoff]
```

---

## Phase 1: 16×16 Systolic Array Macro Scale-Up (Immediate)
*Target: Match commercial edge NPU tile dimensions (Google Edge TPU scale)*

- [ ] **16×16 Parameterization Validation**:
  - Scale array parameter `N = 16` (256 Processing Elements, 256 INT8 Multipliers, 256 32-bit Accumulators).
  - Verify diagonal skew/deskew buffer depth ($16$ cycles of pipeline stagger).
- [ ] **Throughput & Performance Profiling**:
  - Peak compute at 50 MHz: $256 \times 2 \times 50\,\text{MHz} = \mathbf{25.6\,\text{GOPS}}$.
  - Peak compute at 100 MHz: $\mathbf{51.2\,\text{GOPS}}$.
- [ ] **Physical Area & Gate Count Recalculation**:
  - Update `synth/synth_check.py` for 256 PEs (~120,000 standard cell gates, target die area $\approx 0.65\,\text{mm}^2$).

---

## Phase 2: Automated Continuous Integration (CI)
*Target: Green "Build: Passing" badge on GitHub for every commit & pull request*

- [ ] **GitHub Actions Workflow (`.github/workflows/regression.yml`)**:
  - Set up automated Ubuntu runner with Icarus Verilog (`iverilog`) and `vvp`.
  - Automatically run:
    1. Core algorithmic testbench (`tb/npu_tb.v`).
    2. Direct memory-mapped register bus testbench (`tb/tb_peripheral.v`).
    3. Full-chip SPI harness testbench (`tb/tb_tt_wrapper.v`).
- [ ] **Automated Linting**:
  - Add Verilator linting checks (`verilator --lint-only -Wall`) to enforce clean synthesizable code across all modules.

---

## Phase 3: Hardware-Software Co-Design (C Firmware & Driver)
*Target: Run real neural network layers from the RISC-V CPU*

- [ ] **Bare-Metal C Driver (`drivers/npu.h`, `drivers/npu.c`)**:
  - Implement memory-mapped pointer structures for TinyQV registers (`0x0`–`0xF`).
  - Helper functions:
    ```c
    void npu_reset(void);
    void npu_load_weights(const int8_t weights[4][4]);
    void npu_matmul(const int8_t activations[4][4], int32_t results[4][4]);
    ```
- [ ] **Edge AI Inference Benchmark (`examples/mnist_mlp/`)**:
  - Train a lightweight 2-layer quantized MLP (784 $\to$ 16 $\to$ 10) on MNIST digits in PyTorch.
  - Tile the $16 \times 16$ dense layer onto the NPU and print digit predictions over UART.

---

## Phase 4: Full Silicon Physical Design (RTL-to-GDSII via OpenLane)
*Target: Final foundry layout mask (.gds) and 3D chip renderings*

- [ ] **Floorplanning & Pin Placement**:
  - Configure die dimensions and pin perimeter spacing in `openlane/config.json`.
- [ ] **Placement & Clock Tree Synthesis (CTS)**:
  - Achieve balanced clock distribution across all 16 (or 256) PEs with $< 150\,\text{ps}$ clock skew.
- [ ] **Global & Detailed Routing**:
  - Route across SkyWater 130nm metal layers (`met1` through `met4`).
- [ ] **Physical Verification Signoff**:
  - Zero DRC (Design Rule Check) violations.
  - Zero LVS (Layout Versus Schematic) mismatches.
- [ ] **Visual Assets for Presentation**:
  - High-resolution KLayout renders showing standard cell density, power distribution network (PDN), and metal routing for the TechConnect poster.

---

## Phase 5: Python Machine Learning Toolchain
*Target: Bridge PyTorch directly to custom silicon*

- [ ] **Lightweight Model Compiler (`tools/npu_compiler.py`)**:
  - Extract weight matrices from `torch.nn.Linear` or `torch.nn.Conv2d`.
  - Perform symmetric post-training INT8 quantization:
    $$W_{\text{int8}} = \text{clamp}\left(\text{round}\left(\frac{W}{\text{scale}}\right), -128, 127\right)$$
  - Export weights and test inputs as Verilog memory initialization files (`.mem` / `.hex`).

---

## Phase 6: TechConnect Poster & Publication Signoff
*Target: Final delivery for the TechConnect Student Poster Symposium*

- [ ] **Poster Layout (48" × 36" Standard)**:
  - **Column 1**: The Edge AI Memory Wall (GPU SIMT overhead vs. NPU spatial dataflow).
  - **Column 2**: Weight-Stationary Systolic Array Architecture & Timing Waveforms.
  - **Column 3**: SkyWater 130nm Silicon Profile & TinyQV RISC-V Integration.
  - **Column 4**: Empirical Efficiency Benchmarks (GOPS/Watt curve) & Open-Source Flow Conclusion.
- [ ] **Oral Presentation Pitch (3-Minute Elevator Rehearsal)**:
  - Concise presentation script addressing conference reviewers, faculty, and industry judges.
