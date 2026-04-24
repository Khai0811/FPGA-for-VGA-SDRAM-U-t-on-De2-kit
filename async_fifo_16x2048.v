// async_fifo_16x2048.v
// Asynchronous FIFO for crossing 50 MHz write domain to 25 MHz read domain.

module async_fifo_16x2048 (
    input  wire wr_clk,
    input  wire rd_clk,
    input  wire reset_n,
    input  wire wr_en,
    input  wire rd_en,
    input  wire [15:0] wr_data,
    output reg  [15:0] rd_data,
    output wire full,
    output wire empty,
    output wire almost_full,
    output wire almost_empty
);

    localparam DEPTH = 2048;
    localparam ADDR_WIDTH = 11;

    reg [15:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0] wr_ptr, rd_ptr;
    reg [ADDR_WIDTH:0] wr_ptr_gray, rd_ptr_gray;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;

    // Gray code conversions
    function [ADDR_WIDTH:0] bin2gray;
        input [ADDR_WIDTH:0] bin;
        begin
            bin2gray = (bin >> 1) ^ bin;
        end
    endfunction

    always @(posedge wr_clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr <= 0;
            wr_ptr_gray <= 0;
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
            if (wr_en && !full) begin
                mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1;
                wr_ptr_gray <= bin2gray(wr_ptr + 1);
            end
        end
    end

    always @(posedge rd_clk or negedge reset_n) begin
        if (!reset_n) begin
            rd_ptr <= 0;
            rd_ptr_gray <= 0;
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
            rd_data <= 16'd0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
            if (rd_en && !empty) begin
                rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
                rd_ptr <= rd_ptr + 1;
                rd_ptr_gray <= bin2gray(rd_ptr + 1);
            end
        end
    end

    // Status flags
    wire [ADDR_WIDTH:0] wr_ptr_sync = wr_ptr_gray_sync2;
    wire [ADDR_WIDTH:0] rd_ptr_sync = rd_ptr_gray_sync2;

    assign empty = (rd_ptr_gray == wr_ptr_sync);

    assign full = ( (wr_ptr_gray[ADDR_WIDTH] != rd_ptr_sync[ADDR_WIDTH]) &&
                    (wr_ptr_gray[ADDR_WIDTH-1] != rd_ptr_sync[ADDR_WIDTH-1]) &&
                    (wr_ptr_gray[ADDR_WIDTH-2:0] == rd_ptr_sync[ADDR_WIDTH-2:0]) );

    assign almost_empty = ( ({1'b0, rd_ptr_gray[ADDR_WIDTH-1:0]} + 11'd4) == wr_ptr_sync[ADDR_WIDTH:0] );
    assign almost_full  = ( ({1'b0, wr_ptr_gray[ADDR_WIDTH-1:0]} + 11'd4) == rd_ptr_sync[ADDR_WIDTH:0] );

endmodule
