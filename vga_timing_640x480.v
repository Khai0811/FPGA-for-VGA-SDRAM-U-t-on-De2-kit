// vga_timing_640x480.v
// 640x480@60 Hz timing generator (25.175 MHz pixel clock), simplified

module vga_timing_640x480 (
    input  wire clk,
    input  wire reset_n,
    output reg  hsync,
    output reg  vsync,
    output reg  active_video,
    output reg  [9:0] pixel_x,
    output reg  [9:0] pixel_y
);

    // VGA timing constants
    localparam H_VISIBLE    = 640;
    localparam H_FRONT_PORCH = 16;
    localparam H_SYNC_PULSE  = 96;
    localparam H_BACK_PORCH  = 48;
    localparam H_TOTAL       = H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 800

    localparam V_VISIBLE     = 480;
    localparam V_FRONT_PORCH = 10;
    localparam V_SYNC_PULSE  = 2;
    localparam V_BACK_PORCH  = 33;
    localparam V_TOTAL        = V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 525

    reg [9:0] h_count;
    reg [9:0] v_count;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            h_count <= 0;
            v_count <= 0;
            hsync <= 1;
            vsync <= 1;
            active_video <= 0;
            pixel_x <= 0;
            pixel_y <= 0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 0;
                if (v_count == V_TOTAL - 1) begin
                    v_count <= 0;
                end else begin
                    v_count <= v_count + 1;
                end
            end else begin
                h_count <= h_count + 1;
            end

            hsync <= (h_count >= H_VISIBLE + H_FRONT_PORCH && h_count < H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE) ? 0 : 1;
            vsync <= (v_count >= V_VISIBLE + V_FRONT_PORCH && v_count < V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE) ? 0 : 1;

            active_video <= (h_count < H_VISIBLE && v_count < V_VISIBLE);

            pixel_x <= (h_count < H_VISIBLE) ? h_count : 10'd0;
            pixel_y <= (v_count < V_VISIBLE) ? v_count : 10'd0;
        end
    end

endmodule
