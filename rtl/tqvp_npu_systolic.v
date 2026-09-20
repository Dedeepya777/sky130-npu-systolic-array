/*
 * Module: tqvp_npu_systolic
 * Description: 4x4 Weight-Stationary Systolic Array NPU Peripheral for TinyQV
 *
 * Research Project: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
 * Compatible with Michael Bell's TinyQV RISC-V SoC & TinyTapeout Harness
 *
 * Memory Map (16 8-bit registers, address 0x0 to 0xF):
 *   0x0 : CSR (Control & Status Register)
 *         Write:
 *           bit 0: step/feed activation row (1-cycle pulse)
 *           bit 1: clear pipeline registers (1-cycle pulse)
 *           bit 2: load weight row into systolic array (1-cycle pulse)
 *           bit 3: enable bias
 *         Read:
 *           bit 0: busy
 *           bit 1: done (all 4 rows computed and captured)
 *           bit 2: deskewed_valid (current cycle valid)
 *           bit 3: capture complete (4 rows stored in result buffer)
 *   0x1 : COL_SEL - Selects column index (0..3) for result readout
 *   0x2 : WEIGHT_ROW_SEL - Target row index (0..3) for weight loading
 *   0x3 : ROW_SEL - Selects row index (0..3) for result readout
 *   0x4 : ACT_0 - INT8 signed activation input for Row 0
 *   0x5 : ACT_1 - INT8 signed activation input for Row 1
 *   0x6 : ACT_2 - INT8 signed activation input for Row 2
 *   0x7 : ACT_3 - INT8 signed activation input for Row 3
 *   0x8 : WEIGHT_0 - INT8 signed weight input for Col 0
 *   0x9 : WEIGHT_1 - INT8 signed weight input for Col 1
 *   0xA : WEIGHT_2 - INT8 signed weight input for Col 2
 *   0xB : WEIGHT_3 - INT8 signed weight input for Col 3
 *   0xC : RESULT_B0 - Byte 0 (bits [7:0], LSB) of C[ROW_SEL][COL_SEL]
 *   0xD : RESULT_B1 - Byte 1 (bits [15:8]) of C[ROW_SEL][COL_SEL]
 *   0xE : RESULT_B2 - Byte 2 (bits [23:16]) of C[ROW_SEL][COL_SEL]
 *   0xF : RESULT_B3 - Byte 3 (bits [31:24], MSB) of C[ROW_SEL][COL_SEL]
 */

