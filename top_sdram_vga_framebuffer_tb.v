// top_sdram_vga_framebuffer_tb.v
// Testbench for top_sdram_vga_framebuffer
// - init sdram with 2 image zones: pink and orange
// - read out via VGA timing generator
// - no physical pmod, just waveform simulation

`timescale 1ns/1ps

module top_sdram_vga_framebuffer_tb;

    reg clk50;
    reg clk25;
    reg reset_n;

    wire hsync;
    wire vsync;
    wire [7:0] vga_r;
    wire [7:0] vga_g;
    wire [7:0] vga_b;

    top_sdram_vga_framebuffer dut (
        .clk50(clk50),
        .clk25(clk25),
        .reset_n(reset_n),
        .vga_hsync(hsync),
        .vga_vsync(vsync),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b)
    );

    initial begin
        // init clocks
        clk50 = 0;
        clk25 = 0;
        reset_n = 0;
        #200;
        reset_n = 1;
    end

    always #10 clk50 = ~clk50; // 50 MHz
    always #20 clk25 = ~clk25; // 25 MHz

    initial begin
        $dumpfile("top_sdram_vga_framebuffer_tb.vcd");
        $dumpvars(0, top_sdram_vga_framebuffer_tb);
        #20000000; // 20 ms simulation

        $display("Simulation done.");
        $finish;
    end

    // Optionally sample first frame pixel on active video corners.
    reg [7:0] corner_r[0:3];
    reg [7:0] corner_g[0:3];
    reg [7:0] corner_b[0:3];
    integer ccount = 0;

    always @(posedge clk25) begin
        if (reset_n && dut.vgagen.active_video) begin
            if ((dut.vgagen.pixel_x == 0 && dut.vgagen.pixel_y == 0) && ccount == 0) begin
                corner_r[0] <= vga_r; corner_g[0] <= vga_g; corner_b[0] <= vga_b; ccount = ccount + 1;
            end
            if ((dut.vgagen.pixel_x == 639 && dut.vgagen.pixel_y == 0) && ccount == 1) begin
                corner_r[1] <= vga_r; corner_g[1] <= vga_g; corner_b[1] <= vga_b; ccount = ccount + 1;
            end
            if ((dut.vgagen.pixel_x == 0 && dut.vgagen.pixel_y == 239) && ccount == 2) begin
                corner_r[2] <= vga_r; corner_g[2] <= vga_g; corner_b[2] <= vga_b; ccount = ccount + 1;
            end
            if ((dut.vgagen.pixel_x == 639 && dut.vgagen.pixel_y == 239) && ccount == 3) begin
                corner_r[3] <= vga_r; corner_g[3] <= vga_g; corner_b[3] <= vga_b; ccount = ccount + 1;
            end
        end
    end

    always @(posedge clk25) begin
        if (ccount == 4) begin
            $display("Corners RGB:");
            $display("UL %02x %02x %02x", corner_r[0], corner_g[0], corner_b[0]);
            $display("UR %02x %02x %02x", corner_r[1], corner_g[1], corner_b[1]);
            $display("LL %02x %02x %02x", corner_r[2], corner_g[2], corner_b[2]);
            $display("LR %02x %02x %02x", corner_r[3], corner_g[3], corner_b[3]);
            ccount = 5;
        end
    end

endmodule
