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
