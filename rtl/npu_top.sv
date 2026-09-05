// ============================================================================
// Module: npu_top
// Description: Top-level NPU Accelerator with 4x4 Weight-Stationary Systolic Array
//
// Project: 4x4 Weight-Stationary Systolic Array NPU
// Paper: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
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
//      - raw_psum_out [N-1:0] & raw_valid_out [N-1:0]: Exposes exact spatial systolic waveforms.
//      - deskewed_out [N-1:0] & deskewed_valid: Aligns systolic outputs so full matrix
//        rows appear simultaneously for straightforward host memory writeback.
//   5. Status Flags: busy, done.
// ============================================================================

`timescale 1ns / 1ps

module npu_top #(
    parameter int N      = 4,   // Matrix dimension (N x N)
    parameter int DATA_W = 8,   // Activation and weight width (INT8)
    parameter int ACC_W  = 32   // Partial sum accumulator width (INT32)
) (
    input  logic                                  clk,
    input  logic                                  rst_n,        // Active-low global asynchronous reset
    input  logic                                  clr,          // Synchronous clear for data pipeline (preserves weights)

    // Weight Preload Interface (stationary loading down columns)
    input  logic                                  weight_en,
    input  logic signed [N-1:0][DATA_W-1:0]       weight_in,

    // Activation Input Interface (parallel row presented per cycle when in_valid is high)
    input  logic                                  in_valid,
    input  logic signed [N-1:0][DATA_W-1:0]       act_in,

    // Optional Bias / Initial Partial Sum Input (North side, defaults to 0)
    input  logic signed [N-1:0][ACC_W-1:0]        bias_in,
    input  logic                                  bias_en,

    // Raw Systolic Outputs (directly from bottom of PE array for waveform inspection)
    output logic signed [N-1:0][ACC_W-1:0]        raw_psum_out,
    output logic [N-1:0]                          raw_valid_out,

    // Deskewed Matrix Outputs (aligned so entire row C[i, 0..N-1] is valid in the same cycle)
    output logic signed [N-1:0][ACC_W-1:0]        deskewed_out,
    output logic                                  deskewed_valid,

    // Status Flags
    output logic                                  busy,
    output logic                                  done
);

    // ========================================================================
    // 1. Input Skewing Pipeline Registers
    // ========================================================================
    // Row r activation must be delayed by r clock cycles before entering PE(r, 0).
    // Column c psum / valid must be delayed by c clock cycles.

    logic signed [N-1:0][DATA_W-1:0] act_skewed;
    logic signed [N-1:0][ACC_W-1:0]  psum_skewed;
    logic [N-1:0]                    valid_skewed;

    // Row 0 connects directly (0 skew delay)
    assign act_skewed[0] = act_in[0];

    genvar r_idx;
    generate
        for (r_idx = 1; r_idx < N; r_idx++) begin : gen_act_skew
            logic signed [r_idx-1:0][DATA_W-1:0] stage_reg;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int d = 0; d < r_idx; d++) begin
                        stage_reg[d] <= '0;
                    end
                end else if (clr) begin
                    for (int d = 0; d < r_idx; d++) begin
                        stage_reg[d] <= '0;
                    end
                end else begin
                    stage_reg[0] <= act_in[r_idx];
                    for (int d = 1; d < r_idx; d++) begin
                        stage_reg[d] <= stage_reg[d-1];
                    end
                end
            end

            assign act_skewed[r_idx] = stage_reg[r_idx-1];
        end
    endgenerate

    // Column 0 connects directly
    assign psum_skewed[0]  = bias_en ? bias_in[0] : '0;
    assign valid_skewed[0] = in_valid;

    genvar c_idx;
    generate
        for (c_idx = 1; c_idx < N; c_idx++) begin : gen_col_skew
            logic signed [c_idx-1:0][ACC_W-1:0] psum_stage;
            logic [c_idx-1:0]                   valid_stage;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int d = 0; d < c_idx; d++) begin
                        psum_stage[d]  <= '0;
                        valid_stage[d] <= 1'b0;
                    end
                end else if (clr) begin
                    for (int d = 0; d < c_idx; d++) begin
                        psum_stage[d]  <= '0;
                        valid_stage[d] <= 1'b0;
                    end
                end else begin
                    psum_stage[0]  <= bias_en ? bias_in[c_idx] : '0;
                    valid_stage[0] <= in_valid;
                    for (int d = 1; d < c_idx; d++) begin
                        psum_stage[d]  <= psum_stage[d-1];
                        valid_stage[d] <= valid_stage[d-1];
                    end
                end
            end

            assign psum_skewed[c_idx]  = psum_stage[c_idx-1];
            assign valid_skewed[c_idx] = valid_stage[c_idx-1];
        end
    endgenerate

    // ========================================================================
    // 2. Core Systolic Array Instantiation
    // ========================================================================
    logic signed [N-1:0][DATA_W-1:0] arr_weight_out;
    logic signed [N-1:0][DATA_W-1:0] arr_act_out;

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
        for (o_idx = 0; o_idx < N; o_idx++) begin : gen_deskew
            localparam int DELAY = N - 1 - o_idx;

            if (DELAY == 0) begin : gen_no_delay
                assign deskewed_out[o_idx] = raw_psum_out[o_idx];
            end else begin : gen_delay_pipe
                logic signed [DELAY-1:0][ACC_W-1:0] d_stage;

                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        for (int p = 0; p < DELAY; p++) begin
                            d_stage[p] <= '0;
                        end
                    end else if (clr) begin
                        for (int p = 0; p < DELAY; p++) begin
                            d_stage[p] <= '0;
                        end
                    end else begin
                        d_stage[0] <= raw_psum_out[o_idx];
                        for (int p = 1; p < DELAY; p++) begin
                            d_stage[p] <= d_stage[p-1];
                        end
                    end
                end

                assign deskewed_out[o_idx] = d_stage[DELAY-1];
            end
        end
    endgenerate

    // deskewed_valid is column N-1's raw valid out, which has 0 deskew delay
    assign deskewed_valid = raw_valid_out[N-1];

    // ========================================================================
    // 4. Status Flags (busy, done)
    // ========================================================================
    assign busy = in_valid | (|raw_valid_out) | (|valid_skewed) | weight_en;

    // Done pulse: fires when the last deskewed row finishes
    logic deskewed_valid_d;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            deskewed_valid_d <= 1'b0;
            done             <= 1'b0;
        end else begin
            deskewed_valid_d <= deskewed_valid;
            // Pulse done on the falling edge of deskewed_valid
            done <= (!deskewed_valid && deskewed_valid_d);
        end
    end

endmodule
