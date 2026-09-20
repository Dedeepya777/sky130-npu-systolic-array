// ============================================================================
// Testbench: tb_tt_wrapper
// Description: End-to-End SPI Test for tt_um_tqv_peripheral_harness with NPU
//
// Project: 4x4 Weight-Stationary Systolic Array NPU
// Research: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
//
// Tests the full TinyTapeout / TinyQV peripheral chip level over SPI:
//   - SPI Mode 0 (CPOL=0, CPHA=0) on uio_in[4..6] / uio_out[3]
//   - Preloads 4x4 weight matrix via SPI register writes
//   - Streams 4x4 activation matrix via SPI register writes
//   - Reads back 4x4 accumulated matrix via SPI register reads
//   - Validates all 16 results against golden reference model
// ============================================================================

`timescale 1ns / 1ps

module tb_tt_wrapper;

    reg        clk;
    reg        rst_n;
    reg        ena;
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // DUT
    tt_um_tqv_peripheral_harness dut (
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio_in (uio_in),
        .uio_out(uio_out),
        .uio_oe (uio_oe),
        .ena    (ena),
        .clk    (clk),
        .rst_n  (rst_n)
    );

    // 100MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Pin definitions:
    // uio_in[4] = spi_cs_n
    // uio_in[5] = spi_clk
    // uio_in[6] = spi_mosi
    // uio_out[3] = spi_miso

    localparam DELAY = 2; // Clock cycles per half SPI bit

    task spi_write(input [3:0] addr, input [7:0] data);
        integer i;
        begin
            // Idle CS high
            uio_in[4] <= 1'b1;
            uio_in[5] <= 1'b0;
            repeat(DELAY) @(posedge clk);

            // Pull CS low + Write bit (1)
            uio_in[4] <= 1'b0;
            uio_in[6] <= 1'b1;
            repeat(DELAY) @(posedge clk);
            uio_in[5] <= 1'b1; // SCLK high
            repeat(DELAY) @(posedge clk);

            // 3 don't care bits (000)
            for (i = 0; i < 3; i = i + 1) begin
                uio_in[5] <= 1'b0;
                uio_in[6] <= 1'b0;
                repeat(DELAY) @(posedge clk);
                uio_in[5] <= 1'b1;
                repeat(DELAY) @(posedge clk);
            end

            // 4-bit Address (MSB first)
            for (i = 3; i >= 0; i = i - 1) begin
                uio_in[5] <= 1'b0;
                uio_in[6] <= addr[i];
                repeat(DELAY) @(posedge clk);
                uio_in[5] <= 1'b1;
                repeat(DELAY) @(posedge clk);
            end

            // 8-bit Data (MSB first)
            for (i = 7; i >= 0; i = i - 1) begin
                uio_in[5] <= 1'b0;
                uio_in[6] <= data[i];
                repeat(DELAY) @(posedge clk);
                uio_in[5] <= 1'b1;
                repeat(DELAY) @(posedge clk);
            end

            // Deselect CS
            uio_in[5] <= 1'b0;
            repeat(DELAY) @(posedge clk);
            uio_in[4] <= 1'b1;
            repeat(DELAY) @(posedge clk);
        end
    endtask

    task spi_read(input [3:0] addr, output [7:0] data);
        integer i;
        begin
            uio_in[4] <= 1'b1;
            uio_in[5] <= 1'b0;
            repeat(DELAY) @(posedge clk);

            // Pull CS low + Read bit (0)
            uio_in[4] <= 1'b0;
            uio_in[6] <= 1'b0;
            repeat(DELAY) @(posedge clk);
            uio_in[5] <= 1'b1;
            repeat(DELAY) @(posedge clk);

            // 3 don't care bits (000)
            for (i = 0; i < 3; i = i + 1) begin
                uio_in[5] <= 1'b0;
                uio_in[6] <= 1'b0;
                repeat(DELAY) @(posedge clk);
                uio_in[5] <= 1'b1;
                repeat(DELAY) @(posedge clk);
            end

            // 4-bit Address
            for (i = 3; i >= 0; i = i - 1) begin
                uio_in[5] <= 1'b0;
                uio_in[6] <= addr[i];
                repeat(DELAY) @(posedge clk);
                uio_in[5] <= 1'b1;
                repeat(DELAY) @(posedge clk);
            end

            // Allow extra clock as in tqv_reg.py line 190
            @(posedge clk);

            // Read 8-bit Data from MISO (uio_out[3])
            data = 8'h00;
            for (i = 7; i >= 0; i = i - 1) begin
                uio_in[5] <= 1'b0;
                repeat(DELAY) @(posedge clk);
                uio_in[5] <= 1'b1;
                repeat(DELAY) @(posedge clk);
                data[i] = uio_out[3];
            end

            // Final clock edge & deselect CS
            uio_in[5] <= 1'b0;
            repeat(DELAY) @(posedge clk);
            uio_in[4] <= 1'b1;
            repeat(DELAY) @(posedge clk);
        end
    endtask

    // Test Data
    reg signed [7:0]  matrix_A [0:3][0:3];
    reg signed [7:0]  matrix_B [0:3][0:3];
    reg signed [31:0] matrix_C_golden [0:3][0:3];
    reg signed [31:0] matrix_C_actual [0:3][0:3];

    integer r, c, k;
    integer errors;
    reg [7:0] b0, b1, b2, b3;

    initial begin
        $dumpfile("tb_tt_wrapper.vcd");
        $dumpvars(0, tb_tt_wrapper);

        $display("\n================================================================");
        $display("  TinyTapeout SPI Harness Test: 4x4 Systolic Array NPU");
        $display("  Target: tt_um_tqv_peripheral_harness (SPI Mode 0)");
        $display("================================================================\n");

        errors = 0;
        ena    = 1'b1;
        ui_in  = 8'h00;
        uio_in = 8'h10; // CS_n high
        rst_n  = 1'b0;

        #30;
        rst_n  = 1'b1;
        #30;
        $display("[SPI_TB] Power-on reset sequence complete.");

        // Define Matrix B (Stationary Weights):
        matrix_B[0][0] =  8'sd2;  matrix_B[0][1] = -8'sd1;  matrix_B[0][2] =  8'sd3;  matrix_B[0][3] =  8'sd0;
        matrix_B[1][0] =  8'sd1;  matrix_B[1][1] =  8'sd4;  matrix_B[1][2] = -8'sd2;  matrix_B[1][3] =  8'sd1;
        matrix_B[2][0] = -8'sd3;  matrix_B[2][1] =  8'sd2;  matrix_B[2][2] =  8'sd1;  matrix_B[2][3] =  8'sd2;
        matrix_B[3][0] =  8'sd0;  matrix_B[3][1] =  8'sd1;  matrix_B[3][2] = -8'sd1;  matrix_B[3][3] =  8'sd3;

        // Define Matrix A (Activations):
        matrix_A[0][0] =  8'sd3;  matrix_A[0][1] =  8'sd1;  matrix_A[0][2] =  8'sd2;  matrix_A[0][3] =  8'sd0;
        matrix_A[1][0] =  8'sd1;  matrix_A[1][1] = -8'sd2;  matrix_A[1][2] =  8'sd0;  matrix_A[1][3] =  8'sd4;
        matrix_A[2][0] =  8'sd2;  matrix_A[2][1] =  8'sd3;  matrix_A[2][2] = -8'sd1;  matrix_A[2][3] =  8'sd1;
        matrix_A[3][0] =  8'sd0;  matrix_A[3][1] =  8'sd1;  matrix_A[3][2] =  8'sd4;  matrix_A[3][3] = -8'sd2;

        // Compute Golden Reference
        for (r = 0; r < 4; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
                matrix_C_golden[r][c] = 0;
                for (k = 0; k < 4; k = k + 1) begin
                    matrix_C_golden[r][c] = matrix_C_golden[r][c] + (matrix_A[r][k] * matrix_B[k][c]);
                end
            end
        end

        // 1. Preload Weights over SPI
        $display("[SPI_TB] Preloading stationary weights into PE array over SPI...");
        for (r = 3; r >= 0; r = r - 1) begin
            spi_write(4'h8, matrix_B[r][0]);
            spi_write(4'h9, matrix_B[r][1]);
            spi_write(4'hA, matrix_B[r][2]);
            spi_write(4'hB, matrix_B[r][3]);
            // Strobe weight load in CSR
            spi_write(4'h0, 8'h04);
        end
        $display("[SPI_TB] All 16 weights programmed into PE array.");

        // 2. Stream Activations over SPI
        $display("[SPI_TB] Streaming activation rows into NPU over SPI...");
        for (r = 0; r < 4; r = r + 1) begin
            spi_write(4'h4, matrix_A[r][0]);
            spi_write(4'h5, matrix_A[r][1]);
            spi_write(4'h6, matrix_A[r][2]);
            spi_write(4'h7, matrix_A[r][3]);
            // Strobe feed in CSR
            spi_write(4'h0, 8'h01);
        end

        // Flush pipeline
        spi_write(4'h4, 8'h00);
        spi_write(4'h5, 8'h00);
        spi_write(4'h6, 8'h00);
        spi_write(4'h7, 8'h00);
        for (r = 0; r < 8; r = r + 1) begin
            spi_write(4'h0, 8'h01);
        end

        // 3. Read back results over SPI
        $display("[SPI_TB] Reading back 4x4 matrix result elements over SPI MISO...");
        for (r = 0; r < 4; r = r + 1) begin
            spi_write(4'h3, r[1:0]); // Select row
            for (c = 0; c < 4; c = c + 1) begin
                spi_write(4'h1, c[1:0]); // Select column

                spi_read(4'hC, b0);
                spi_read(4'hD, b1);
                spi_read(4'hE, b2);
                spi_read(4'hF, b3);

                matrix_C_actual[r][c] = {b3, b2, b1, b0};

                if (matrix_C_actual[r][c] !== matrix_C_golden[r][c]) begin
                    $display("  [ERROR] Mismatch at C[%0d][%0d]: Got %0d, Expected %0d",
                             r, c, matrix_C_actual[r][c], matrix_C_golden[r][c]);
                    errors = errors + 1;
                end
            end
        end

        $display("\nGolden Reference Matrix C_golden = A x B:");
        for (r = 0; r < 4; r = r + 1)
            $display("  [%6d %6d %6d %6d ]", matrix_C_golden[r][0], matrix_C_golden[r][1], matrix_C_golden[r][2], matrix_C_golden[r][3]);

        $display("\nActual Result Matrix C_actual from SPI Readback:");
        for (r = 0; r < 4; r = r + 1)
            $display("  [%6d %6d %6d %6d ]", matrix_C_actual[r][0], matrix_C_actual[r][1], matrix_C_actual[r][2], matrix_C_actual[r][3]);

        $display("\n================================================================");
        if (errors == 0) begin
            $display("  >>> SUCCESS: FULL CHIP SPI HARNESS PASSED WITH 0 MISMATCHES! <<<");
            $display("  SPI reads/writes verified down to the wire.");
        end else begin
            $display("  >>> FAILURE: %0d MISMATCHES DETECTED! <<<", errors);
        end
        $display("================================================================\n");

        #100;
        $finish;
    end

endmodule
