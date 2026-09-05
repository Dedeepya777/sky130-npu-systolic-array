// ============================================================================
// Module: systolic_array
// Description: Parameterized 2D Weight-Stationary Systolic Array (N x N)
//
// Project: 4x4 Weight-Stationary Systolic Array NPU
// Paper: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
//
// Interconnect Topology:
//   - Instantiates N x N Processing Elements (PEs).
//   - Stationary Weights: Preloaded vertically via column daisy-chains.
//   - Activations: Streamed from West to East across rows.
//     Row r input connects to PE(r, 0).
//     PE(r, c) act_out connects to PE(r, c+1) act_in.
//   - Partial Sums: Streamed from North to South down columns.
//     Column c input connects to PE(0, c).
//     PE(r, c) psum_out connects to PE(r+1, c) psum_in.
//     Final results emerge from PE(N-1, c) at the bottom.
//   - Valid Tokens: Propagate synchronously with partial sums down columns.
// ============================================================================

`timescale 1ns / 1ps

module systolic_array #(
    parameter int N      = 4,   // Array dimension (N x N)
    parameter int DATA_W = 8,   // Activation & weight bitwidth
    parameter int ACC_W  = 32   // Partial sum bitwidth
) (
    input  logic                                  clk,
    input  logic                                  rst_n,
    input  logic                                  clr,
    input  logic                                  en,

    // Weight loading interface (top inputs, bottom outputs)
    input  logic                                  weight_en,
    input  logic signed [N-1:0][DATA_W-1:0]       weight_in,
    output logic signed [N-1:0][DATA_W-1:0]       weight_out,

    // Activation interface (west inputs, east outputs)
    input  logic signed [N-1:0][DATA_W-1:0]       act_in,
    output logic signed [N-1:0][DATA_W-1:0]       act_out,

    // Partial sum interface (north inputs, south outputs)
    input  logic signed [N-1:0][ACC_W-1:0]        psum_in,
    output logic signed [N-1:0][ACC_W-1:0]        psum_out,

    // Valid token bit-vectors (north inputs, south outputs)
    input  logic [N-1:0]                          valid_in,
    output logic [N-1:0]                          valid_out
);

    // ------------------------------------------------------------------------
    // Internal Wiring Grids
    // ------------------------------------------------------------------------
    // Horizontal activations: [row][col], dimension [N][N+1]
    wire signed [DATA_W-1:0] act_wire   [N][N+1];

    // Vertical partial sums: [row][col], dimension [N+1][N]
    wire signed [ACC_W-1:0]  psum_wire  [N+1][N];

    // Vertical weight shift chain: [row][col], dimension [N+1][N]
    wire signed [DATA_W-1:0] weight_wire[N+1][N];

    // Vertical valid tokens: [row][col], dimension [N+1][N]
    wire                     valid_wire [N+1][N];

    // ------------------------------------------------------------------------
    // Boundary Hookups
    // ------------------------------------------------------------------------
    genvar b;
    generate
        for (b = 0; b < N; b++) begin : gen_boundaries
            // West inputs & East outputs (Activations)
            assign act_wire[b][0]    = act_in[b];
            assign act_out[b]        = act_wire[b][N];

            // North inputs & South outputs (Partial Sums)
            assign psum_wire[0][b]   = psum_in[b];
            assign psum_out[b]       = psum_wire[N][b];

            // North inputs & South outputs (Weights)
            assign weight_wire[0][b] = weight_in[b];
            assign weight_out[b]     = weight_wire[N][b];

            // North inputs & South outputs (Valid Tokens)
            assign valid_wire[0][b]  = valid_in[b];
            assign valid_out[b]      = valid_wire[N][b];
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 2D Processing Element Grid Instantiation
    // ------------------------------------------------------------------------
    genvar r, c;
    generate
        for (r = 0; r < N; r++) begin : gen_row
            for (c = 0; c < N; c++) begin : gen_col
                processing_element #(
                    .DATA_W(DATA_W),
                    .ACC_W (ACC_W)
                ) u_pe (
                    .clk       (clk),
                    .rst_n     (rst_n),
                    .clr       (clr),
                    .en        (en),

                    .weight_en (weight_en),
                    .weight_in (weight_wire[r][c]),
                    .weight_out(weight_wire[r+1][c]),

                    .act_in    (act_wire[r][c]),
                    .act_out   (act_wire[r][c+1]),

                    .psum_in   (psum_wire[r][c]),
                    .psum_out  (psum_wire[r+1][c]),

                    .valid_in  (valid_wire[r][c]),
                    .valid_out (valid_wire[r+1][c])
                );
            end
        end
    endgenerate

endmodule
