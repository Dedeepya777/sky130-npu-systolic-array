# SPDX-FileCopyrightText: © 2025 Tiny Tapeout & COS231 Architecture Team
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
import numpy as np

from tqv import TinyQV

PERIPHERAL_NUM = 16

@cocotb.test()
async def test_systolic_npu(dut):
    """
    End-to-End Verification of the 4x4 Weight-Stationary Systolic Array NPU
    Interfacing through TinyQV Memory-Mapped Peripheral Registers.
    """
    dut._log.info("============================================================")
    dut._log.info("  Starting TinyQV 4x4 Systolic Array NPU Verification Suite")
    dut._log.info("============================================================")

    # Set clock to 100 ns (10 MHz)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)

    # 1. Reset
    await tqv.reset()
    dut._log.info("TinyQV SoC & NPU Peripheral successfully reset.")

    # 2. Check initial CSR
    csr = await tqv.read_reg(0)
    dut._log.info(f"Initial CSR (reg 0x0) = 0x{csr:02X}")

    # ------------------------------------------------------------------------
    # Test Data: 4x4 Matrices
    # Weight Matrix B (Stationary)
    # Activation Matrix A (Streamed)
    # ------------------------------------------------------------------------
    B = np.array([
        [ 2, -1,  3,  0],
        [ 1,  4, -2,  1],
        [-3,  2,  1,  2],
        [ 0,  1, -1,  3]
    ], dtype=np.int8)

    A = np.array([
        [ 3,  1,  2,  0],
        [ 1, -2,  0,  4],
        [ 2,  3, -1,  1],
        [ 0,  1,  4, -2]
    ], dtype=np.int8)

    # Golden Matrix Multiplication C = A x B (INT32)
    C_golden = np.matmul(A.astype(np.int32), B.astype(np.int32))
    dut._log.info(f"\nExpected Matrix C_golden (A x B):\n{C_golden}")

    # ------------------------------------------------------------------------
    # Step 3: Preload Stationary Weights
    # Load rows in order: Row 3 -> Row 2 -> Row 1 -> Row 0 (shifting downward)
    # ------------------------------------------------------------------------
    dut._log.info("\n[1/3] Preloading 4x4 stationary weights into PE array...")
    for r in [3, 2, 1, 0]:
        for c in range(4):
            val = int(B[r, c]) & 0xFF
            await tqv.write_reg(0x8 + c, val)
        # Strobe weight_load_pulse (CSR bit 2 = 0x04)
        await tqv.write_reg(0x0, 0x04)

    dut._log.info("Weights loaded into all 16 PEs successfully.")

    # ------------------------------------------------------------------------
    # Step 4: Stream Activation Rows
    # Feed Row 0, 1, 2, 3, followed by zero-flushes
    # ------------------------------------------------------------------------
    dut._log.info("\n[2/3] Streaming 4x4 activation rows into systolic pipeline...")
    for r in range(4):
        for c in range(4):
            val = int(A[r, c]) & 0xFF
            await tqv.write_reg(0x4 + c, val)
        # Pulse step/feed (CSR bit 0 = 0x01)
        await tqv.write_reg(0x0, 0x01)

    # Flush remaining systolic cycles with zero activations
    for c in range(4):
        await tqv.write_reg(0x4 + c, 0x00)
    for flush in range(8):
        await tqv.write_reg(0x0, 0x01)

    # ------------------------------------------------------------------------
    # Step 5: Read and Verify Result Matrix
    # ------------------------------------------------------------------------
    dut._log.info("\n[3/3] Reading back 4x4 accumulated result matrix...")
    C_actual = np.zeros((4, 4), dtype=np.int32)
    mismatches = 0

    for r in range(4):
        # Set target row
        await tqv.write_reg(0x3, r)
        for c in range(4):
            # Set target column
            await tqv.write_reg(0x1, c)

            # Read 4 bytes of 32-bit accumulator: LSB at 0xC, MSB at 0xF
            b0 = await tqv.read_reg(0xC)
            b1 = await tqv.read_reg(0xD)
            b2 = await tqv.read_reg(0xE)
            b3 = await tqv.read_reg(0xF)

            # Reconstruct signed 32-bit integer
            raw_32 = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
            if raw_32 & 0x80000000:
                val = raw_32 - (1 << 32)
            else:
                val = raw_32

            C_actual[r, c] = val
            expected = int(C_golden[r, c])
            if val != expected:
                dut._log.error(f"MISMATCH at C[{r},{c}]: Actual={val}, Expected={expected}")
                mismatches += 1
            else:
                dut._log.info(f"MATCH: C[{r},{c}] = {val}")

    dut._log.info(f"\nActual Result Matrix from NPU:\n{C_actual}")
    dut._log.info("============================================================")
    if mismatches == 0:
        dut._log.info("  >>> SUCCESS: ALL 16 MATRIX ELEMENTS MATCH GOLDEN MODEL! <<<")
    else:
        dut._log.error(f"  >>> FAILED: {mismatches} MISMATCHES DETECTED! <<<")
    dut._log.info("============================================================")

    assert mismatches == 0, f"{mismatches} matrix element mismatches detected!"
