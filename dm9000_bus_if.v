`timescale 1ns/1ps
module dm9000_bus_if (
    input  wire        clk,          // System clock (Reference for strobe timing)
    input  wire        rst_n,        // Asynchronous active-low reset

    // --- Internal Core Interface (Avalon-ST like Handshaking) ---
    input  wire        req_valid,    // High when a new command is issued by core
    output reg         req_ready,    // High when interface is idle and ready for next command
    input  wire [1:0]  req_cmd,      // [00: Reg Write, 01: Reg Read, 10: Data W16, 11: Data R16]
    input  wire [7:0]  req_reg_addr, // Target DM9000A register index
    input  wire [15:0] req_wdata,    // Payload for write operations

    output reg  [15:0] rsp_rdata,    // Latched data from DM9000A read cycle
    output reg         rsp_valid,    // Single-cycle pulse indicating rsp_rdata is valid

    // --- External Hardware Interface
    inout  wire [15:0] ENET_DATA,    // Multiplexed Bi-directional Data/Address bus
    output reg         ENET_CMD,     // Command type: 0 = Index Port, 1 = Data Port
    output reg         ENET_CS_N,    // Chip Select (Active Low)
    output reg         ENET_RD_N,    // Read Strobe (Active Low)
    output reg         ENET_WR_N,    // Write Strobe (Active Low)
    output reg         ENET_RST_N,   // Hardware Reset to PHY (Active Low)
    input  wire        ENET_INT      // Interrupt request from DM9000A
);
    localparam CMD_REG_WRITE = 2'b00; // Phase 1: Write Index -> Phase 2: Write Data
    localparam CMD_REG_READ  = 2'b01; // Phase 1: Write Index -> Phase 2: Read Data
    localparam CMD_DATA_W16  = 2'b10; // Direct Data Write (Skips Index phase)
    localparam CMD_DATA_R16  = 2'b11; // Direct Data Read (Skips Index phase)

    // FSM State 
    localparam S_RESET_HOLD  = 4'd0;  // Asserting HW Reset (T_RST requirement)
    localparam S_RESET_REL   = 4'd1;  // De-asserting Reset, wait for PLL/Internal Regs
    localparam S_IDLE        = 4'd2;  // Bus Idle, monitoring req_valid
    localparam S_IDX_SETUP   = 4'd3;  // Address Setup: CMD=0, Drive Address on Bus
    localparam S_IDX_PULSE   = 4'd4;  // Address Latch: Pull WR_N low (T_AS/T_AH)
    localparam S_DATA_SETUP  = 4'd5;  // Data Access Setup: CMD=1, Port switching
    localparam S_DATA_WRITE  = 4'd6;  // Data Write Cycle: Pull WR_N low (T_DS/T_DH)
    localparam S_DATA_READ   = 4'd7;  // Data Read Cycle: Pull RD_N low (T_ACC)
    localparam S_DONE        = 4'd8;  // Pulse completion, bus turn-around time

    reg [3:0]  state;
    reg [15:0] reset_cnt;
    reg [1:0]  cmd_latched;
    reg [7:0]  reg_latched;
    reg [15:0] wdata_latched;
    reg        data_oe;      // Output Enable for Tri-state Data Bus
    reg [15:0] data_out;

    // --- Bi-directional Bus Logic (Avoids Bus Contention) ---
    wire [15:0] data_in;
    assign data_in   = ENET_DATA;
    assign ENET_DATA = data_oe ? data_out : 16'hZZZZ; // High-Z when not driving

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Synchronous Reset: Initialize signals to inactive/safe levels
            state         <= S_RESET_HOLD;
            reset_cnt     <= 16'd0;
            cmd_latched   <= 2'b00;
            reg_latched   <= 8'd0;
            wdata_latched <= 16'd0;
            req_ready     <= 1'b0;
            rsp_rdata     <= 16'd0;
            rsp_valid     <= 1'b0;
            data_oe       <= 1'b0;
            data_out      <= 16'd0;
            ENET_CMD      <= 1'b0;
            ENET_CS_N     <= 1'b1; // Inactive
            ENET_RD_N     <= 1'b1; // Inactive
            ENET_WR_N     <= 1'b1; // Inactive
            ENET_RST_N    <= 1'b0; // Active Reset
        end else begin
            rsp_valid <= 1'b0; // Default status: no response pending

            case (state)
                // State 0: Hardware Reset assertion (Duration: ~1ms @ 50MHz)
                S_RESET_HOLD: begin
                    ENET_RST_N <= 1'b0;
                    if (reset_cnt == 16'd50000) begin
                        reset_cnt <= 16'd0;
                        state     <= S_RESET_REL;
                    end else begin
                        reset_cnt <= reset_cnt + 16'd1;
                    end
                end

                // State 1: Release Reset, allow internal chip configuration
                S_RESET_REL: begin
                    ENET_RST_N <= 1'b1;
                    req_ready  <= 1'b1;
                    state      <= S_IDLE;
                end

                // State 2: Monitoring Command Bus Interface
                S_IDLE: begin
                    ENET_CS_N <= 1'b1;
                    ENET_RD_N <= 1'b1;
                    ENET_WR_N <= 1'b1;
                    data_oe   <= 1'b0; // Bus Floats
                    req_ready <= 1'b1;

                    if (req_valid) begin
                        req_ready     <= 1'b0; // Lock interface
                        cmd_latched   <= req_cmd;
                        reg_latched   <= req_reg_addr;
                        wdata_latched <= req_wdata;

                        // Branching: DATA commands bypass Index Address cycle
                        if (req_cmd == CMD_DATA_W16 || req_cmd == CMD_DATA_R16)
                            state <= S_DATA_SETUP;
                        else
                            state <= S_IDX_SETUP;
                    end
                end

                // State 3: Register Address Setup (Index Port)
                S_IDX_SETUP: begin
                    ENET_CMD  <= 1'b0;              // Command = Index
                    ENET_CS_N <= 1'b0;              // Select Chip
                    data_oe   <= 1'b1;              // FPGA drives bus
                    data_out  <= {8'h00, reg_latched};
                    state     <= S_IDX_PULSE;
                end

                // State 4: Write Strobe for Index Latch
                S_IDX_PULSE: begin
                    ENET_WR_N <= 1'b0;              // Latching Address on rising edge
                    state     <= S_DATA_SETUP;
                end

                // State 5: Register Data Setup (Data Port)
                S_DATA_SETUP: begin
                    ENET_CS_N <= 1'b1;              // Strobe recovery time
                    ENET_WR_N <= 1'b1;
                    ENET_RD_N <= 1'b1;
                    data_oe   <= 1'b0;

                    ENET_CMD  <= 1'b1;              // Command = Data
                    ENET_CS_N <= 1'b0;

                    if (cmd_latched == CMD_REG_WRITE || cmd_latched == CMD_DATA_W16) begin
                        data_oe   <= 1'b1;          // Driver Enable for Write
                        data_out  <= wdata_latched;
                        state     <= S_DATA_WRITE;
                    end else begin
                        data_oe   <= 1'b0;          // Hi-Z for Read
                        state     <= S_DATA_READ;
                    end
                end

                // State 6: Write Strobe for Data Payload
                S_DATA_WRITE: begin
                    ENET_WR_N <= 1'b0;              // Trigger write strobe
                    state     <= S_DONE;
                end

                // State 7: Read Strobe and Data Sampling
                S_DATA_READ: begin
                    ENET_RD_N   <= 1'b0;            // Trigger read strobe
                    rsp_rdata   <= data_in;         // Sample bus (T_ACC must be met)
                    state       <= S_DONE;
                end

                // State 8: Cycle Completion and Strobe recovery
                S_DONE: begin
                    ENET_CS_N  <= 1'b1;
                    ENET_RD_N  <= 1'b1;
                    ENET_WR_N  <= 1'b1;
                    data_oe    <= 1'b0;             // Release bus
                    rsp_valid  <= 1'b1;             // Notify Core of completion
                    req_ready  <= 1'b1;             // Ready for next transaction
                    state      <= S_IDLE;
                end

                default: state <= S_RESET_HOLD;
            endcase
        end
    end
endmodule