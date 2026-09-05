// ============================================================================
// Module: npu_top
// Description: Top-level NPU Accelerator with 4x4 Weight-Stationary Systolic Array
//
// Project: 4x4 Weight-Stationary Systolic Array NPU (ASIC / OpenLane Ready)
// Research: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
// Target: Synthesizable ASIC Standard Cell Libraries (e.g., SkyWater 130nm)
//
// Features:
//   1. Core Parameterized NxN Systolic Array (N=4, INT8 inputs, INT32 psums).
//   2. Stationary Weight Loading Interface:
//      - When weight_en is pulsed for N cycles, columns are loaded sequentially.
//      - After weight_en deasserts, weights remain stationary across inferences.
//   3. Integrated Input Skew Registers:
//      - Accepts parallel matrix rows (A[i, 0..N-1]) and automatically applies
//        the systolic skew delays (0, 1, 2, ... N-1 cycles) before feeding the array.
//   4. Direct Systolic Visibility & Output Deskewing:
//      - raw_psum_out & raw_valid_out: Exposes exact spatial systolic waveforms.
//      - deskewed_out & deskewed_valid: Aligns systolic outputs so full matrix
//        rows appear simultaneously for straightforward host memory writeback.
//   5. Status Flags: busy, done.
//   6. 100% Verilog-2001 Standard Compliant: Flat 1D bitvector interfaces for
//      seamless synthesis with OpenLane, Yosys, OpenROAD, and commercial tools.
// ============================================================================

