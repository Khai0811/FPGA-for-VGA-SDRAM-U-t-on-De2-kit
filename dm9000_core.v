module dm9000_core (
    input  wire        clk, //clk 
    input  wire        rst_n,

    // TX stream in
    input  wire        tx_start,
    input  wire [15:0] tx_length_bytes,
    input  wire [15:0] tx_data,
    input  wire        tx_data_valid,
    output reg         tx_data_ready,
    output reg         tx_busy,
    output reg         tx_done,

    // RX stream out
    input  wire        rx_pop,
    output reg  [15:0] rx_data,
    output reg         rx_data_valid,
    output reg  [15:0] rx_length_bytes,
    output reg         rx_frame_ready,

    // Status
    output reg         init_done,
    output reg         link_ok,
    output reg  [15:0] chip_vid,
    output reg  [15:0] chip_pid,

    // Bus interface
    output reg         bus_req_valid, 
    input  wire        bus_req_ready,
    output reg  [1:0]  bus_req_cmd,
    output reg  [7:0]  bus_req_reg_addr,
    output reg  [15:0] bus_req_wdata,
    input  wire [15:0] bus_rsp_rdata,
    input  wire        bus_rsp_valid,   // check data that is valid 

    input  wire        enet_int  // interrupt to alter news packet
);
    // Bus command encoding (sent to dm9000_bus_if)
    localparam CMD_REG_WRITE = 2'b00;  // Write INDEX port (addr) then write DATA port (value)
    localparam CMD_REG_READ  = 2'b01;  // Write INDEX port (addr) then read  DATA port (value)
    localparam CMD_DATA_W16  = 2'b10;  // Write 16-bit directly to DATA port (no index step)
    localparam CMD_DATA_R16  = 2'b11;  // Read  16-bit directly from DATA port (no index step)

    // DM9000A register addresses
    localparam NCR   = 8'h00;  // Network Control Register    (reset, loopback mode)
    localparam NSR   = 8'h01;  // Network Status Register     (link status bit[6], TX complete bit[2])
    localparam TCR   = 8'h02;  // TX Control Register         (write 0x01 to kick transmit)
    localparam RCR   = 8'h05;  // RX Control Register         (enable RX, promiscuous, filter)
    localparam GPCR  = 8'h1E;  // General Purpose Control Reg (set GPIO direction)
    localparam GPR   = 8'h1F;  // General Purpose Register    (write 0x00 to power on PHY)
    localparam TRPAL = 8'h22;  // TX Packet Length Low  byte
    localparam TRPAH = 8'h23;  // TX Packet Length High byte
    localparam VIDL  = 8'h28;  // Vendor  ID Low  byte (expect 0x46 -> VID=0x0A46)
    localparam VIDH  = 8'h29;  // Vendor  ID High byte (expect 0x0A)
    localparam PIDL  = 8'h2A;  // Product ID Low  byte (expect 0x00 -> PID=0x9000)
    localparam PIDH  = 8'h2B;  // Product ID High byte (expect 0x90)
    localparam ISR   = 8'hFE;  // Interrupt Status Register   (write 0xFF to clear all flags)
    localparam IMR   = 8'hFF;  // Interrupt Mask Register     (0x83 = enable RX+TX interrupt)

    // FSM states 
    localparam S_BOOT            = 8'd0;   // Read Vendor ID Low byte (VIDL)
    localparam S_RD_VIDL         = 8'd1;   // (unused, S_BOOT handles VIDL)
    localparam S_RD_VIDH         = 8'd2;   // Read Vendor ID High byte (VIDH)
    localparam S_RD_PIDL         = 8'd3;   // Read Product ID Low byte (PIDL)
    localparam S_RD_PIDH         = 8'd4;   // Read Product ID High byte (PIDH)
    localparam S_WR_GPCR         = 8'd5;   // Write GPCR=0x01: set GPIO as output
    localparam S_WR_GPR          = 8'd6;   // Write GPR=0x00:  power on PHY
    localparam S_WR_NCR          = 8'd7;   // Write NCR=0x00:  normal operation mode
    localparam S_WR_RCR          = 8'd8;   // Write RCR=0x39:  enable RX, promiscuous
    localparam S_WR_IMR          = 8'd9;   // Write IMR=0x83:  enable interrupt -> init_done=1
    // FSM states -- Main loop
    localparam S_IDLE            = 8'd10;  // Read NSR -> update link_ok
    localparam S_POLL_NSR        = 8'd11;  // Decision: tx_start->TX, enet_int->RX, else->IDLE
    // FSM states -- TX path
    localparam S_TX_LEN_LO       = 8'd12;  // Write TX length low byte to TRPAL
    localparam S_TX_LEN_HI       = 8'd13;  // Write TX length high byte to TRPAH
    localparam S_TX_PUSH         = 8'd14;  // Push 16-bit words to DATA port (loop)
    localparam S_TX_KICK         = 8'd15;  // Write TCR=0x01 to start transmission
    localparam S_TX_WAIT         = 8'd16;  // Poll NSR[2] until TX complete -> tx_done=1
    // FSM states -- RX path
    localparam S_RX_STATUS       = 8'd17;  // Read status word from DATA port
    localparam S_RX_LENGTH       = 8'd18;  // Read length word -> rx_frame_ready=1
    localparam S_RX_DATA         = 8'd19;  // Read data words (rx_pop driven loop)
    localparam S_CLR_ISR         = 8'd20;  // Write ISR=0xFF to clear interrupt flags
    reg [7:0]  state;
    reg [15:0] tx_words_left;
    reg [15:0] rx_words_left;

    task automatic issue_reg_read(input [7:0] addr);
    begin
        bus_req_valid    <= 1'b1;
        bus_req_cmd      <= CMD_REG_READ;
        bus_req_reg_addr <= addr;
        bus_req_wdata    <= 16'h0000;
    end
    endtask

    task automatic issue_reg_write(input [7:0] addr, input [7:0] val);
    begin
        bus_req_valid    <= 1'b1;
        bus_req_cmd      <= CMD_REG_WRITE;
        bus_req_reg_addr <= addr;
        bus_req_wdata    <= {8'h00, val};
    end
    endtask

    task automatic issue_data_write(input [15:0] val);
    begin
        bus_req_valid    <= 1'b1;
        bus_req_cmd      <= CMD_DATA_W16;
        bus_req_reg_addr <= 8'h00;
        bus_req_wdata    <= val;
    end
    endtask

    task automatic issue_data_read;
    begin
        bus_req_valid    <= 1'b1;
        bus_req_cmd      <= CMD_DATA_R16;
        bus_req_reg_addr <= 8'h00;
        bus_req_wdata    <= 16'h0000;
    end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_BOOT;
            tx_words_left    <= 16'd0;
            rx_words_left    <= 16'd0;

            bus_req_valid    <= 1'b0;
            bus_req_cmd      <= 2'b00;
            bus_req_reg_addr <= 8'd0;
            bus_req_wdata    <= 16'd0;

            tx_data_ready    <= 1'b0;
            tx_busy          <= 1'b0;
            tx_done          <= 1'b0;

            rx_data          <= 16'd0;
            rx_data_valid    <= 1'b0;
            rx_length_bytes  <= 16'd0;
            rx_frame_ready   <= 1'b0;

            init_done        <= 1'b0;
            link_ok          <= 1'b0;
            chip_vid         <= 16'd0;
            chip_pid         <= 16'd0;
        end else begin
            tx_done       <= 1'b0;
            rx_data_valid <= 1'b0;
            // check bus response and clear request 
            if (bus_req_valid && bus_req_ready)
                bus_req_valid <= 1'b0;
            case (state)
                // state 0 -> 3 be used to check status of the chip and read VID/PID to confirm we are talking to the right device
                S_BOOT: begin
                    if (!bus_req_valid) issue_reg_read(VIDL);
                    if (bus_rsp_valid) begin
                        chip_vid[7:0] <= bus_rsp_rdata[7:0];
                        state <= S_RD_VIDH;
                    end
                end

                S_RD_VIDH: begin
                    if (!bus_req_valid) issue_reg_read(VIDH);
                    if (bus_rsp_valid) begin
                        chip_vid[15:8] <= bus_rsp_rdata[7:0];
                        state <= S_RD_PIDL;
                    end
                end
                S_RD_PIDL: begin
                    if (!bus_req_valid) issue_reg_read(PIDL);
                    if (bus_rsp_valid) begin
                        chip_pid[7:0] <= bus_rsp_rdata[7:0];
                        state <= S_RD_PIDH;
                    end
                end

                S_RD_PIDH: begin
                    if (!bus_req_valid) issue_reg_read(PIDH);
                    if (bus_rsp_valid) begin
                        chip_pid[15:8] <= bus_rsp_rdata[7:0];
                        state <= S_WR_GPCR;
                    end
                end
                // to set gpio diraction 
                S_WR_GPCR: begin
                    if (!bus_req_valid) issue_reg_write(GPCR, 8'h01);
                    if (bus_rsp_valid) state <= S_WR_GPR;
                end
                // to power on the phy
                S_WR_GPR: begin
                    if (!bus_req_valid) issue_reg_write(GPR, 8'h00);
                    if (bus_rsp_valid) state <= S_WR_NCR;
                end
                // to set normal operation mode (not reset, not loopback)
                S_WR_NCR: begin
                    if (!bus_req_valid) issue_reg_write(NCR, 8'h00);
                    if (bus_rsp_valid) state <= S_WR_RCR;
                end
                // to enable RX, promiscuous mode, and unicast/multicast/broadcast filter
                S_WR_RCR: begin
                    if (!bus_req_valid) issue_reg_write(RCR, 8'h39);
                    if (bus_rsp_valid) state <= S_WR_IMR;
                end
                // to enable RX and TX interrupts -> after this step, init_done=1 and we enter main loop (S_IDLE)
                S_WR_IMR: begin
                    if (!bus_req_valid) issue_reg_write(IMR, 8'h83);
                    if (bus_rsp_valid) begin
                        init_done <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                // state 10: main loop, wait for either tx_start or enet_int
                S_IDLE: begin
                    tx_data_ready <= 1'b0;
                    if (!bus_req_valid) issue_reg_read(NSR);
                    if (bus_rsp_valid) begin
                        link_ok <= bus_rsp_rdata[6];
                        state   <= S_POLL_NSR;
                    end
                end
                //decision point after reading NSR in main loop. If tx_start=1, go to TX path. Else if enet_int=1, go to RX path. Else, go back to IDLE and keep polling NSR.
                S_POLL_NSR: begin
                    if (tx_start) begin
                        tx_busy       <= 1'b1;
                        tx_words_left <= tx_length_bytes[15:1] + tx_length_bytes[0];
                        state         <= S_TX_LEN_LO;
                    end else if (enet_int) begin
                        state <= S_RX_STATUS;
                    end else begin
                        state <= S_IDLE;
                    end
                end
                // TX path states: first write length, then push data, then kick off transmission, then wait for completion
                S_TX_LEN_LO: begin
                    if (!bus_req_valid) issue_reg_write(TRPAL, tx_length_bytes[7:0]);
                    if (bus_rsp_valid) state <= S_TX_LEN_HI;
                end
                // write high byte of length to TRPAH
                S_TX_LEN_HI: begin
                    if (!bus_req_valid) issue_reg_write(TRPAH, tx_length_bytes[15:8]);
                    if (bus_rsp_valid) state <= S_TX_PUSH;
                end
                // push data words to DATA port in a loop until all words are sent. Then write TCR=0x01 to kick off transmission, and poll NSR[2] until TX complete
                S_TX_PUSH: begin
                    tx_data_ready <= bus_req_ready && !bus_req_valid;
                    if (tx_words_left == 16'd0) begin
                        tx_data_ready <= 1'b0;
                        state <= S_TX_KICK;
                    end else if (tx_data_valid && !bus_req_valid) begin
                        issue_data_write(tx_data);
                        tx_words_left <= tx_words_left - 16'd1;
                    end
                end
                // write TCR=0x01 to start transmission
                S_TX_KICK: begin
                    if (!bus_req_valid) issue_reg_write(TCR, 8'h01);
                    if (bus_rsp_valid) state <= S_TX_WAIT;
                end
                // poll NSR[2] until TX complete -> tx_done=1, then go back to IDLE
                S_TX_WAIT: begin
                    if (!bus_req_valid) issue_reg_read(NSR);
                    if (bus_rsp_valid && bus_rsp_rdata[2]) begin
                        tx_busy <= 1'b0;
                        tx_done <= 1'b1;
                        state   <= S_IDLE;
                    end
                end
                // RX path states: first read status, then read length, then read data in a loop until frame is done, then clear interrupt flags
                S_RX_STATUS: begin
                    if (!bus_req_valid) issue_data_read();
                    if (bus_rsp_valid) state <= S_RX_LENGTH;
                end
                // read length word from DATA port. Set rx_frame_ready=1 to indicate to external logic that length is available and frame is being processed. Then loop in S_RX_DATA to read words until entire frame is read (rx_words_left==0), then clear interrupt flags and go back to IDLE.
                S_RX_LENGTH: begin
                    if (!bus_req_valid) issue_data_read();
                    if (bus_rsp_valid) begin
                        rx_length_bytes <= bus_rsp_rdata;
                        rx_words_left   <= bus_rsp_rdata[15:1] + bus_rsp_rdata[0];
                        rx_frame_ready  <= 1'b1;
                        state           <= S_RX_DATA;
                    end
                end
                // loop in this state while rx_pop is pulsed by external logic to read out words until entire frame is read (rx_words_left==0), then clear interrupt flags and go back to IDLE
                S_RX_DATA: begin
                    if (rx_frame_ready && rx_pop && rx_words_left != 16'd0 && !bus_req_valid)
                        issue_data_read();

                    if (bus_rsp_valid) begin
                        rx_data       <= bus_rsp_rdata;
                        rx_data_valid <= 1'b1;
                        rx_words_left <= rx_words_left - 16'd1;

                        if (rx_words_left == 16'd1) begin
                            rx_frame_ready <= 1'b0;
                            state <= S_CLR_ISR;
                        end
                    end
                end
                // write 0xFF to ISR to clear interrupt flags, then go back to IDLE
                S_CLR_ISR: begin
                    if (!bus_req_valid) issue_reg_write(ISR, 8'hFF);
                    if (bus_rsp_valid) state <= S_IDLE;
                end

                default: state <= S_BOOT;
            endcase
        end
    end
endmodule
