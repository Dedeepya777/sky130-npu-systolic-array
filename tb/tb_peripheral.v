// ============================================================================
// Testbench: tb_peripheral
// Description: Standalone Verilog Verification for TinyQV Systolic NPU Peripheral
//
// Project: 4x4 Weight-Stationary Systolic Array NPU
// Research: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
//
// Exercises the 16-register TinyQV memory map directly via bus write/read tasks:
//   1. Applies power-on reset.
//   2. Preloads 4x4 stationary weight matrix down columns.
//   3. Streams 4x4 activation rows with pipeline flush cycles.
//   4. Reads back the entire 4x4 32-bit accumulated result matrix.
//   5. Compares against independent golden matrix multiplication model.
//   6. Formatted ASCII matrix display & PASS/FAIL assertion.
// ============================================================================

`timescale 1ns / 1ps

module tb_peripheral;

    // ------------------------------------------------------------------------
    // Clock & Reset Signals
    // ------------------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg  [7:0] ui_in;
    wire [7:0] uo_out;

    reg  [3:0] address;
    reg        data_write;
    reg  [7:0] data_in;
    wire [7:0] data_out;

    // ------------------------------------------------------------------------
    // DUT Instantiation
    // ------------------------------------------------------------------------
    tqvp_npu_systolic dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .ui_in      (ui_in),
        .uo_out     (uo_out),
        .address    (address),
        .data_write (data_write),
        .data_in    (data_in),
        .data_out   (data_out)
    );

    // ------------------------------------------------------------------------
    // 100 MHz Clock Generation (10ns period)
    // ------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // Bus Access Tasks (Simulating TinyQV CPU Load/Store Byte Operations)
    // ------------------------------------------------------------------------
    task write_reg(input [3:0] addr, input [7:0] val);
    begin
        @(posedge clk);
        address    <= addr;
        data_write <= 1'b1;
        data_in    <= val;
        @(posedge clk);
        data_write <= 1'b0;
        data_in    <= 8'h00;
    end
    endtask

    task read_reg(input [3:0] addr, output [7:0] val);
    begin
        @(posedge clk);
        address    <= addr;
        data_write <= 1'b0;
        #1; // Sample after combinational mux settles
        val = data_out;
        @(posedge clk);
    end
    endtask

    // ------------------------------------------------------------------------
    // Test Matrices
    // ------------------------------------------------------------------------
    reg signed [7:0]  matrix_A [0:3][0:3];
    reg signed [7:0]  matrix_B [0:3][0:3];
    reg signed [31:0] matrix_C_golden [0:3][0:3];
    reg signed [31:0] matrix_C_actual [0:3][0:3];

    integer r, c, k;
    integer errors;
    reg [7:0] b0, b1, b2, b3;
    reg [7:0] status;

    // ------------------------------------------------------------------------
    // Main Verification Procedure
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_peripheral.vcd");
        $dumpvars(0, tb_peripheral);

        $display("\n================================================================");
        $display("  TinyQV RISC-V Peripheral Test: 4x4 Systolic Array NPU");
        $display("  COS231 Research: NPUs vs GPUs in On-Device AI");
        $display("================================================================\n");

        errors = 0;
        address = 4'h0;
        data_write = 1'b0;
        data_in = 8'h00;
        ui_in = 8'h00;
        rst_n = 1'b0;

        // Reset sequence
        #25;
        rst_n = 1'b1;
        #20;
        $display("[TB] System reset released. Initializing test matrices...");

        // Define Matrix B (Stationary Weights):
        //   [  2, -1,  3,  0 ]
        //   [  1,  4, -2,  1 ]
        //   [ -3,  2,  1,  2 ]
        //   [  0,  1, -1,  3 ]
        matrix_B[0][0] =  8'sd2;  matrix_B[0][1] = -8'sd1;  matrix_B[0][2] =  8'sd3;  matrix_B[0][3] =  8'sd0;
        matrix_B[1][0] =  8'sd1;  matrix_B[1][1] =  8'sd4;  matrix_B[1][2] = -8'sd2;  matrix_B[1][3] =  8'sd1;
        matrix_B[2][0] = -8'sd3;  matrix_B[2][1] =  8'sd2;  matrix_B[2][2] =  8'sd1;  matrix_B[2][3] =  8'sd2;
        matrix_B[3][0] =  8'sd0;  matrix_B[3][1] =  8'sd1;  matrix_B[3][2] = -8'sd1;  matrix_B[3][3] =  8'sd3;

        // Define Matrix A (Streamed Activations):
        //   [  3,  1,  2,  0 ]
        //   [  1, -2,  0,  4 ]
        //   [  2,  3, -1,  1 ]
        //   [  0,  1,  4, -2 ]
        matrix_A[0][0] =  8'sd3;  matrix_A[0][1] =  8'sd1;  matrix_A[0][2] =  8'sd2;  matrix_A[0][3] =  8'sd0;
        matrix_A[1][0] =  8'sd1;  matrix_A[1][1] = -8'sd2;  matrix_A[1][2] =  8'sd0;  matrix_A[1][3] =  8'sd4;
        matrix_A[2][0] =  8'sd2;  matrix_A[2][1] =  8'sd3;  matrix_A[2][2] = -8'sd1;  matrix_A[2][3] =  8'sd1;
        matrix_A[3][0] =  8'sd0;  matrix_A[3][1] =  8'sd1;  matrix_A[3][2] =  8'sd4;  matrix_A[3][3] = -8'sd2;

        // Compute Golden Model Reference: C_golden = A x B
        for (r = 0; r < 4; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
                matrix_C_golden[r][c] = 0;
                for (k = 0; k < 4; k = k + 1) begin
                    matrix_C_golden[r][c] = matrix_C_golden[r][c] + (matrix_A[r][k] * matrix_B[k][c]);
                end
            end
        end

        // Display Inputs
        $display("\nMatrix A (Streamed Activations 4x4 INT8):");
        for (r = 0; r < 4; r = r + 1)
            $display("  [%4d %4d %4d %4d ]", matrix_A[r][0], matrix_A[r][1], matrix_A[r][2], matrix_A[r][3]);

        $display("\nMatrix B (Stationary Weights 4x4 INT8):");
        for (r = 0; r < 4; r = r + 1)
            $display("  [%4d %4d %4d %4d ]", matrix_B[r][0], matrix_B[r][1], matrix_B[r][2], matrix_B[r][3]);

        $display("\nGolden Reference Matrix C_golden = A x B (INT32):");
        for (r = 0; r < 4; r = r + 1)
            $display("  [%6d %6d %6d %6d ]", matrix_C_golden[r][0], matrix_C_golden[r][1], matrix_C_golden[r][2], matrix_C_golden[r][3]);

        // --------------------------------------------------------------------
        // Step 1: Preload Stationary Weights into Systolic Array
        // Loading rows in reverse (Row 3 -> Row 2 -> Row 1 -> Row 0)
        // --------------------------------------------------------------------
        $display("\n[TB] Preloading stationary weights into registers 0x8..0xB...");
        for (r = 3; r >= 0; r = r - 1) begin
            write_reg(4'h8, matrix_B[r][0]);
            write_reg(4'h9, matrix_B[r][1]);
            write_reg(4'hA, matrix_B[r][2]);
            write_reg(4'hB, matrix_B[r][3]);
            // Strobe weight_load_pulse (CSR bit 2)
            write_reg(4'h0, 8'h04);
        end
        $display("[TB] Weights successfully loaded into all 16 Processing Elements.");

        // --------------------------------------------------------------------
        // Step 2: Stream Activation Rows into NPU Pipeline
        // --------------------------------------------------------------------
        $display("\n[TB] Streaming activation rows into registers 0x4..0x7...");
        for (r = 0; r < 4; r = r + 1) begin
            write_reg(4'h4, matrix_A[r][0]);
            write_reg(4'h5, matrix_A[r][1]);
            write_reg(4'h6, matrix_A[r][2]);
            write_reg(4'h7, matrix_A[r][3]);
            // Strobe step/feed (CSR bit 0)
            write_reg(4'h0, 8'h01);
        end

        // Flush pipeline with zeros
        write_reg(4'h4, 8'h00);
        write_reg(4'h5, 8'h00);
        write_reg(4'h6, 8'h00);
        write_reg(4'h7, 8'h00);
        for (r = 0; r < 8; r = r + 1) begin
            write_reg(4'h0, 8'h01);
        end

        // --------------------------------------------------------------------
        // Step 3: Read Back Results from Result Registers 0xC..0xF
        // --------------------------------------------------------------------
        $display("\n[TB] Reading back 4x4 matrix result from registers 0xC..0xF...");
        for (r = 0; r < 4; r = r + 1) begin
            write_reg(4'h3, r[1:0]); // Set target row
            for (c = 0; c < 4; c = c + 1) begin
                write_reg(4'h1, c[1:0]); // Set target column

                read_reg(4'hC, b0);
                read_reg(4'hD, b1);
                read_reg(4'hE, b2);
                read_reg(4'hF, b3);

                matrix_C_actual[r][c] = {b3, b2, b1, b0};

                if (matrix_C_actual[r][c] !== matrix_C_golden[r][c]) begin
                    $display("  [ERROR] Mismatch at C[%0d][%0d]: Got %0d, Expected %0d",
                             r, c, matrix_C_actual[r][c], matrix_C_golden[r][c]);
                    errors = errors + 1;
                end
            end
        end

        $display("\nActual Result Matrix C_actual from NPU Peripheral (INT32):");
        for (r = 0; r < 4; r = r + 1)
            $display("  [%6d %6d %6d %6d ]", matrix_C_actual[r][0], matrix_C_actual[r][1], matrix_C_actual[r][2], matrix_C_actual[r][3]);

        // --------------------------------------------------------------------
        // Verification Summary
        // --------------------------------------------------------------------
        $display("\n================================================================");
        if (errors == 0) begin
            $display("  >>> SUCCESS: ALL 16 MATRIX ELEMENTS MATCH GOLDEN MODEL! <<<");
            $display("  Zero errors detected. TinyQV NPU Peripheral is fully functional.");
        end else begin
            $display("  >>> FAILURE: %0d MISMATCHES DETECTED! <<<", errors);
        end
        $display("================================================================\n");

        #50;
        $finish;
    end

endmodule
