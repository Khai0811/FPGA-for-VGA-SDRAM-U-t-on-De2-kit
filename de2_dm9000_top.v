`timescale 1ns/1ps

module de2_dm9000_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    output wire [8:0]  LEDG,

    inout  wire [15:0] ENET_DATA,
    output wire        ENET_CLK,
    output wire        ENET_CMD,
    output wire        ENET_CS_N,
    input  wire        ENET_INT,
    output wire        ENET_RD_N,
    output wire        ENET_RST_N,
    output wire        ENET_WR_N,

    output wire [11:0] DRAM_ADDR,
    output wire        DRAM_BA_0,
    output wire        DRAM_BA_1,
    output wire        DRAM_CAS_N,
    output wire        DRAM_CKE,
    output wire        DRAM_CLK,
    output wire        DRAM_CS_N,
    inout  wire [15:0] DRAM_DQ,
    output wire        DRAM_LDQM,
    output wire        DRAM_RAS_N,
    output wire        DRAM_UDQM,
    output wire        DRAM_WE_N
);

    wire clk   = CLOCK_50;
    wire rst_n = KEY[0];

    reg enet_clk_div;
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n)
            enet_clk_div <= 1'b0;
        else
            enet_clk_div <= ~enet_clk_div;
    end
    assign ENET_CLK = enet_clk_div;

    wire        bus_req_valid;
    wire        bus_req_ready;
    wire [1:0]  bus_req_cmd;
    wire [7:0]  bus_req_reg_addr;
    wire [15:0] bus_req_wdata;
    wire [15:0] bus_rsp_rdata;
    wire        bus_rsp_valid;

    wire        init_done;
    wire        link_ok;
    wire [15:0] chip_vid;
    wire [15:0] chip_pid;

    wire        tx_start;
    wire        tx_busy;
    wire        tx_done;
    wire [15:0] tx_data;
    wire        tx_data_valid;
    wire        tx_data_ready;

    wire        rx_pop;
    wire [15:0] rx_data;
    wire        rx_data_valid;
    wire [15:0] rx_length_bytes;
    wire        rx_frame_ready;

    wire        wb_stb;
    wire        wb_cyc;
    wire        wb_we;
    wire [3:0]  wb_sel;
    wire [31:0] wb_addr;
    wire [31:0] wb_wdata;
    wire [31:0] wb_rdata;
    wire        wb_stall;
    wire        wb_ack;

    wire        sdram_clk_int;
    wire [12:0] sdram_addr_int;
    wire [1:0]  sdram_ba_int;
    wire [1:0]  sdram_dqm_int;

    assign tx_start      = 1'b0;
    assign tx_data       = 16'd0;
    assign tx_data_valid = 1'b0;

    assign DRAM_CLK  = sdram_clk_int;
    assign DRAM_ADDR = sdram_addr_int[11:0];
    assign DRAM_BA_0 = sdram_ba_int[0];
    assign DRAM_BA_1 = sdram_ba_int[1];
    assign DRAM_LDQM = sdram_dqm_int[0];
    assign DRAM_UDQM = sdram_dqm_int[1];

    dm9000_bus_if u_bus (
        .clk          (ENET_CLK),
        .rst_n        (rst_n),
        .req_valid    (bus_req_valid),
        .req_ready    (bus_req_ready),
        .req_cmd      (bus_req_cmd),
        .req_reg_addr (bus_req_reg_addr),
        .req_wdata    (bus_req_wdata),
        .rsp_rdata    (bus_rsp_rdata),
        .rsp_valid    (bus_rsp_valid),
        .ENET_DATA    (ENET_DATA),
        .ENET_CMD     (ENET_CMD),
        .ENET_CS_N    (ENET_CS_N),
        .ENET_RD_N    (ENET_RD_N),
        .ENET_WR_N    (ENET_WR_N),
        .ENET_RST_N   (ENET_RST_N),
        .ENET_INT     (ENET_INT)
    );

    dm9000_core u_core (
        .clk              (ENET_CLK),
        .rst_n            (rst_n),
        .tx_start         (tx_start),
        .tx_length_bytes  (16'd0),
        .tx_data          (tx_data),
        .tx_data_valid    (tx_data_valid),
        .tx_data_ready    (tx_data_ready),
        .tx_busy          (tx_busy),
        .tx_done          (tx_done),
        .rx_pop           (rx_pop),
        .rx_data          (rx_data),
        .rx_data_valid    (rx_data_valid),
        .rx_length_bytes  (rx_length_bytes),
        .rx_frame_ready   (rx_frame_ready),
        .init_done        (init_done),
        .link_ok          (link_ok),
        .chip_vid         (chip_vid),
        .chip_pid         (chip_pid),
        .bus_req_valid    (bus_req_valid),
        .bus_req_ready    (bus_req_ready),
        .bus_req_cmd      (bus_req_cmd),
        .bus_req_reg_addr (bus_req_reg_addr),
        .bus_req_wdata    (bus_req_wdata),
        .bus_rsp_rdata    (bus_rsp_rdata),
        .bus_rsp_valid    (bus_rsp_valid),
        .enet_int         (ENET_INT)
    );

    eth_to_sdram_bridge u_bridge (
        .clk            (ENET_CLK),
        .rst_n          (rst_n),
        .rx_data        (rx_data),
        .rx_data_valid  (rx_data_valid),
        .rx_frame_ready (rx_frame_ready),
        .rx_pop         (rx_pop),
        .wb_stb_o       (wb_stb),
        .wb_cyc_o       (wb_cyc),
        .wb_we_o        (wb_we),
        .wb_sel_o       (wb_sel),
        .wb_addr_o      (wb_addr),
        .wb_data_o      (wb_wdata),
        .wb_stall_i     (wb_stall),
        .wb_ack_i       (wb_ack)
    );

    sdram #(
        .SDRAM_MHZ    (50),
        .SDRAM_TARGET ("ALTERA")
    ) u_sdram (
        .clk_i         (ENET_CLK),
        .rst_i         (~rst_n),
        .stb_i         (wb_stb),
        .we_i          (wb_we),
        .sel_i         (wb_sel),
        .cyc_i         (wb_cyc),
        .addr_i        (wb_addr),
        .data_i        (wb_wdata),
        .data_o        (wb_rdata),
        .stall_o       (wb_stall),
        .ack_o         (wb_ack),
        .sdram_clk_o   (sdram_clk_int),
        .sdram_cke_o   (DRAM_CKE),
        .sdram_cs_o    (DRAM_CS_N),
        .sdram_ras_o   (DRAM_RAS_N),
        .sdram_cas_o   (DRAM_CAS_N),
        .sdram_we_o    (DRAM_WE_N),
        .sdram_dqm_o   (sdram_dqm_int),
        .sdram_addr_o  (sdram_addr_int),
        .sdram_ba_o    (sdram_ba_int),
        .sdram_data_io (DRAM_DQ)
    );

    assign LEDG[0] = init_done;
    assign LEDG[1] = link_ok;
    assign LEDG[2] = rx_frame_ready;
    assign LEDG[3] = rx_data_valid;
    assign LEDG[4] = rx_pop;
    assign LEDG[5] = wb_stb;
    assign LEDG[6] = wb_ack;
    assign LEDG[7] = wb_stall;
    assign LEDG[8] = chip_vid[15];

endmodule