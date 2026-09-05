// ============================================================================
// Testbench: npu_tb
// Description: Comprehensive Self-Checking Verification Suite for 4x4 NPU
//
// Project: 4x4 Weight-Stationary Systolic Array NPU
// Paper: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
//
// Verification Features:
//   1. 100MHz clock generation and asynchronous/synchronous reset sequencing.
//   2. Automated weight loading task with stationary verification.
//   3. Activation stream stimulus generator with systolic timing.
//   4. Independent golden model computing C = A x B via nested arithmetic loops.
//   5. Automated output capture and comparison against golden reference.
//   6. Multi-test scenario coverage:
//      - Test 1: Paper Reference Matrix (values 1..16)
//      - Test 2: Identity Matrix (activation passthrough check)
//      - Test 3: Mixed Signed Positive and Negative Values (2's complement check)
//      - Test 4: Extreme INT8 Values (+127, -128, 32-bit accumulation headroom)
//      - Test 5: Stationary Weight Reuse (multiple consecutive inferences)
//      - Test 6: Sparse / All-Zeros Matrix
//   7. Cycle-accurate VCD waveform dumping for GTKWave inspection.
//   8. Formatted ASCII matrix display and final PASS/FAIL summary.
// ============================================================================

`timescale 1ns / 1ps

module npu_tb;

    localparam int N      = 4;
    localparam int DATA_W = 8;
    localparam int ACC_W  = 32;
    localparam int CLK_PERIOD = 10; // 10ns -> 100 MHz

    // ------------------------------------------------------------------------
    // DUT Signals (Packed 2D vectors for robust simulator compatibility)
    // ------------------------------------------------------------------------
    logic                                  clk;
    logic                                  rst_n;
    logic                                  clr;

    logic                                  weight_en;
    logic signed [N-1:0][DATA_W-1:0]       weight_in;

    logic                                  in_valid;
    logic signed [N-1:0][DATA_W-1:0]       act_in;

    logic signed [N-1:0][ACC_W-1:0]        bias_in;
    logic                                  bias_en;

    wire  signed [N-1:0][ACC_W-1:0]        raw_psum_out;
    wire  [N-1:0]                          raw_valid_out;

    wire  signed [N-1:0][ACC_W-1:0]        deskewed_out;
    wire                                   deskewed_valid;

    wire                                   busy;
    wire                                   done;

    // ------------------------------------------------------------------------
    // Testbench Matrix Storage (Module-level for universal simulator portability)
    // ------------------------------------------------------------------------
    logic signed [DATA_W-1:0] A_mat    [N][N];
    logic signed [DATA_W-1:0] B_mat    [N][N];
    logic signed [ACC_W-1:0]  C_golden [N][N];
    logic signed [ACC_W-1:0]  C_actual [N][N];

    int total_tests  = 0;
    int passed_tests = 0;
    int failed_tests = 0;
    int total_errors = 0;

    // ------------------------------------------------------------------------
    // DUT Instantiation
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
    task print_matrix_A;
        $display("Matrix A (Activations %0dx%0d INT%0d):", N, N, DATA_W);
        for (int r = 0; r < N; r++) begin
            $write("  [ ");
            for (int c = 0; c < N; c++) begin
                $write("%6d ", A_mat[r][c]);
            end
            $display("]");
        end
    endtask

    task print_matrix_B;
        $display("Matrix B (Weights %0dx%0d INT%0d):", N, N, DATA_W);
        for (int r = 0; r < N; r++) begin
            $write("  [ ");
            for (int c = 0; c < N; c++) begin
                $write("%6d ", B_mat[r][c]);
            end
            $display("]");
        end
    endtask

    task print_matrix_results;
        $display("Expected Result Matrix C_golden (INT%0d):", ACC_W);
        for (int r = 0; r < N; r++) begin
            $write("  [ ");
            for (int c = 0; c < N; c++) begin
                $write("%10d ", C_golden[r][c]);
            end
            $display("]");
        end
        $display("Actual Result Matrix C_actual from NPU RTL (INT%0d):", ACC_W);
        for (int r = 0; r < N; r++) begin
            $write("  [ ");
            for (int c = 0; c < N; c++) begin
                $write("%10d ", C_actual[r][c]);
            end
            $display("]");
        end
    endtask

    // ------------------------------------------------------------------------
    // Independent Golden Model
    // ------------------------------------------------------------------------
    task compute_golden;
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                longint sum;
                sum = 0;
                for (int k = 0; k < N; k++) begin
                    sum = sum + (longint'(A_mat[r][k]) * longint'(B_mat[k][c]));
                end
                C_golden[r][c] = sum[ACC_W-1:0];
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Task: Reset Sequence
    // ------------------------------------------------------------------------
    task apply_reset;
        rst_n     = 1'b0;
        clr       = 1'b0;
        weight_en = 1'b0;
        in_valid  = 1'b0;
        bias_en   = 1'b0;
        for (int i = 0; i < N; i++) begin
            weight_in[i] = '0;
            act_in[i]    = '0;
            bias_in[i]   = '0;
        end
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        $display("[TB] Reset released at simulation time %0t ps", $time);
    endtask

    // ------------------------------------------------------------------------
    // Task: Systolic Weight Preload
    // ------------------------------------------------------------------------
    task load_weights;
        $display("----------------------------------------------------------------");
        $display("[TB] Preloading %0dx%0d Stationary Weights down columns...", N, N);
        print_matrix_B;

        @(negedge clk);
        weight_en = 1'b1;

        for (int step = N - 1; step >= 0; step--) begin
            for (int c = 0; c < N; c++) begin
                weight_in[c] = B_mat[step][c];
            end
            @(negedge clk);
        end

        weight_en = 1'b0;
        for (int c = 0; c < N; c++) begin
            weight_in[c] = '0;
        end
        @(posedge clk);
        $display("[TB] Stationary weights preloaded into all 16 PEs.");
    endtask

    // ------------------------------------------------------------------------
    // Task: Run Inference Test
    // ------------------------------------------------------------------------
    task run_test(
        input string test_title,
        input bit    reload_weights
    );
        int err_count;
        err_count = 0;
        total_tests++;

        $display("\n================================================================");
        $display(" TEST %0d: %s", total_tests, test_title);
        $display("================================================================");

        if (reload_weights) begin
            load_weights;
        end else begin
            $display("[TB] Retaining stationary weights from previous run (Weight Reuse).");
        end

        // Compute golden reference
        compute_golden;
        print_matrix_A;

        // Clear actual result buffer
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                C_actual[r][c] = '0;
            end
        end

        // Stream Matrix A rows into NPU top
        $display("[TB] Streaming activation rows into NPU...");
        @(negedge clk);
        for (int r = 0; r < N; r++) begin
            in_valid = 1'b1;
            for (int c = 0; c < N; c++) begin
                act_in[c] = A_mat[r][c];
            end
            @(negedge clk);
        end

        // Deassert in_valid after all N rows streamed
        in_valid = 1'b0;
        for (int c = 0; c < N; c++) begin
            act_in[c] = '0;
        end

        // Capture deskewed output matrix C row by row
        $display("[TB] Waiting for deskewed results to emerge...");
        @(posedge clk);
        while (!deskewed_valid) @(posedge clk);

        // Deskewed valid is high at this posedge: sample Row 0
        for (int c = 0; c < N; c++) begin
            C_actual[0][c] = deskewed_out[c];
        end

        // Sample remaining rows 1..N-1 on subsequent cycles
        for (int r = 1; r < N; r++) begin
            @(posedge clk);
            for (int c = 0; c < N; c++) begin
                C_actual[r][c] = deskewed_out[c];
            end
        end

        // Wait a few cycles for pipeline to settle
        repeat (3) @(posedge clk);

        // Display results
        print_matrix_results;

        // Check each element
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                if (C_actual[r][c] !== C_golden[r][c]) begin
                    $display("  [ERROR] Mismatch at C[%0d][%0d]: Expected = %0d, Actual = %0d",
                             r, c, C_golden[r][c], C_actual[r][c]);
                    err_count++;
                end
            end
        end

        if (err_count == 0) begin
            $display(">>> [PASS] %s: All %0d matrix elements match golden model perfectly!", test_title, N*N);
            passed_tests++;
        end else begin
            $display(">>> [FAIL] %s: %0d mismatch(es) detected!", test_title, err_count);
            failed_tests++;
            total_errors = total_errors + err_count;
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Verification Process
    // ------------------------------------------------------------------------
    initial begin
        // Waveform dumping for GTKWave inspection
        $dumpfile("sim/npu_sim.vcd");
        $dumpvars(0, npu_tb);
        $display("[TB] VCD Waveform dump enabled -> sim/npu_sim.vcd");

        $display("\n****************************************************************");
        $display("*     COS231 Research: 4x4 Weight-Stationary NPU Testbench     *");
        $display("****************************************************************\n");

        apply_reset;

        // --------------------------------------------------------------------
        // TEST 1: Paper Reference Matrix (Values 1..16)
        // --------------------------------------------------------------------
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                A_mat[r][c] = r * N + c + 1;
                B_mat[r][c] = r * N + c + 1;
            end
        end
        run_test("Paper Reference Matrix Test (Sequential 1..16)", 1'b1);

        // --------------------------------------------------------------------
        // TEST 2: Identity Matrix Test (B = I_4)
        // Verifies activation passthrough and weight mapping correctness: A x I = A
        // --------------------------------------------------------------------
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                A_mat[r][c] = (r + 1) * 10 + (c + 1);
                B_mat[r][c] = (r == c) ? 8'sd1 : 8'sd0;
            end
        end
        run_test("Identity Matrix Test (A x I_4 = A)", 1'b1);

        // --------------------------------------------------------------------
        // TEST 3: Signed Mixed Positive and Negative Values (2's Complement)
        // --------------------------------------------------------------------
        A_mat[0][0] =  8'sd12; A_mat[0][1] = -8'sd5;  A_mat[0][2] =  8'sd3;  A_mat[0][3] = -8'sd8;
        A_mat[1][0] = -8'sd7;  A_mat[1][1] =  8'sd15; A_mat[1][2] = -8'sd2;  A_mat[1][3] =  8'sd9;
        A_mat[2][0] =  8'sd4;  A_mat[2][1] = -8'sd11; A_mat[2][2] =  8'sd6;  A_mat[2][3] = -8'sd1;
        A_mat[3][0] = -8'sd14; A_mat[3][1] =  8'sd8;  A_mat[3][2] = -8'sd10; A_mat[3][3] =  8'sd13;

        B_mat[0][0] =  8'sd2;  B_mat[0][1] = -8'sd4;  B_mat[0][2] =  8'sd7;  B_mat[0][3] = -8'sd3;
        B_mat[1][0] = -8'sd6;  B_mat[1][1] =  8'sd1;  B_mat[1][2] = -8'sd9;  B_mat[1][3] =  8'sd5;
        B_mat[2][0] =  8'sd8;  B_mat[2][1] = -8'sd3;  B_mat[2][2] =  8'sd2;  B_mat[2][3] = -8'sd4;
        B_mat[3][0] = -8'sd5;  B_mat[3][1] =  8'sd12; B_mat[3][2] = -8'sd1;  B_mat[3][3] =  8'sd6;
        run_test("Signed Mixed Positive/Negative Test (2's Complement)", 1'b1);

        // --------------------------------------------------------------------
        // TEST 4: Extreme INT8 Boundary Values (+127, -128)
        // --------------------------------------------------------------------
        A_mat[0][0] =  8'sd127; A_mat[0][1] = -8'sd128; A_mat[0][2] =  8'sd127; A_mat[0][3] = -8'sd128;
        A_mat[1][0] = -8'sd128; A_mat[1][1] =  8'sd127; A_mat[1][2] = -8'sd128; A_mat[1][3] =  8'sd127;
        A_mat[2][0] =  8'sd120; A_mat[2][1] = -8'sd120; A_mat[2][2] =  8'sd110; A_mat[2][3] = -8'sd110;
        A_mat[3][0] = -8'sd100; A_mat[3][1] =  8'sd100; A_mat[3][2] = -8'sd90;  A_mat[3][3] =  8'sd90;

        B_mat[0][0] =  8'sd127; B_mat[0][1] = -8'sd128; B_mat[0][2] =  8'sd127; B_mat[0][3] = -8'sd128;
        B_mat[1][0] = -8'sd128; B_mat[1][1] =  8'sd127; B_mat[1][2] = -8'sd128; B_mat[1][3] =  8'sd127;
        B_mat[2][0] =  8'sd127; B_mat[2][1] =  8'sd127; B_mat[2][2] = -8'sd128; B_mat[2][3] = -8'sd128;
        B_mat[3][0] = -8'sd128; B_mat[3][1] = -8'sd128; B_mat[3][2] =  8'sd127; B_mat[3][3] =  8'sd127;
        run_test("Extreme INT8 Boundary Test (+127 / -128 Dynamic Range)", 1'b1);

        // --------------------------------------------------------------------
        // TEST 5: Weight-Stationary Data Reuse Test
        // Retain stationary weights from Test 4 and run a new activation matrix
        // WITHOUT reloading weights!
        // --------------------------------------------------------------------
        A_mat[0][0] = 8'sd1; A_mat[0][1] = 8'sd2; A_mat[0][2] = 8'sd3; A_mat[0][3] = 8'sd4;
        A_mat[1][0] = 8'sd5; A_mat[1][1] = 8'sd6; A_mat[1][2] = 8'sd7; A_mat[1][3] = 8'sd8;
        A_mat[2][0] = 8'sd2; A_mat[2][1] = 8'sd4; A_mat[2][2] = 8'sd6; A_mat[2][3] = 8'sd8;
        A_mat[3][0] = 8'sd1; A_mat[3][1] = 8'sd3; A_mat[3][2] = 8'sd5; A_mat[3][3] = 8'sd7;
        run_test("Stationary Weight Reuse Test (Inference without Reload)", 1'b0);

        // --------------------------------------------------------------------
        // TEST 6: Sparse and Zero Matrix Test
        // --------------------------------------------------------------------
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                A_mat[r][c] = (r == 1 && c == 2) ? 8'sd42 : 8'sd0;
                B_mat[r][c] = 8'sd0;
            end
        end
        run_test("Sparse & Zero Matrix Test", 1'b1);

        // --------------------------------------------------------------------
        // Final Summary Report
        // ------------------------------------------------------------------------
        $display("\n================================================================");
        $display("                    FINAL VERIFICATION REPORT                    ");
        $display("================================================================");
        $display("  Total Tests Executed : %0d", total_tests);
        $display("  Tests Passed         : %0d", passed_tests);
        $display("  Tests Failed         : %0d", failed_tests);
        $display("  Total Errors         : %0d", total_errors);
        $display("================================================================");

        if (failed_tests == 0) begin
            $display("  *** SUCCESS: ALL TESTS PASSED WITH 0 MISMATCHES! ***");
        end else begin
            $display("  *** FAILURE: %0d TEST(S) FAILED! ***", failed_tests);
        end
        $display("================================================================\n");

        $finish;
    end

endmodule
