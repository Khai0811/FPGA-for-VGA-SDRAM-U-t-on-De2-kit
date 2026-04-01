// top_sdram_vga_framebuffer.v
// Top-level: VGA timing + full SDRAM controller + async FIFO.

module top_sdram_vga_framebuffer (
    input  wire        clk50,
    input  wire        clk25,
    input  wire        reset_n,

    // VGA output
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,

    // SDRAM pins for DE2 MT48LC4M16A2
    output wire [12:0] sdram_addr,
    output wire [1:0]  sdram_ba,
    output wire        sdram_cs_n,
    output wire        sdram_ras_n,
    output wire        sdram_cas_n,
    output wire        sdram_we_n,
    inout  wire [15:0] sdram_dq,
    output wire [1:0]  sdram_dqm,
    output wire        sdram_cke
);

    // VGA timing
    wire active_video;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;

    vga_timing_640x480 vgagen (
        .clk(clk25),
        .reset_n(reset_n),
        .hsync(vga_hsync),
        .vsync(vga_vsync),
        .active_video(active_video),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y)
    );

    // SDRAM controller interface
    reg  sdram_write_req;
    reg  sdram_read_req;
    reg  [22:0] sdram_host_addr;
    reg  [15:0] sdram_host_wdata;
    wire [15:0] sdram_host_rdata;
    wire        sdram_busy;
    wire        sdram_ready;

    sdram_controller_full sdram_ctrl (
        .clk50(clk50),
        .reset_n(reset_n),
        .write_req(sdram_write_req),
        .read_req(sdram_read_req),
        .addr(sdram_host_addr),
        .write_data(sdram_host_wdata),
        .read_data(sdram_host_rdata),
        .busy(sdram_busy),
        .ready(sdram_ready),
        .sdram_addr(sdram_addr),
        .sdram_ba(sdram_ba),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_dq(sdram_dq),
        .sdram_dqm(sdram_dqm),
        .sdram_cke(sdram_cke)
    );

    // Async FIFO for 50MHz SDRAM -> 25MHz VGA
    wire fifo_full, fifo_empty;
    wire fifo_almost_full, fifo_almost_empty;
    reg  fifo_wr_en;
    reg  [15:0] fifo_wr_data;
    reg  fifo_rd_en;
    wire [15:0] fifo_rd_data;

    async_fifo_16x2048 pixel_fifo (
        .wr_clk(clk50),
        .rd_clk(clk25),
        .reset_n(reset_n),
        .wr_en(fifo_wr_en),
        .rd_en(fifo_rd_en),
        .wr_data(fifo_wr_data),
        .rd_data(fifo_rd_data),
        .full(fifo_full),
        .empty(fifo_empty),
        .almost_full(fifo_almost_full),
        .almost_empty(fifo_almost_empty)
    );

    // Init SDRAM frame buffer: top half magenta (pink), bottom half orange
    localparam TOTAL_PIXELS = 23'd307200; // 640 x 480
    reg [22:0] init_index;
    reg init_done;

    always @(posedge clk50 or negedge reset_n) begin
        if (!reset_n) begin
            init_index <= 23'd0;
            init_done <= 1'b0;
            sdram_write_req <= 1'b0;
            sdram_host_addr <= 23'd0;
            sdram_host_wdata <= 16'd0;
        end else if (!init_done) begin
            if (!sdram_busy && sdram_ready) begin
                sdram_write_req <= 1'b1;
                sdram_host_addr <= init_index;
                if (init_index < (TOTAL_PIXELS >> 1))
                    sdram_host_wdata <= 16'hF81F; // pink
                else
                    sdram_host_wdata <= 16'hFC00; // orange

                if (init_index == TOTAL_PIXELS - 1) begin
                    init_done <= 1'b1;
                end else begin
                    init_index <= init_index + 1;
                end
            end else begin
                sdram_write_req <= 1'b0;
            end
        end else begin
            sdram_write_req <= 1'b0;
        end
    end

    // Read loop into FIFO once init complete
    reg [22:0] read_index;

    always @(posedge clk50 or negedge reset_n) begin
        if (!reset_n) begin
            read_index <= 23'd0;
            sdram_read_req <= 1'b0;
            sdram_host_addr <= 23'd0;
        end else if (init_done && !fifo_almost_full) begin
            if (!sdram_busy && sdram_ready) begin
                sdram_read_req <= 1'b1;
                sdram_host_addr <= read_index;
                read_index <= read_index + 1;
                if (read_index == TOTAL_PIXELS - 1)
                    read_index <= 23'd0;
            end else begin
                sdram_read_req <= 1'b0;
            end
        end else begin
            sdram_read_req <= 1'b0;
        end
    end

    // FIFO write from SDRAM read data
    always @(posedge clk50 or negedge reset_n) begin
        if (!reset_n) begin
            fifo_wr_en <= 1'b0;
            fifo_wr_data <= 16'd0;
        end else begin
            if (init_done && !fifo_full && sdram_ready && !sdram_busy) begin
                fifo_wr_en <= 1'b1;
                fifo_wr_data <= sdram_host_rdata;
            end else begin
                fifo_wr_en <= 1'b0;
            end
        end
    end

    // FIFO read for VGA
    reg [15:0] pixel_data;
    always @(posedge clk25 or negedge reset_n) begin
        if (!reset_n) begin
            fifo_rd_en <= 1'b0;
            pixel_data <= 16'd0;
        end else if (active_video && !fifo_empty) begin
            fifo_rd_en <= 1'b1;
            pixel_data <= fifo_rd_data;
        end else begin
            fifo_rd_en <= 1'b0;
        end
    end

    assign vga_r = active_video ? {pixel_data[15:11], pixel_data[15:13]} : 8'd0;
    assign vga_g = active_video ? {pixel_data[10:5], pixel_data[10:9]} : 8'd0;
    assign vga_b = active_video ? {pixel_data[4:0], pixel_data[4:2]} : 8'd0;

endmodule
