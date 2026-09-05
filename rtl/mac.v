// ============================================================================
// Module: mac
// Description: Signed Multiply-Accumulate (MAC) Unit
//
// Project: 4x4 Weight-Stationary Systolic Array NPU (ASIC / OpenLane Ready)
// Research: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
// Target: Synthesizable ASIC Standard Cell Libraries (e.g., SkyWater 130nm)
//
// Operation:
//   psum_out = psum_in + (act_in * weight_in)
//
// Signed Arithmetic:
//   Both activation and weight are signed 2's complement integers (default INT8).
//   The product is 16-bit signed, sign-extended to 32 bits, and accumulated with psum_in.
// ============================================================================

`timescale 1ns / 1ps

module mac #(
    parameter integer DATA_W = 8,   // Activation and weight bitwidth (INT8)
    parameter integer ACC_W  = 32   // Partial sum accumulator bitwidth (INT32)
) (
    input  wire signed [DATA_W-1:0] act_in,
    input  wire signed [DATA_W-1:0] weight_in,
    input  wire signed [ACC_W-1:0]  psum_in,
    output wire signed [ACC_W-1:0]  psum_out
);

    // 1. Signed multiplication: DATA_W x DATA_W -> (2 * DATA_W) bits
    wire signed [2*DATA_W-1:0] mult_product;
    assign mult_product = act_in * weight_in;

    // 2. Sign extension to accumulator width (ACC_W)
    wire signed [ACC_W-1:0] mult_extended;
    assign mult_extended = {{(ACC_W - 2*DATA_W){mult_product[2*DATA_W-1]}}, mult_product};

    // 3. Signed accumulation with incoming partial sum
    assign psum_out = psum_in + mult_extended;

endmodule
