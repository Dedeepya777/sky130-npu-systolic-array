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
// ============================================================================
// Module: processing_element
// Description: Processing Element (PE) for Weight-Stationary Systolic Array
//
// Project: 4x4 Weight-Stationary Systolic Array NPU (ASIC / OpenLane Ready)
// Research: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
// Target: Synthesizable ASIC Standard Cell Libraries (e.g., SkyWater 130nm)
//
// Features:
//   1. Stationary Weight Register: Loaded when weight_en=1; held stationary across
//      arbitrary computation cycles when weight_en=0.
//   2. Weight Daisy-Chaining: weight_out connects to South PE's weight_in
//      enabling systolic column-shift preload in N cycles.
//   3. Horizontal Activation Propagation: act_in latched into act_reg and forwarded
//      to act_out (West -> East).
//   4. Vertical Partial-Sum Propagation: MAC computes (psum_in + act_in * weight_reg),
//      latched into psum_reg and forwarded to psum_out (North -> South).
//   5. Pipeline Clear (clr): Clears act_reg, psum_reg, and valid_reg without disturbing
//      the stationary weight register.
//   6. Reset (rst_n): Active-low asynchronous reset clearing all registers.
// ============================================================================

`timescale 1ns / 1ps

module processing_element #(
    parameter integer DATA_W = 8,   // Activation and weight width
    parameter integer ACC_W  = 32   // Partial sum accumulator width
) (
    input  wire                     clk,
    input  wire                     rst_n,        // Active-low global asynchronous reset
    input  wire                     clr,          // Synchronous clear for data registers (preserves weights)
    input  wire                     en,           // PE pipeline enable

    // Weight programming interface
    input  wire                     weight_en,    // Weight write/shift enable
    input  wire signed [DATA_W-1:0] weight_in,    // Weight input (from North PE or external top)
    output wire signed [DATA_W-1:0] weight_out,   // Weight output (to South PE)

    // Systolic dataflow interfaces
    input  wire signed [DATA_W-1:0] act_in,       // Activation input (from West)
    output wire signed [DATA_W-1:0] act_out,      // Activation output (to East)

    input  wire signed [ACC_W-1:0]  psum_in,      // Partial sum input (from North)
    output wire signed [ACC_W-1:0]  psum_out,     // Partial sum output (to South)

    // Control / valid token propagation
    input  wire                     valid_in,     // Valid token input (from North)
    output wire                     valid_out     // Valid token output (to South)
);

    // ------------------------------------------------------------------------
    // Internal Registers
    // ------------------------------------------------------------------------
    reg signed [DATA_W-1:0] weight_reg;
    reg signed [DATA_W-1:0] act_reg;
    reg signed [ACC_W-1:0]  psum_reg;
    reg                     valid_reg;

    // ------------------------------------------------------------------------
    // MAC Unit Instance
    // ------------------------------------------------------------------------
    wire signed [ACC_W-1:0] mac_psum_out;

    mac #(
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) u_mac (
        .act_in   (act_in),
        .weight_in(weight_reg),
        .psum_in  (psum_in),
        .psum_out (mac_psum_out)
    );

    // ------------------------------------------------------------------------
    // Sequential Logic: Weight Register (Stationary Storage)
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_reg <= {DATA_W{1'b0}};
        end else if (weight_en) begin
            weight_reg <= weight_in;
        end
        // When weight_en == 0, weight_reg holds stationary value indefinitely
    end

    // Forward weight for column-shift daisy-chaining during weight loading
    assign weight_out = weight_reg;

    // ------------------------------------------------------------------------
    // Sequential Logic: Systolic Pipeline Registers (Activation, Psum, Valid)
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            act_reg   <= {DATA_W{1'b0}};
            psum_reg  <= {ACC_W{1'b0}};
            valid_reg <= 1'b0;
        end else if (clr) begin
            // Synchronously clear data pipeline without disturbing stationary weights
            act_reg   <= {DATA_W{1'b0}};
            psum_reg  <= {ACC_W{1'b0}};
            valid_reg <= 1'b0;
        end else if (en) begin
            act_reg   <= act_in;
            psum_reg  <= mac_psum_out;
            valid_reg <= valid_in;
        end
    end

    // Drive outputs from registered pipeline stages
    assign act_out   = act_reg;
    assign psum_out  = psum_reg;
    assign valid_out = valid_reg;

endmodule
// ============================================================================
// Module: systolic_array
// Description: Parameterized 2D Weight-Stationary Systolic Array (N x N)
//
// Project: 4x4 Weight-Stationary Systolic Array NPU (ASIC / OpenLane Ready)
// Research: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
// Target: Synthesizable ASIC Standard Cell Libraries (e.g., SkyWater 130nm)
//
// Interconnect Topology:
//   - Instantiates N x N Processing Elements (PEs).
//   - Stationary Weights: Preloaded vertically via column daisy-chains.
//   - Activations: Streamed West -> East across rows.
//     Row r input connects to PE(r, 0).
//     PE(r, c) act_out connects to PE(r, c+1) act_in.
//   - Partial Sums: Streamed North -> South down columns.
//     Column c input connects to PE(0, c).
//     PE(r, c) psum_out connects to PE(r+1, c) psum_in.
//     Final results emerge from PE(N-1, c) at the bottom.
//   - Valid Tokens: Propagate synchronously with partial sums down columns.
//   - Flat 1D Bitvector Ports: Guarantees 100% compatibility with Yosys / OpenLane.
// ============================================================================

`timescale 1ns / 1ps

