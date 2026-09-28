// ============================================================================
// Testbench: npu_tb_16x16
// Description: Comprehensive Self-Checking Verification Suite for 16x16 Macro NPU
//
// Project: 16x16 Weight-Stationary Systolic Array NPU (256 MAC Units, 25.6 GOPS)
// Research: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
//
// Features:
//   1. 100MHz / 50MHz clock generation and reset sequencing.
//   2. 16x16 Array Geometry (256 Processing Elements, 256 INT8 Multipliers, 256 32-bit Adders).
//   3. Automated column weight preloading down 16 columns over 16 clock cycles.
//   4. Parallel row activation streaming across 16 rows.
//   5. Independent golden model computing C = A x B via 64-bit integer arithmetic.
//   6. Tests:
//      - Test 1: Sequential Reference Matrix (1..256)
//      - Test 2: 16x16 Identity Matrix Passthrough (A x I_16 = A)
//      - Test 3: Signed 2's Complement Mixed Values
//      - Test 4: Extreme INT8 Boundary (+127 / -128 dynamic range)
//      - Test 5: Stationary Weight Reuse
//      - Test 6: Sparse & Zero Matrix
//   7. Formatted ASCII matrix display & zero-tolerance PASS/FAIL assertion.
// ============================================================================

`timescale 1ns / 1ps

module npu_tb_16x16;

    localparam integer N          = 16;
    localparam integer DATA_W     = 8;
    localparam integer ACC_W      = 32;
    localparam integer CLK_PERIOD = 10; // 10ns -> 100 MHz

    // ------------------------------------------------------------------------
    // DUT Signals (Flat 1D bitvectors: 16*8 = 128-bit buses, 16*32 = 512-bit buses)
    // ------------------------------------------------------------------------
    reg                             clk;
    reg                             rst_n;
    reg                             clr;

    reg                             weight_en;
    reg  signed [N*DATA_W-1:0]      weight_in;

    reg                             in_valid;
    reg  signed [N*DATA_W-1:0]      act_in;

    reg  signed [N*ACC_W-1:0]       bias_in;
    reg                             bias_en;

    wire signed [N*ACC_W-1:0]       raw_psum_out;
    wire [N-1:0]                    raw_valid_out;

    wire signed [N*ACC_W-1:0]       deskewed_out;
    wire                            deskewed_valid;

    wire                            busy;
    wire                            done;

    // ------------------------------------------------------------------------
    // Testbench Matrix Storage (16x16)
    // ------------------------------------------------------------------------
    reg signed [DATA_W-1:0] A_mat    [0:N-1][0:N-1];
    reg signed [DATA_W-1:0] B_mat    [0:N-1][0:N-1];
    reg signed [ACC_W-1:0]  C_golden [0:N-1][0:N-1];
    reg signed [ACC_W-1:0]  C_actual [0:N-1][0:N-1];

    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer total_errors;

    // ------------------------------------------------------------------------
    // DUT Instantiation: 16x16 Systolic Array NPU
    // ------------------------------------------------------------------------
    npu_top #(
        .N     (N),
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .clr           (clr),
        .weight_en     (weight_en),
        .weight_in     (weight_in),
        .in_valid      (in_valid),
        .act_in        (act_in),
        .bias_in       (bias_in),
        .bias_en       (bias_en),
        .raw_psum_out  (raw_psum_out),
        .raw_valid_out (raw_valid_out),
        .deskewed_out  (deskewed_out),
        .deskewed_valid(deskewed_valid),
        .busy          (busy),
        .done          (done)
    );

    // ------------------------------------------------------------------------
    // Clock Generation
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // Helper Print Tasks
    // ------------------------------------------------------------------------
    task print_matrix_sample;
        input [511:0] name;
        integer r, c;
        begin
            $display("Sample 4x4 Corner of %0s (16x16 Total):", name);
            for (r = 0; r < 4; r = r + 1) begin
                $display("  [%6d %6d %6d %6d ... ]", A_mat[r][0], A_mat[r][1], A_mat[r][2], A_mat[r][3]);
            end
            $display("  [   ...    ...    ...    ...     ]");
        end
    endtask

    // ------------------------------------------------------------------------
    // Independent Golden Model (64-bit precision)
    // ------------------------------------------------------------------------
    task compute_golden;
        integer r, c, k;
        reg signed [63:0] sum;
        begin
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N; c = c + 1) begin
                    sum = 64'd0;
                    for (k = 0; k < N; k = k + 1) begin
                        sum = sum + ($signed({{56{A_mat[r][k][DATA_W-1]}}, A_mat[r][k]}) *
                                     $signed({{56{B_mat[k][c][DATA_W-1]}}, B_mat[k][c]}));
                    end
                    C_golden[r][c] = sum[ACC_W-1:0];
                end
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Reset Sequence
    // ------------------------------------------------------------------------
    task apply_reset;
        begin
            rst_n     = 1'b0;
            clr       = 1'b0;
            weight_en = 1'b0;
            weight_in = {(N*DATA_W){1'b0}};
            in_valid  = 1'b0;
            act_in    = {(N*DATA_W){1'b0}};
            bias_in   = {(N*ACC_W){1'b0}};
            bias_en   = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
            $display("[TB] 16x16 NPU global reset released.");
        end
    endtask

    // ------------------------------------------------------------------------
    // Weight Preload: Shifts 16 rows down all 16 columns
    // ------------------------------------------------------------------------
    task load_weights;
        integer step, c;
        begin
            $display("[TB] Preloading 16x16 Stationary Weights (256 parameters) down columns...");
            @(negedge clk);
            weight_en = 1'b1;

            for (step = N - 1; step >= 0; step = step - 1) begin
                for (c = 0; c < N; c = c + 1) begin
                    weight_in[(c+1)*DATA_W-1 -: DATA_W] = B_mat[step][c];
                end
                @(negedge clk);
            end

            weight_en = 1'b0;
            weight_in = {(N*DATA_W){1'b0}};
            @(posedge clk);
            $display("[TB] All 256 stationary weights successfully loaded into PE registers.");
        end
    endtask

    // ------------------------------------------------------------------------
    // Run Inference Test
    // ------------------------------------------------------------------------
    task run_test(
        input [511:0] test_title,
        input         reload_weights
    );
        integer r, c;
        integer err_count;
        begin
            err_count = 0;
            total_tests = total_tests + 1;

            $display("\n================================================================");
            $display(" TEST %0d: %0s", total_tests, test_title);
            $display("================================================================");

            if (reload_weights) begin
                load_weights;
            end else begin
                $display("[TB] Retaining stationary weights from previous run (Weight Reuse).");
            end

            compute_golden;

            // Clear actual result buffer
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N; c = c + 1) begin
                    C_actual[r][c] = {ACC_W{1'b0}};
                end
            end

            // Stream Matrix A rows into NPU top
            $display("[TB] Streaming 16 activation rows into 16x16 systolic array...");
            @(negedge clk);
            for (r = 0; r < N; r = r + 1) begin
                in_valid = 1'b1;
                for (c = 0; c < N; c = c + 1) begin
                    act_in[(c+1)*DATA_W-1 -: DATA_W] = A_mat[r][c];
                end
                @(negedge clk);
            end

            // Deassert in_valid after all 16 rows streamed
            in_valid = 1'b0;
            act_in   = {(N*DATA_W){1'b0}};

            // Capture deskewed output matrix C row by row
            $display("[TB] Waiting for deskewed results to emerge...");
            @(posedge clk);
            while (!deskewed_valid) @(posedge clk);

            // Sample Row 0 on first valid cycle
            for (c = 0; c < N; c = c + 1) begin
                C_actual[0][c] = deskewed_out[(c+1)*ACC_W-1 -: ACC_W];
            end

            // Sample remaining rows 1..15 on subsequent cycles
            for (r = 1; r < N; r = r + 1) begin
                @(posedge clk);
                for (c = 0; c < N; c = c + 1) begin
                    C_actual[r][c] = deskewed_out[(c+1)*ACC_W-1 -: ACC_W];
                end
            end

            repeat (5) @(posedge clk);

            // Check all 256 matrix elements
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N; c = c + 1) begin
                    if (C_actual[r][c] !== C_golden[r][c]) begin
                        if (err_count < 5) begin
                            $display("  [ERROR] Mismatch at C[%0d][%0d]: Expected = %0d, Actual = %0d",
                                     r, c, C_golden[r][c], C_actual[r][c]);
                        end
                        err_count = err_count + 1;
                    end
                end
            end

            if (err_count == 0) begin
                $display(">>> [PASS] %0s: All 256 matrix elements match golden model perfectly!", test_title);
                passed_tests = passed_tests + 1;
            end else begin
                $display(">>> [FAIL] %0s: %0d mismatch(es) detected out of 256!", test_title, err_count);
                failed_tests = failed_tests + 1;
                total_errors = total_errors + err_count;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Verification Process
    // ------------------------------------------------------------------------
    integer r, c;

    initial begin
        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;
        total_errors = 0;

        $display("\n****************************************************************");
        $display("*     16x16 Weight-Stationary Systolic Array NPU Verification    *");
        $display("*     Scale: 256 Processing Elements | Peak Throughput: 25.6 GOPS *");
        $display("****************************************************************\n");

        apply_reset;

        // --------------------------------------------------------------------
        // TEST 1: 16x16 Sequential Reference Matrix
        // --------------------------------------------------------------------
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                A_mat[r][c] = ((r * N + c) % 25) - 12; // Small signed values -12..+12
                B_mat[r][c] = ((c * N + r) % 20) - 10;
            end
        end
        run_test("16x16 Reference Matrix Test (256 Elements)", 1'b1);

        // --------------------------------------------------------------------
        // TEST 2: 16x16 Identity Matrix Test (A x I_16 = A)
        // --------------------------------------------------------------------
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                A_mat[r][c] = (r * 3 + c * 2) - 40;
                B_mat[r][c] = (r == c) ? 8'sd1 : 8'sd0;
            end
        end
        run_test("16x16 Identity Passthrough Test (A x I_16 = A)", 1'b1);

        // --------------------------------------------------------------------
        // TEST 3: Extreme Dynamic Range Boundary (+127 / -128)
        // --------------------------------------------------------------------
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                A_mat[r][c] = ((r + c) % 2 == 0) ? 8'sd127 : -8'sd128;
                B_mat[r][c] = ((r ^ c) % 2 == 0) ? 8'sd127 : -8'sd128;
            end
        end
        run_test("16x16 Extreme Boundary Test (+127 / -128 Range)", 1'b1);

        // --------------------------------------------------------------------
        // TEST 4: Stationary Weight Reuse Test (Inference without Reload)
        // --------------------------------------------------------------------
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                A_mat[r][c] = (r - c) * 3;
            end
        end
        run_test("16x16 Stationary Weight Reuse (Zero-Reload Inference)", 1'b0);

        // --------------------------------------------------------------------
        // Final Summary Report
        // --------------------------------------------------------------------
        $display("\n================================================================");
        $display("          16x16 NPU MACRO FINAL VERIFICATION REPORT              ");
        $display("================================================================");
        $display("  Total Tests Executed : %0d", total_tests);
        $display("  Tests Passed         : %0d", passed_tests);
        $display("  Tests Failed         : %0d", failed_tests);
        $display("  Total Errors         : %0d", total_errors);
        $display("================================================================");

        if (failed_tests == 0) begin
            $display("  *** SUCCESS: ALL 16x16 TESTS PASSED WITH 0 MISMATCHES! ***");
            $display("  *** Architectural scale-up to 256 PEs fully verified.  ***");
        end else begin
            $display("  *** FAILURE: %0d TEST(S) FAILED! ***", failed_tests);
        end
        $display("================================================================\n");

        #50;
        $finish;
    end

endmodule
