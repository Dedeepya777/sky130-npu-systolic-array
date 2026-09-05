// ============================================================================
// Module: tt_um_npu_systolic (npu_tinyqv_wrapper)
// Description: TinyQV / TinyTapeout / Bifurcated RISC-V SoC Compatible Wrapper
//
// Project: 4x4 Weight-Stationary Systolic Array NPU (ASIC / OpenLane Ready)
// Research: "Domain-Specific Accelerator Architectures: NPUs vs. GPUs in On-Device AI"
// Target: TinyTapeout / TinyQV / SkyWater 130nm ASIC Shuttle
//
// Pinout Mapping:
//   ui_in[7:0]   : Dedicated Inputs
//                  ui_in[1:0] : Byte select / column index (0..3)
//                  ui_in[2]   : Weight load strobe (assert to latch byte into weight buffer)
//                  ui_in[3]   : Activation stream strobe (assert to latch byte into act buffer)
//                  ui_in[4]   : Execute row strobe (pulse when 4 bytes loaded to feed row)
//                  ui_in[5]   : Pipeline clear (clr)
//                  ui_in[7:6] : Output byte lane select (selects byte 0..3 of 32-bit psum)
//
//   uio_in[7:0]  : Input Data Bus (INT8 signed operand)
//
//   uo_out[7:0]  : Dedicated Outputs (8-bit slice of 32-bit accumulated result)
//
//   uio_out[7:0] : Status & Output Control
//                  uio_out[0] : busy flag
//                  uio_out[1] : done pulse
//                  uio_out[2] : deskewed_valid
//                  uio_out[5:3] : internal state / debug
//                  uio_out[7:6] : reserved (0)
//
//   uio_oe[7:0]  : Bidirectional I/O direction (configured as 8'hFF = all outputs)
// ============================================================================

`timescale 1ns / 1ps

module tt_um_npu_systolic (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path (data byte in)
    output wire [7:0] uio_out,  // IOs: Output path (status out)
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // Always 1 when powered
    input  wire       clk,      // System Clock
    input  wire       rst_n     // Global active-low reset
);

    localparam integer N      = 4;
    localparam integer DATA_W = 8;
    localparam integer ACC_W  = 32;

    // Configure bidirectional pins: all 8 driven as status outputs
    assign uio_oe = 8'hFF;

    // ------------------------------------------------------------------------
    // Control Signal Decoding from ui_in
    // ------------------------------------------------------------------------
    wire [1:0] byte_sel       = ui_in[1:0];
    wire       weight_wr      = ui_in[2];
    wire       act_wr         = ui_in[3];
    wire       exec_row       = ui_in[4];
    wire       clr_req        = ui_in[5];
    wire [1:0] out_byte_sel   = ui_in[7:6];

    // Data byte from uio_in
    wire signed [DATA_W-1:0] data_byte = uio_in;

    // ------------------------------------------------------------------------
    // 32-bit Row Assembly Registers (4 bytes x 8 bits = 32 bits)
    // ------------------------------------------------------------------------
    reg signed [31:0] weight_row_buf;
    reg signed [31:0] act_row_buf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_row_buf <= 32'd0;
            act_row_buf    <= 32'd0;
        end else begin
            if (weight_wr) begin
                case (byte_sel)
                    2'b00: weight_row_buf[7:0]   <= data_byte;
                    2'b01: weight_row_buf[15:8]  <= data_byte;
                    2'b10: weight_row_buf[23:16] <= data_byte;
                    2'b11: weight_row_buf[31:24] <= data_byte;
                endcase
            end
            if (act_wr) begin
                case (byte_sel)
                    2'b00: act_row_buf[7:0]   <= data_byte;
                    2'b01: act_row_buf[15:8]  <= data_byte;
                    2'b10: act_row_buf[23:16] <= data_byte;
                    2'b11: act_row_buf[31:24] <= data_byte;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------------
    // Core NPU Instance
    // ------------------------------------------------------------------------
    wire signed [N*ACC_W-1:0] raw_psum_out;
    wire [N-1:0]              raw_valid_out;
    wire signed [N*ACC_W-1:0] deskewed_out;
    wire                      deskewed_valid;
    wire                      busy;
    wire                      done;

    npu_top #(
        .N     (N),
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) u_npu_core (
        .clk           (clk),
        .rst_n         (rst_n & ena),
        .clr           (clr_req),

        .weight_en     (weight_wr & (byte_sel == 2'b11)),
        .weight_in     (weight_row_buf),

        .in_valid      (exec_row),
        .act_in        (act_row_buf),

        .bias_in       ({(N*ACC_W){1'b0}}),
        .bias_en       (1'b0),

        .raw_psum_out  (raw_psum_out),
        .raw_valid_out (raw_valid_out),

        .deskewed_out  (deskewed_out),
        .deskewed_valid(deskewed_valid),

        .busy          (busy),
        .done          (done)
    );

    // ------------------------------------------------------------------------
    // Output Multiplexing (Reading 32-bit results via 8-bit output bus)
    // ------------------------------------------------------------------------
    // Output byte lane multiplexer: selects one byte of column byte_sel's 32-bit psum
    reg [7:0] result_byte;
    always @(*) begin
        case (byte_sel)
            2'b00: begin
                case (out_byte_sel)
                    2'b00: result_byte = deskewed_out[7:0];
                    2'b01: result_byte = deskewed_out[15:8];
                    2'b10: result_byte = deskewed_out[23:16];
                    2'b11: result_byte = deskewed_out[31:24];
                endcase
            end
            2'b01: begin
                case (out_byte_sel)
                    2'b00: result_byte = deskewed_out[39:32];
                    2'b01: result_byte = deskewed_out[47:40];
                    2'b10: result_byte = deskewed_out[55:48];
                    2'b11: result_byte = deskewed_out[63:56];
                endcase
            end
            2'b10: begin
                case (out_byte_sel)
                    2'b00: result_byte = deskewed_out[71:64];
                    2'b01: result_byte = deskewed_out[79:72];
                    2'b10: result_byte = deskewed_out[87:80];
                    2'b11: result_byte = deskewed_out[95:88];
                endcase
            end
            2'b11: begin
                case (out_byte_sel)
                    2'b00: result_byte = deskewed_out[103:96];
                    2'b01: result_byte = deskewed_out[111:104];
                    2'b10: result_byte = deskewed_out[119:112];
                    2'b11: result_byte = deskewed_out[127:120];
                endcase
            end
        endcase
    end

    assign uo_out = result_byte;

    // Status output bus
    assign uio_out[0]   = busy;
    assign uio_out[1]   = done;
    assign uio_out[2]   = deskewed_valid;
    assign uio_out[4:3] = raw_valid_out[1:0];
    assign uio_out[5]   = raw_valid_out[3];
    assign uio_out[7:6] = 2'b00;

endmodule
