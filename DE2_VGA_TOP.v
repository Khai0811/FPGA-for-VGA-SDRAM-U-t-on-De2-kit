module DE2_VGA_TOP (

    // ===== CLOCK =====
    input CLOCK_50,

    // ===== KEY (active low) =====
    input [3:0] KEY,

    // ===== SWITCH =====
    input [3:0] SW,   // SW[0]=R, SW[1]=G, SW[2]=B

    // ===== VGA =====
    output [9:0] VGA_R,
    output [9:0] VGA_G,
    output [9:0] VGA_B,
    output VGA_HS,
    output VGA_VS,
    output VGA_CLK,
    output VGA_BLANK,
    output VGA_SYNC
);

    // ========================
    // Reset
    // ========================
    wire rst;
    assign rst = ~KEY[0];

    // ========================
    // Internal signals
    // ========================
    wire video_on;
    wire [9:0] x, y;

    wire [4:0] r;
    wire [5:0] g;
    wire [4:0] b;

    // FIFO giáº£ láº­p (test)
    wire [15:0] fifo_top;
    assign fifo_top = {x[9:2], y[9:2]};  // fake data

    // ========================
    // VGA Controller
    // ========================
    vga_controller vga (
        .clk_in(CLOCK_50),
        .rst(rst),
        .hsync(VGA_HS),
        .vsync(VGA_VS),
        .video_on(video_on),
        .x(x),
        .y(y),
        .clk25(VGA_CLK)
    );

    // ========================
    // DATA 565 â†’ RGB
    // ========================
    vga_data565 data (
        .fifo_top(fifo_top),
        .r(r),
        .g(g),
        .b(b)
    );

    // ========================
    // Mask theo SW + video_on
    // ========================
    wire [4:0] r_out;
    wire [5:0] g_out;
    wire [4:0] b_out;

    assign r_out = (video_on && SW[0]) ? r : 5'b0;
    assign g_out = (video_on && SW[1]) ? g : 6'b0;
    assign b_out = (video_on && SW[2]) ? b : 5'b0;

    // ========================
    // Output VGA (10-bit DAC)
    // ========================
    assign VGA_R = {r_out, 5'b0};
    assign VGA_G = {g_out, 4'b0};
    assign VGA_B = {b_out, 5'b0};

    assign VGA_BLANK = 1'b1;  // luÃ´n báº­t
    assign VGA_SYNC  = 1'b0;

endmodule