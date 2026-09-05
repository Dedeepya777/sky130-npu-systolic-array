// ============================================================================
// Module: mac
// Description: Signed Multiply-Accumulate (MAC) Unit
//
// Project: 4x4 Weight-Stationary Systolic Array NPU
// Paper: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
//
// Operation:
//   psum_out = psum_in + (act_in * weight_in)
//
// Both activation and weight are signed 2's complement integers (default INT8).
// The partial sum is a wide signed 2's complement integer (default INT32)
// to prevent overflow across repeated accumulations.
// ============================================================================

`timescale 1ns / 1ps

module mac #(
    parameter int DATA_W = 8,   // Activation and weight bitwidth (INT8)
    parameter int ACC_W  = 32   // Partial sum accumulator bitwidth (INT32)
) (
    input  logic signed [DATA_W-1:0] act_in,
    input  logic signed [DATA_W-1:0] weight_in,
    input  logic signed [ACC_W-1:0]  psum_in,
    output logic signed [ACC_W-1:0]  psum_out
);

    // 1. Signed multiplication: DATA_W x DATA_W -> (2 * DATA_W) bits
    // For INT8 x INT8: range is [-128 * 127 = -16256] to [-128 * -128 = +16384]
    // which fits completely in signed 16 bits.
    wire signed [2*DATA_W-1:0] mult_product;
    assign mult_product = act_in * weight_in;

    // 2. Sign extension to accumulator width (ACC_W)
    wire signed [ACC_W-1:0] mult_extended;
    assign mult_extended = {{(ACC_W - 2*DATA_W){mult_product[2*DATA_W-1]}}, mult_product};

    // 3. Signed accumulation with incoming partial sum
    assign psum_out = psum_in + mult_extended;

endmodule