module systolic_array #(
    parameter integer N      = 4,   // Array dimension (N x N)
    parameter integer DATA_W = 8,   // Activation & weight bitwidth
    parameter integer ACC_W  = 32   // Partial sum bitwidth
) (
    input  wire                             clk,
    input  wire                             rst_n,
    input  wire                             clr,
    input  wire                             en,

    // Weight loading interface (top inputs, bottom outputs)
    input  wire                             weight_en,
    input  wire signed [N*DATA_W-1:0]       weight_in,
    output wire signed [N*DATA_W-1:0]       weight_out,

    // Activation interface (west inputs, east outputs)
    input  wire signed [N*DATA_W-1:0]       act_in,
    output wire signed [N*DATA_W-1:0]       act_out,

    // Partial sum interface (north inputs, south outputs)
    input  wire signed [N*ACC_W-1:0]        psum_in,
    output wire signed [N*ACC_W-1:0]        psum_out,

    // Valid token bit-vectors (north inputs, south outputs)
    input  wire [N-1:0]                      valid_in,
    output wire [N-1:0]                      valid_out
);

    // ------------------------------------------------------------------------
    // Internal Wiring Grids
    // ------------------------------------------------------------------------
    // Horizontal activations: [row][col], dimension [N][N+1]
    wire signed [DATA_W-1:0] act_wire   [0:N-1][0:N];

    // Vertical partial sums: [row][col], dimension [N+1][N]
    wire signed [ACC_W-1:0]  psum_wire  [0:N][0:N-1];

    // Vertical weight shift chain: [row][col], dimension [N+1][N]
    wire signed [DATA_W-1:0] weight_wire[0:N][0:N-1];

    // Vertical valid tokens: [row][col], dimension [N+1][N]
    wire                     valid_wire [0:N][0:N-1];

    // ------------------------------------------------------------------------
    // Boundary Hookups (Packing and Unpacking 1D Flat Ports)
    // ------------------------------------------------------------------------
    genvar b;
    generate
        for (b = 0; b < N; b = b + 1) begin : gen_boundaries
            // West inputs & East outputs (Activations)
            assign act_wire[b][0] = act_in[(b+1)*DATA_W-1 : b*DATA_W];
            assign act_out[(b+1)*DATA_W-1 : b*DATA_W] = act_wire[b][N];

            // North inputs & South outputs (Partial Sums)
            assign psum_wire[0][b] = psum_in[(b+1)*ACC_W-1 : b*ACC_W];
            assign psum_out[(b+1)*ACC_W-1 : b*ACC_W] = psum_wire[N][b];

            // North inputs & South outputs (Weights)
            assign weight_wire[0][b] = weight_in[(b+1)*DATA_W-1 : b*DATA_W];
            assign weight_out[(b+1)*DATA_W-1 : b*DATA_W] = weight_wire[N][b];

            // North inputs & South outputs (Valid Tokens)
            assign valid_wire[0][b] = valid_in[b];
            assign valid_out[b] = valid_wire[N][b];
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 2D Processing Element Grid Instantiation
    // ------------------------------------------------------------------------
    genvar r, c;
    generate
        for (r = 0; r < N; r = r + 1) begin : gen_row
            for (c = 0; c < N; c = c + 1) begin : gen_col
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