`default_nettype none

module tqvp_npu_systolic (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  ui_in,
    output wire [7:0]  uo_out,

    input  wire [3:0]  address,
    input  wire        data_write,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out
);

    localparam integer N      = 4;
    localparam integer DATA_W = 8;
    localparam integer ACC_W  = 32;

    // ------------------------------------------------------------------------
    // Internal Registers
    // ------------------------------------------------------------------------
    reg [1:0] col_sel_reg;
    reg [1:0] row_sel_reg;
    reg [1:0] weight_row_reg;
    reg       bias_en_reg;

    reg signed [DATA_W-1:0] act_buf [0:N-1];
    reg signed [DATA_W-1:0] weight_buf [0:N-1];

    // Single-cycle control pulses
    reg step_pulse;
    reg clr_pulse;
    reg weight_load_pulse;

    // ------------------------------------------------------------------------
    // 4x4 Output Capture Buffer: Stores full 32-bit results for all 16 elements
    // ------------------------------------------------------------------------
    reg signed [ACC_W-1:0] result_matrix [0:N-1][0:N-1];
    reg [2:0]              captured_rows_cnt;
    wire                   capture_complete = (captured_rows_cnt >= 3'd4);

    // ------------------------------------------------------------------------
    // Core NPU Instance Signals
    // ------------------------------------------------------------------------
    wire signed [N*DATA_W-1:0] weight_in_bus;
    wire signed [N*DATA_W-1:0] act_in_bus;
    wire signed [N*ACC_W-1:0]  deskewed_out;
    wire                       deskewed_valid;
    wire                       busy;
    wire                       done;

    assign weight_in_bus = {weight_buf[3], weight_buf[2], weight_buf[1], weight_buf[0]};
    assign act_in_bus    = {act_buf[3],    act_buf[2],    act_buf[1],    act_buf[0]};

    npu_top #(
        .N     (N),
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) u_npu_core (
        .clk           (clk),
        .rst_n         (rst_n),
        .clr           (clr_pulse),
        .weight_en     (weight_load_pulse),
        .weight_in     (weight_in_bus),
        .in_valid      (step_pulse),
        .act_in        (act_in_bus),
        .bias_in       ({(N*ACC_W){1'b0}}),
        .bias_en       (bias_en_reg),
        .raw_psum_out  (),
        .raw_valid_out (),
        .deskewed_out  (deskewed_out),
        .deskewed_valid(deskewed_valid),
        .busy          (busy),
        .done          (done)
    );

    // ------------------------------------------------------------------------
    // Bus Write Logic & Pulse Generation
    // ------------------------------------------------------------------------
    integer i, j;
    always @(posedge clk) begin
        if (!rst_n) begin
            col_sel_reg        <= 2'd0;
            row_sel_reg        <= 2'd0;
            weight_row_reg     <= 2'd0;
            bias_en_reg        <= 1'b0;
            step_pulse         <= 1'b0;
            clr_pulse          <= 1'b0;
            weight_load_pulse  <= 1'b0;
            captured_rows_cnt  <= 3'd0;

            for (i = 0; i < N; i = i + 1) begin
                act_buf[i]    <= {DATA_W{1'b0}};
                weight_buf[i] <= {DATA_W{1'b0}};
                for (j = 0; j < N; j = j + 1) begin
                    result_matrix[i][j] <= {ACC_W{1'b0}};
                end
            end
        end else begin
            // Pulses self-clear every cycle
            step_pulse        <= 1'b0;
            clr_pulse         <= 1'b0;
            weight_load_pulse <= 1'b0;

            // Handle Register Writes
            if (data_write) begin
                case (address)
                    4'h0: begin
                        step_pulse        <= data_in[0];
                        clr_pulse         <= data_in[1];
                        weight_load_pulse <= data_in[2];
                        bias_en_reg       <= data_in[3];
                        if (data_in[1]) begin
                            captured_rows_cnt <= 3'd0;
                        end
                    end
                    4'h1: col_sel_reg    <= data_in[1:0];
                    4'h2: weight_row_reg <= data_in[1:0];
                    4'h3: row_sel_reg    <= data_in[1:0];
                    4'h4: act_buf[0]     <= data_in;
                    4'h5: act_buf[1]     <= data_in;
                    4'h6: act_buf[2]     <= data_in;
                    4'h7: act_buf[3]     <= data_in;
                    4'h8: weight_buf[0]  <= data_in;
                    4'h9: weight_buf[1]  <= data_in;
                    4'hA: weight_buf[2]  <= data_in;
                    4'hB: weight_buf[3]  <= data_in;
                    default: ;
                endcase
            end

            // Capture deskewed output matrix rows as they emerge
            if (deskewed_valid && (captured_rows_cnt < 3'd4)) begin
                result_matrix[captured_rows_cnt[1:0]][0] <= deskewed_out[31:0];
                result_matrix[captured_rows_cnt[1:0]][1] <= deskewed_out[63:32];
                result_matrix[captured_rows_cnt[1:0]][2] <= deskewed_out[95:64];
                result_matrix[captured_rows_cnt[1:0]][3] <= deskewed_out[127:96];
                captured_rows_cnt <= captured_rows_cnt + 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Read Multiplexer
    // ------------------------------------------------------------------------
    wire signed [ACC_W-1:0] current_res = result_matrix[row_sel_reg][col_sel_reg];

    always @(*) begin
        case (address)
            4'h0: data_out = {4'b0000, capture_complete, deskewed_valid, done, busy};
            4'h1: data_out = {6'b000000, col_sel_reg};
            4'h2: data_out = {6'b000000, weight_row_reg};
            4'h3: data_out = {6'b000000, row_sel_reg};
            4'h4: data_out = act_buf[0];
            4'h5: data_out = act_buf[1];
            4'h6: data_out = act_buf[2];
            4'h7: data_out = act_buf[3];
            4'h8: data_out = weight_buf[0];
            4'h9: data_out = weight_buf[1];
            4'hA: data_out = weight_buf[2];
            4'hB: data_out = weight_buf[3];
            4'hC: data_out = current_res[7:0];
            4'hD: data_out = current_res[15:8];
            4'hE: data_out = current_res[23:16];
            4'hF: data_out = current_res[31:24];
            default: data_out = 8'h00;
        endcase
    end

    // Real-time output: mirror currently selected byte to uo_out
    assign uo_out = data_out;

    // Unused input tie-off
    wire _unused = &{ui_in, 1'b0};

endmodule
