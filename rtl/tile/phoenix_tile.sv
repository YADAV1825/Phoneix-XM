// ============================================================================
// Phoenix-XM GPU — Compute Tile
// ============================================================================
// A Tile is the fundamental "chiplet" of Phoenix-XM.
// Each tile contains:
//   - N SMs (default 4)
//   - A block dispatcher
//   - Instruction memory (per-tile, shared by all SMs)
//   - Data memory (per-tile, shared by all SMs)
//
// In the full Phoenix-XM vision, tiles are connected by an optical fabric.
// In this implementation, tiles connect through a parameterized-latency bus.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_tile
    import phoenix_pkg::*;
#(
    parameter TILE_ID          = 0,
    parameter NUM_SMS          = SMS_PER_TILE,
    parameter IMEM_SIZE_WORDS  = 256,
    parameter DMEM_SIZE_WORDS  = 1024
) (
    input  wire clk,
    input  wire rst_n,

    // --- Kernel Launch Interface (from global scheduler or host) ---
    input  wire                            kernel_valid,
    output logic                           kernel_ready,
    input  wire [ADDR_WIDTH-1:0]           kernel_pc,
    input  wire [DATA_WIDTH-1:0]           kernel_num_blocks,
    input  wire [$clog2(THREADS_PER_WARP):0] kernel_threads_per_block,

    // --- Kernel Completion ---
    output logic                           kernel_done,

    // --- Host Memory Load Interface ---
    input  wire                            host_imem_wr_en,
    input  wire [$clog2(IMEM_SIZE_WORDS)-1:0] host_imem_wr_addr,
    input  wire [INSTR_WIDTH-1:0]          host_imem_wr_data,

    input  wire                            host_dmem_wr_en,
    input  wire [$clog2(DMEM_SIZE_WORDS)-1:0] host_dmem_wr_addr,
    input  wire [DATA_WIDTH-1:0]           host_dmem_wr_data,

    // --- Host Memory Read Interface (for reading results) ---
    input  wire                            host_dmem_rd_en,
    input  wire [$clog2(DMEM_SIZE_WORDS)-1:0] host_dmem_rd_addr,
    output logic [DATA_WIDTH-1:0]          host_dmem_rd_data
);

    // ========================================================================
    // Instruction Memory (shared by all SMs in this tile)
    // ========================================================================
    logic [INSTR_WIDTH-1:0] imem [IMEM_SIZE_WORDS];

    // SM instruction memory interfaces (muxed)
    logic [NUM_SMS-1:0]             sm_imem_req_valid;
    logic [ADDR_WIDTH-1:0]          sm_imem_req_addr  [NUM_SMS];
    logic [NUM_SMS-1:0]             sm_imem_req_ready;
    logic [NUM_SMS-1:0]             sm_imem_rsp_valid;
    logic [INSTR_WIDTH-1:0]         sm_imem_rsp_data  [NUM_SMS];

    // Host write to instruction memory
    always_ff @(posedge clk) begin
        if (host_imem_wr_en) begin
            imem[host_imem_wr_addr] <= host_imem_wr_data;
        end
    end

    // Simple round-robin instruction memory arbiter
    // (In a real design, this would be an I-cache. For simulation, direct SRAM.)
    logic [$clog2(IMEM_SIZE_WORDS)-1:0] imem_word_addr [NUM_SMS];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_SMS; i++) begin
                sm_imem_req_ready[i] <= 1'b0;
                sm_imem_rsp_valid[i] <= 1'b0;
                sm_imem_rsp_data[i]  <= '0;
            end
        end else begin
            for (int i = 0; i < NUM_SMS; i++) begin
                sm_imem_rsp_valid[i] <= 1'b0;

                if (sm_imem_req_valid[i]) begin
                    imem_word_addr[i] = sm_imem_req_addr[i][$clog2(IMEM_SIZE_WORDS)+1:2]; // Byte to word
                    sm_imem_req_ready[i] <= 1'b1;
                    sm_imem_rsp_valid[i] <= 1'b1;
                    sm_imem_rsp_data[i]  <= imem[imem_word_addr[i]];
                end else begin
                    sm_imem_req_ready[i] <= 1'b0;
                end
            end
        end
    end

    // ========================================================================
    // Data Memory (shared by all SMs in this tile)
    // ========================================================================
    logic [DATA_WIDTH-1:0] dmem [DMEM_SIZE_WORDS];

    // SM data memory interfaces
    logic [NUM_SMS-1:0]             sm_dmem_req_valid;
    logic [NUM_SMS-1:0]             sm_dmem_req_is_write;
    logic [ADDR_WIDTH-1:0]          sm_dmem_req_addr  [NUM_SMS];
    logic [DATA_WIDTH-1:0]          sm_dmem_req_wdata [NUM_SMS];
    logic [3:0]                     sm_dmem_req_byte_en [NUM_SMS];
    logic [NUM_SMS-1:0]             sm_dmem_req_ready;
    logic [NUM_SMS-1:0]             sm_dmem_rsp_valid;
    logic [DATA_WIDTH-1:0]          sm_dmem_rsp_rdata [NUM_SMS];

    // Host write/read to data memory
    always_ff @(posedge clk) begin
        if (host_dmem_wr_en) begin
            dmem[host_dmem_wr_addr] <= host_dmem_wr_data;
        end
    end

    always_comb begin
        host_dmem_rd_data = host_dmem_rd_en ? dmem[host_dmem_rd_addr] : '0;
    end

    // Simple round-robin data memory arbiter
    logic [$clog2(DMEM_SIZE_WORDS)-1:0] dmem_word_addr [NUM_SMS];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_SMS; i++) begin
                sm_dmem_req_ready[i] <= 1'b0;
                sm_dmem_rsp_valid[i] <= 1'b0;
                sm_dmem_rsp_rdata[i] <= '0;
            end
        end else begin
            for (int i = 0; i < NUM_SMS; i++) begin
                sm_dmem_rsp_valid[i] <= 1'b0;

                if (sm_dmem_req_valid[i]) begin
                    dmem_word_addr[i] = sm_dmem_req_addr[i][$clog2(DMEM_SIZE_WORDS)+1:2];
                    sm_dmem_req_ready[i] <= 1'b1;

                    if (sm_dmem_req_is_write[i]) begin
                        dmem[dmem_word_addr[i]] <= sm_dmem_req_wdata[i];
                    end else begin
                        sm_dmem_rsp_valid[i] <= 1'b1;
                        sm_dmem_rsp_rdata[i] <= dmem[dmem_word_addr[i]];
                    end
                end else begin
                    sm_dmem_req_ready[i] <= 1'b0;
                end
            end
        end
    end

    // ========================================================================
    // Dispatcher
    // ========================================================================
    logic [NUM_SMS-1:0]  sm_dispatch_valid;
    logic [NUM_SMS-1:0]  sm_dispatch_ready;
    logic [ADDR_WIDTH-1:0] sm_dispatch_pc;
    logic [DATA_WIDTH-1:0] sm_dispatch_block_id;
    logic [$clog2(THREADS_PER_WARP):0] sm_dispatch_thread_count;
    logic [NUM_SMS-1:0]  sm_block_done;

    phoenix_dispatcher #(
        .NUM_SMS(NUM_SMS)
    ) dispatcher (
        .clk(clk), .rst_n(rst_n),
        .kernel_valid(kernel_valid),
        .kernel_ready(kernel_ready),
        .kernel_pc(kernel_pc),
        .kernel_num_blocks(kernel_num_blocks),
        .kernel_threads_per_block(kernel_threads_per_block),
        .sm_dispatch_valid(sm_dispatch_valid),
        .sm_dispatch_ready(sm_dispatch_ready),
        .sm_dispatch_pc(sm_dispatch_pc),
        .sm_dispatch_block_id(sm_dispatch_block_id),
        .sm_dispatch_thread_count(sm_dispatch_thread_count),
        .sm_block_done(sm_block_done),
        .kernel_done(kernel_done)
    );

    // ========================================================================
    // SM Instances
    // ========================================================================
    genvar g;
    generate
        for (g = 0; g < NUM_SMS; g = g + 1) begin : sms
            logic sm_block_done_o;
            logic [DATA_WIDTH-1:0] sm_block_done_id;

            phoenix_sm #(
                .SM_ID(TILE_ID * NUM_SMS + g)
            ) sm_inst (
                .clk(clk), .rst_n(rst_n),

                // Dispatch
                .dispatch_valid(sm_dispatch_valid[g]),
                .dispatch_ready(sm_dispatch_ready[g]),
                .dispatch_pc(sm_dispatch_pc),
                .dispatch_block_id(sm_dispatch_block_id),
                .dispatch_thread_count(sm_dispatch_thread_count),

                // Completion
                .block_done(sm_block_done_o),
                .block_done_id(sm_block_done_id),

                // Instruction Memory
                .imem_req_valid(sm_imem_req_valid[g]),
                .imem_req_addr(sm_imem_req_addr[g]),
                .imem_req_ready(sm_imem_req_ready[g]),
                .imem_rsp_valid(sm_imem_rsp_valid[g]),
                .imem_rsp_data(sm_imem_rsp_data[g]),

                // Data Memory
                .dmem_req_valid(sm_dmem_req_valid[g]),
                .dmem_req_is_write(sm_dmem_req_is_write[g]),
                .dmem_req_addr(sm_dmem_req_addr[g]),
                .dmem_req_wdata(sm_dmem_req_wdata[g]),
                .dmem_req_byte_en(sm_dmem_req_byte_en[g]),
                .dmem_req_ready(sm_dmem_req_ready[g]),
                .dmem_rsp_valid(sm_dmem_rsp_valid[g]),
                .dmem_rsp_rdata(sm_dmem_rsp_rdata[g])
            );

            assign sm_block_done[g] = sm_block_done_o;
        end
    endgenerate

endmodule