`timescale 1ns / 1ps

module npu_top #(
    parameter integer N      = 4,   // Matrix dimension (N x N)
    parameter integer DATA_W = 8,   // Activation and weight width (INT8)
    parameter integer ACC_W  = 32   // Partial sum accumulator width (INT32)
) (
    input  wire                             clk,
    input  wire                             rst_n,        // Active-low global asynchronous reset
    input  wire                             clr,          // Synchronous clear for data pipeline (preserves weights)

    // Weight Preload Interface (stationary loading down columns)
    input  wire                             weight_en,
    input  wire signed [N*DATA_W-1:0]       weight_in,

    // Activation Input Interface (parallel row presented per cycle when in_valid is high)
    input  wire                             in_valid,
    input  wire signed [N*DATA_W-1:0]       act_in,

    // Optional Bias / Initial Partial Sum Input (North side, defaults to 0)
    input  wire signed [N*ACC_W-1:0]        bias_in,
    input  wire                             bias_en,

    // Raw Systolic Outputs (directly from bottom of PE array for waveform inspection)
    output wire signed [N*ACC_W-1:0]        raw_psum_out,
    output wire [N-1:0]                     raw_valid_out,

    // Deskewed Matrix Outputs (aligned so entire row C[i, 0..N-1] is valid in the same cycle)
    output wire signed [N*ACC_W-1:0]        deskewed_out,
    output wire                             deskewed_valid,

    // Status Flags
    output wire                             busy,
    output reg                              done
);

    // ========================================================================
    // 1. Input Skewing Pipeline Registers
    // ========================================================================
    // Row r activation must be delayed by r clock cycles before entering PE(r, 0).
    // Column c psum / valid must be delayed by c clock cycles.

    wire signed [N*DATA_W-1:0] act_skewed;
    wire signed [N*ACC_W-1:0]  psum_skewed;
    wire [N-1:0]               valid_skewed;

    // Row 0 connects directly (0 skew delay)
    assign act_skewed[DATA_W-1:0] = act_in[DATA_W-1:0];

    genvar r_idx;
    generate
        for (r_idx = 1; r_idx < N; r_idx = r_idx + 1) begin : gen_act_skew
            reg signed [DATA_W-1:0] stage_reg [0:r_idx-1];
            integer d;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (d = 0; d < r_idx; d = d + 1) begin
                        stage_reg[d] <= {DATA_W{1'b0}};
                    end
                end else if (clr) begin
                    for (d = 0; d < r_idx; d = d + 1) begin
                        stage_reg[d] <= {DATA_W{1'b0}};
                    end
                end else begin
                    stage_reg[0] <= act_in[(r_idx+1)*DATA_W-1 : r_idx*DATA_W];
                    for (d = 1; d < r_idx; d = d + 1) begin
                        stage_reg[d] <= stage_reg[d-1];
                    end
                end
            end

            assign act_skewed[(r_idx+1)*DATA_W-1 : r_idx*DATA_W] = stage_reg[r_idx-1];
        end
    endgenerate

    // Column 0 connects directly
    assign psum_skewed[ACC_W-1:0] = bias_en ? bias_in[ACC_W-1:0] : {ACC_W{1'b0}};
    assign valid_skewed[0]        = in_valid;

    genvar c_idx;
    generate
        for (c_idx = 1; c_idx < N; c_idx = c_idx + 1) begin : gen_col_skew
            reg signed [ACC_W-1:0] psum_stage  [0:c_idx-1];
            reg                    valid_stage [0:c_idx-1];
            integer d;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (d = 0; d < c_idx; d = d + 1) begin
                        psum_stage[d]  <= {ACC_W{1'b0}};
                        valid_stage[d] <= 1'b0;
                    end
                end else if (clr) begin
                    for (d = 0; d < c_idx; d = d + 1) begin
                        psum_stage[d]  <= {ACC_W{1'b0}};
                        valid_stage[d] <= 1'b0;
                    end
                end else begin
                    psum_stage[0]  <= bias_en ? bias_in[(c_idx+1)*ACC_W-1 : c_idx*ACC_W] : {ACC_W{1'b0}};
                    valid_stage[0] <= in_valid;
                    for (d = 1; d < c_idx; d = d + 1) begin
                        psum_stage[d]  <= psum_stage[d-1];
                        valid_stage[d] <= valid_stage[d-1];
                    end
                end
            end

            assign psum_skewed[(c_idx+1)*ACC_W-1 : c_idx*ACC_W] = psum_stage[c_idx-1];
            assign valid_skewed[c_idx]                          = valid_stage[c_idx-1];
        end
    endgenerate

    // ========================================================================
    // 2. Core Systolic Array Instantiation
    // ========================================================================
    wire signed [N*DATA_W-1:0] arr_weight_out;
    wire signed [N*DATA_W-1:0] arr_act_out;

    systolic_array #(
        .N     (N),
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) u_systolic_array (
        .clk       (clk),
        .rst_n     (rst_n),
        .clr       (clr),
        .en        (1'b1),

        .weight_en (weight_en),
        .weight_in (weight_in),
        .weight_out(arr_weight_out),

        .act_in    (act_skewed),
        .act_out   (arr_act_out),

        .psum_in   (psum_skewed),
        .psum_out  (raw_psum_out),

        .valid_in  (valid_skewed),
        .valid_out (raw_valid_out)
    );

    // ========================================================================
    // 3. Output Deskewing Pipeline Registers
    // ========================================================================
    // Column c outputs row i at cycle (T_start + i + c + N).
    // To align all elements of row i to the same cycle, column c must be delayed
    // by (N - 1 - c) clock cycles:
    // Col 0: delay (N - 1) = 3 cycles
    // Col 1: delay (N - 2) = 2 cycles
    // Col 2: delay (N - 3) = 1 cycle
    // Col 3: delay 0 cycles

    genvar o_idx;
    generate
        for (o_idx = 0; o_idx < N; o_idx = o_idx + 1) begin : gen_deskew
            localparam integer DELAY = N - 1 - o_idx;

            if (DELAY == 0) begin : gen_no_delay
                assign deskewed_out[(o_idx+1)*ACC_W-1 : o_idx*ACC_W] = raw_psum_out[(o_idx+1)*ACC_W-1 : o_idx*ACC_W];
            end else begin : gen_delay_pipe
                reg signed [ACC_W-1:0] d_stage [0:DELAY-1];
                integer p;

                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        for (p = 0; p < DELAY; p = p + 1) begin
                            d_stage[p] <= {ACC_W{1'b0}};
                        end
                    end else if (clr) begin
                        for (p = 0; p < DELAY; p = p + 1) begin
                            d_stage[p] <= {ACC_W{1'b0}};
                        end
                    end else begin
                        d_stage[0] <= raw_psum_out[(o_idx+1)*ACC_W-1 : o_idx*ACC_W];
                        for (p = 1; p < DELAY; p = p + 1) begin
                            d_stage[p] <= d_stage[p-1];
                        end
                    end
                end

                assign deskewed_out[(o_idx+1)*ACC_W-1 : o_idx*ACC_W] = d_stage[DELAY-1];
            end
        end
    endgenerate

    // deskewed_valid is column N-1's raw valid out, which has 0 deskew delay
    assign deskewed_valid = raw_valid_out[N-1];

    // ========================================================================
    // 4. Status Flags (busy, done)
    // ========================================================================
    assign busy = in_valid | (|raw_valid_out) | (|valid_skewed) | weight_en;

    // Done pulse: fires on the falling edge of deskewed_valid
    reg deskewed_valid_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            deskewed_valid_d <= 1'b0;
            done             <= 1'b0;
        end else begin
            deskewed_valid_d <= deskewed_valid;
            done             <= (!deskewed_valid && deskewed_valid_d);
        end
    end

endmodule
