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

	 reg clk25;


    // ========================
    // VGA Controller
    // ========================
    wire video_on;
    wire [9:0] x, y;

    vga_controller vga (
        .clk_in(CLOCK_50),   // ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ FIX: dÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¹ng clock 25MHz
        .rst(rst),
        .hsync(VGA_HS),
        .vsync(VGA_VS),
        .video_on(video_on),
        .x(x),
        .y(y),
		  .clk25(VGA_CLK)
    );

    // ========================
    // RGB logic (10-bit)
    // ========================
    reg [9:0] r, g, b;

    always @(*) begin
        if (video_on) begin
            // mÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂºÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â·c ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¹Ã…â€œÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â»ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¹nh = 0
            r = 10'd0;
            g = 10'd0;
            b = 10'd0;

            // SW control
            if (SW[0]) r = 10'h3FF; // max ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¹Ã…â€œÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â»ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â
            if (SW[1]) g = 10'h3FF; // max xanh lÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡
            if (SW[2]) b = 10'h3FF; // max xanh dÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ng
        end else begin
            r = 0;
            g = 0;
            b = 0;
        end
    end

    // ========================
    // Output
    // ========================
    assign VGA_R = r;
    assign VGA_G = g;
    assign VGA_B = b;
    assign VGA_BLANK = SW[3];
    assign VGA_SYNC  = 1'b0;

endmodule