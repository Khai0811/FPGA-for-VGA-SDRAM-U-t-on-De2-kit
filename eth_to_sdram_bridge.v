`timescale 1ns/1ps

module eth_to_sdram_bridge (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [15:0] rx_data,
    input  wire        rx_data_valid,
    input  wire        rx_frame_ready,
    output reg         rx_pop,

    output reg         wb_stb_o,
    output reg         wb_cyc_o,
    output reg         wb_we_o,
    output reg  [3:0]  wb_sel_o,
    output reg  [31:0] wb_addr_o,
    output reg  [31:0] wb_data_o,
    input  wire        wb_stall_i,
    input  wire        wb_ack_i
);

    localparam [15:0] MAGIC_ID         = 16'h1606;
    localparam [31:0] LAST_WB_ADDR     = 32'd614396; // (640*480/2 - 1) * 4
    localparam [2:0]
        S_IDLE        = 3'd0,
        S_HDR_MAGIC   = 3'd1,
        S_HDR_CRC_HI  = 3'd2,
        S_HDR_CRC_LO  = 3'd3,
        S_FETCH_PX0   = 3'd4,
        S_FETCH_PX1   = 3'd5,
        S_WB_WRITE    = 3'd6;

    reg [2:0]  state;

    reg [31:0] rx_crc32;

    reg [15:0] pixel0_buf;
    reg [15:0] pixel1_buf;
    reg [31:0] next_wb_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            rx_pop      <= 1'b0;

            wb_stb_o    <= 1'b0;
            wb_cyc_o    <= 1'b0;
            wb_we_o     <= 1'b0;
            wb_sel_o    <= 4'b0000;
            wb_addr_o   <= 32'd0;
            wb_data_o   <= 32'd0;

            rx_crc32    <= 32'd0;
            pixel0_buf  <= 16'd0;
            pixel1_buf  <= 16'd0;
            next_wb_addr <= 32'd0;
        end else begin
            rx_pop <= 1'b0;

            case (state)
                S_IDLE: begin
                    wb_stb_o     <= 1'b0;
                    wb_cyc_o     <= 1'b0;
                    wb_we_o      <= 1'b0;
                    wb_sel_o     <= 4'b0000;
                    wb_addr_o    <= 32'd0;
                    wb_data_o    <= 32'd0;
                    next_wb_addr <= 32'd0;

                    if (rx_frame_ready)
                        state <= S_HDR_MAGIC;
                end

                S_HDR_MAGIC: begin
                    wb_stb_o <= 1'b0;
                    wb_cyc_o <= 1'b0;
                    wb_we_o  <= 1'b0;
                    wb_sel_o <= 4'b0000;

                    if (rx_data_valid) begin
                        rx_pop <= 1'b1;
                        if (rx_data == MAGIC_ID)
                            state <= S_HDR_CRC_HI;
                        else
                            state <= S_IDLE;
                    end
                end

                S_HDR_CRC_HI: begin
                    wb_stb_o <= 1'b0;
                    wb_cyc_o <= 1'b0;
                    wb_we_o  <= 1'b0;
                    wb_sel_o <= 4'b0000;

                    if (rx_data_valid) begin
                        rx_pop          <= 1'b1;
                        rx_crc32[31:16] <= rx_data;
                        state           <= S_HDR_CRC_LO;
                    end
                end

                S_HDR_CRC_LO: begin
                    wb_stb_o <= 1'b0;
                    wb_cyc_o <= 1'b0;
                    wb_we_o  <= 1'b0;
                    wb_sel_o <= 4'b0000;

                    if (rx_data_valid) begin
                        rx_pop         <= 1'b1;
                        rx_crc32[15:0] <= rx_data;
                        next_wb_addr   <= 32'd0;
                        state          <= S_FETCH_PX0;
                    end
                end

                S_FETCH_PX0: begin
                    wb_stb_o <= 1'b0;
                    wb_cyc_o <= 1'b0;
                    wb_we_o  <= 1'b0;
                    wb_sel_o <= 4'b0000;

                    if (rx_data_valid) begin
                        pixel0_buf <= rx_data;
                        rx_pop     <= 1'b1;
                        state      <= S_FETCH_PX1;
                    end
                end

                S_FETCH_PX1: begin
                    wb_stb_o <= 1'b0;
                    wb_cyc_o <= 1'b0;
                    wb_we_o  <= 1'b0;
                    wb_sel_o <= 4'b0000;

                    if (rx_data_valid) begin
                        pixel1_buf <= rx_data;
                        rx_pop     <= 1'b1;

                        wb_addr_o <= next_wb_addr;
                        wb_data_o <= {rx_data, pixel0_buf};
                        wb_sel_o  <= 4'b1111;
                        wb_we_o   <= 1'b1;
                        wb_stb_o  <= 1'b1;
                        wb_cyc_o  <= 1'b1;

                        state <= S_WB_WRITE;
                    end
                end

                S_WB_WRITE: begin
                    wb_addr_o <= next_wb_addr;
                    wb_data_o <= {pixel1_buf, pixel0_buf};
                    wb_sel_o  <= 4'b1111;
                    wb_we_o   <= 1'b1;
                    wb_stb_o  <= 1'b1;
                    wb_cyc_o  <= 1'b1;

                    if (wb_ack_i) begin
                        wb_stb_o <= 1'b0;
                        wb_cyc_o <= 1'b0;
                        wb_we_o  <= 1'b0;
                        wb_sel_o <= 4'b0000;

                        if (next_wb_addr == LAST_WB_ADDR) begin
                            state <= S_IDLE;
                        end else begin
                            next_wb_addr <= next_wb_addr + 32'd4;
                            state        <= S_FETCH_PX0;
                        end
                    end
                end

                default: begin
                    state    <= S_IDLE;
                    rx_pop   <= 1'b0;
                    wb_stb_o <= 1'b0;
                    wb_cyc_o <= 1'b0;
                    wb_we_o  <= 1'b0;
                    wb_sel_o <= 4'b0000;
                end
            endcase
        end
    end

endmodule