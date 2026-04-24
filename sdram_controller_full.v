// sdram_controller_full.v
// Simplified full SDRAM controller for DE2 (MT48LC4M16A2)
// Supports initialization, auto-refresh, single-word read/write.
// Host interface in 50 MHz domain, 16-bit data path.

module sdram_controller_full (
    input  wire        clk50,
    input  wire        reset_n,

    // Host command interface
    input  wire        write_req,
    input  wire        read_req,
    input  wire [22:0] addr,       // byte address with 16-bit data (word address)
    input  wire [15:0] write_data,
    output reg  [15:0] read_data,
    output reg         busy,
    output reg         ready,

    // SDRAM physical interface (DE2 pin-out)
    output reg  [12:0] sdram_addr,
    output reg  [1:0]  sdram_ba,
    output reg         sdram_cs_n,
    output reg         sdram_ras_n,
    output reg         sdram_cas_n,
    output reg         sdram_we_n,
    inout  wire [15:0] sdram_dq,
    output reg  [1:0]  sdram_dqm,
    output reg         sdram_cke
);

    // SDRAM command encodings
    localparam CMD_NOP       = 4'b0111;
    localparam CMD_ACTIVE    = 4'b0011;
    localparam CMD_READ      = 4'b0101;
    localparam CMD_WRITE     = 4'b0100;
    localparam CMD_PRECHARGE = 4'b0010;
    localparam CMD_REFRESH   = 4'b0001;
    localparam CMD_LOAD_MODE = 4'b0000;

    // Operation state
    localparam ST_POWERUP   = 4'd0;
    localparam ST_PRECH     = 4'd1;
    localparam ST_ARFRESH   = 4'd2;
    localparam ST_LOAD_MODE = 4'd3;
    localparam ST_IDLE      = 4'd4;
    localparam ST_ACTIVATE  = 4'd5;
    localparam ST_COL_CMD   = 4'd6;
    localparam ST_CAS_WAIT  = 4'd7;
    localparam ST_DATA      = 4'd8;
    localparam ST_REFRESH   = 4'd9;

    reg [3:0]  state;
    reg [12:0] row_addr;
    reg [8:0]  col_addr;
    reg [1:0]  bank_addr;
    reg        cmd_write;
    reg [15:0] dq_out;
    reg        dq_oe;

    assign sdram_dq = dq_oe ? dq_out : 16'bz;

    // Initialization counters
    reg [15:0] init_ctr;   // for 200us + refresh interval
    reg [2:0]  arf_count;
    reg [12:0] refresh_ctr;

    // CAS and row timings at 50MHz
    localparam tRCD = 2; // RAS to CAS delay 2 cycles
    localparam tRP  = 2; // row precharge 2 cycles
    localparam tRFC = 7; // refresh cycle 7 cycles
    localparam tCAS = 3; // CAS latency 3 cycles

    reg [3:0] timing_ctr;
    reg [15:0] data_reg;

    always @(posedge clk50 or negedge reset_n) begin
        if (!reset_n) begin
            state <= ST_POWERUP;
            sdram_cs_n <= 1;
            sdram_ras_n <= 1;
            sdram_cas_n <= 1;
            sdram_we_n  <= 1;
            sdram_cke   <= 0;
            sdram_addr <= 13'd0;
            sdram_ba <= 2'd0;
            sdram_dqm <= 2'b00;
            busy <= 1;
            ready <= 0;
            init_ctr <= 0;
            arf_count <= 0;
            refresh_ctr <= 0;
            timing_ctr <= 0;
            row_addr <= 0;
            col_addr <= 0;
            bank_addr <= 0;
            cmd_write <= 0;
            dq_out <= 16'd0;
            dq_oe <= 0;
            read_data <= 0;
            data_reg <= 0;
        end else begin
            // refresh interval counter
            if (state == ST_IDLE && !busy) begin
                if (refresh_ctr >= 13'd2999) begin
                    state <= ST_REFRESH;
                    refresh_ctr <= 0;
                end else begin
                    refresh_ctr <= refresh_ctr + 1;
                end
            end else if (state != ST_IDLE) begin
                refresh_ctr <= refresh_ctr;
            end

            case (state)
                ST_POWERUP: begin
                    sdram_cke <= 1;
                    // wait at least 200us (~10000 cycles 50MHz) for power-up
                    if (init_ctr < 16'd10000) begin
                        init_ctr <= init_ctr + 1;
                        sdram_cs_n <= 1; sdram_ras_n <= 1; sdram_cas_n <= 1; sdram_we_n <= 1;
                        busy <= 1; ready <= 0;
                    end else begin
                        // issue PRECHARGE ALL
                        sdram_cs_n <= 0; sdram_ras_n <= 0; sdram_cas_n <= 1; sdram_we_n <= 0;
                        sdram_addr[10] <= 1'b1; // all banks
                        init_ctr <= 0;
                        timing_ctr <= 0;
                        state <= ST_PRECH;
                    end
                end
                ST_PRECH: begin
                    // wait tRP cycles
                    if (timing_ctr < tRP-1) begin
                        timing_ctr <= timing_ctr + 1;
                        sdram_cs_n <= 1; sdram_ras_n <= 1; sdram_cas_n <= 1; sdram_we_n <= 1;
                    end else begin
                        timing_ctr <= 0;
                        state <= ST_ARFRESH;
                        arf_count <= 0;
                    end
                    busy <= 1; ready <= 0;
                end
                ST_ARFRESH: begin
                    if (arf_count < 3'd8) begin
                        if (timing_ctr == 0) begin
                            sdram_cs_n <= 0; sdram_ras_n <= 0; sdram_cas_n <= 0; sdram_we_n <= 1;
                            timing_ctr <= timing_ctr + 1;
                        end else if (timing_ctr < tRFC) begin
                            timing_ctr <= timing_ctr + 1;
                            sdram_cs_n <= 1; sdram_ras_n <= 1; sdram_cas_n <= 1; sdram_we_n <= 1;
                        end else begin
                            timing_ctr <= 0;
                            arf_count <= arf_count + 1;
                        end
                        busy <= 1; ready <= 0;
                    end else begin
                        state <= ST_LOAD_MODE;
                        timing_ctr <= 0;
                        busy <= 1; ready <= 0;
                    end
                end
                ST_LOAD_MODE: begin
                    // Load mode register: burst length=1, CAS latency=3, sequential
                    if (timing_ctr == 0) begin
                        sdram_cs_n <= 0; sdram_ras_n <= 0; sdram_cas_n <= 0; sdram_we_n <= 0;
                        sdram_addr <= 13'b0000_0_011_0_0_0_0_0; // A10=0, simple mode, CL=3
                        sdram_ba <= 2'b00;
                        timing_ctr <= timing_ctr + 1;
                    end else begin
                        sdram_cs_n <= 1; sdram_ras_n <= 1; sdram_cas_n <= 1; sdram_we_n <= 1;
                        state <= ST_IDLE;
                        ready <= 1;
                        busy <= 0;
                    end
                end
                ST_IDLE: begin
                    sdram_cs_n <= 1; sdram_ras_n <= 1; sdram_cas_n <= 1; sdram_we_n <= 1;
                    dq_oe <= 0;
                    busy <= 0;
                    ready <= 1;
                    // host requests and refresh arbitration
                    if (write_req || read_req) begin
                        // capture row/col/bank
                        row_addr <= addr[20:8];
                        col_addr <= addr[7:0];
                        bank_addr <= addr[22:21];
                        cmd_write <= write_req;
                        data_reg <= write_data;
                        state <= ST_ACTIVATE;
                        busy <= 1; ready <= 0;
                        timing_ctr <= 0;
                    end else if (state == ST_REFRESH) begin
                        // this path not used
                    end
                end
                ST_ACTIVATE: begin
                    // issue ACT
                    if (timing_ctr == 0) begin
                        sdram_cs_n <= 0; sdram_ras_n <= 0; sdram_cas_n <= 1; sdram_we_n <= 1;
                        sdram_ba <= bank_addr;
                        sdram_addr <= row_addr;
                        timing_ctr <= 1;
                    end else if (timing_ctr < tRCD) begin
                        sdram_cs_n <= 1; sdram_ras_n <= 1; sdram_cas_n <= 1; sdram_we_n <= 1;
                        timing_ctr <= timing_ctr + 1;
                    end else begin
                        timing_ctr <= 0;
                        state <= ST_COL_CMD;
                    end
                    busy <= 1; ready <= 0;
                end
                ST_COL_CMD: begin
                    sdram_cs_n <= 0;
                    sdram_ras_n <= 1;
                    sdram_cas_n <= cmd_write ? 0 : 0;
                    sdram_we_n  <= cmd_write ? 0 : 1;
                    sdram_ba <= bank_addr;
                    sdram_addr <= {5'b0, col_addr}; // A10 auto-precharge off
                    if (cmd_write) begin
                        dq_out <= data_reg;
                        dq_oe <= 1;
                        state <= ST_DATA;
                    end else begin
                        dq_oe <= 0;
                        state <= ST_CAS_WAIT;
                    end
                    timing_ctr <= 0;
                    busy <= 1; ready <= 0;
                end
                ST_CAS_WAIT: begin
                    sdram_cs_n <= 1; sdram_ras_n <= 1; sdram_cas_n <= 1; sdram_we_n <= 1;
                    if (timing_ctr < tCAS-1) begin
                        timing_ctr <= timing_ctr + 1;
                        busy <= 1; ready <= 0;
                    end else begin
                        timing_ctr <= 0;
                        state <= ST_DATA;
                        busy <= 1; ready <= 0;
                    end
                end
                ST_DATA: begin
                    if (cmd_write) begin
                        // write already in data cycles; command should be valid at least 1 cycle
                        dq_oe <= 0;
                        state <= ST_IDLE;
                    end else begin
                        read_data <= sdram_dq;
                        state <= ST_IDLE;
                    end
                    busy <= 0;
                    ready <= 1;
                end
                ST_REFRESH: begin
                    // issue auto-refresh command
                    sdram_cs_n <= 0; sdram_ras_n <= 0; sdram_cas_n <= 0; sdram_we_n <= 1;
                    timing_ctr <= timing_ctr + 1;
                    busy <= 1; ready <= 0;
                    if (timing_ctr >= tRFC-1) begin
                        timing_ctr <= 0;
                        state <= ST_IDLE;
                        refresh_ctr <= 0;
                        busy <= 0;
                        ready <= 1;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
