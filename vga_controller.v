module vga_controller (
    input wire clk_in,        
    input wire rst,

    output reg hsync,
    output reg vsync,
    output wire video_on,

    output wire [9:0] x,   
    output wire [9:0] y,    
	 output reg clk25
);

    // ========================
    // Clock divider: 50MHz -> 25MHz
    // ========================
    always @(posedge clk_in) begin
        clk25 <= ~clk25;
    end
    // ========================
    // VGA timing parameters
    // ========================
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = 800;

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = 525;

    // ========================
    // Counters
    // ========================
    reg [9:0] h_count = 0;
    reg [9:0] v_count = 0;

    always @(posedge clk25 or posedge rst) begin
        if (rst) begin
            h_count <= 0;
            v_count <= 0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
            end else begin
                h_count <= h_count + 1;
            end
        end
    end

    // ========================
    // HSYNC & VSYNC
    // ========================
    always @(*) begin
        // HSYNC active low
        if (h_count >= (H_VISIBLE + H_FRONT) &&
            h_count <  (H_VISIBLE + H_FRONT + H_SYNC))
            hsync = 0;
        else
            hsync = 1;

        // VSYNC active low
        if (v_count >= (V_VISIBLE + V_FRONT) &&
            v_count <  (V_VISIBLE + V_FRONT + V_SYNC))
            vsync = 0;
        else
            vsync = 1;
    end

    // ========================
    // Video ON (visible area)
    // ========================
    assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

    // ========================
    // Pixel position
    // ========================
    assign x = h_count;
    assign y = v_count;

endmodule