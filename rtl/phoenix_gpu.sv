// ============================================================================
// Phoenix-XM GPU — Top-Level Module
// ============================================================================
// The "Virtual Monolithic GPU" — instantiates N tiles and presents them
// as a single unified accelerator to the host.
//
// In this prototype:
//   - 2 tiles × 4 SMs = 8 SMs total
//   - Single address space across tiles
//   - Host writes program/data, triggers kernel, reads results
//
// Physical analogy:
//   Each tile = one chiplet on the accelerator board
//   The host interface = PCIe-like connection to CPU
//   The inter-tile connection = the "optical fabric" (modeled as wires)
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_gpu
    import phoenix_pkg::*;
#(
    parameter NUM_TILES_P      = NUM_TILES,
    parameter IMEM_SIZE_WORDS  = 256,
    parameter DMEM_SIZE_WORDS  = 1024
) (
    input  wire clk,
    input  wire rst_n,

    // --- Host Interface ---
    input  wire                            host_kernel_valid,
    output logic                           host_kernel_ready,
    input  wire [ADDR_WIDTH-1:0]           host_kernel_pc,
    input  wire [DATA_WIDTH-1:0]           host_kernel_num_blocks,
    input  wire [$clog2(THREADS_PER_WARP):0] host_kernel_threads_per_block,
    input  wire [$clog2(NUM_TILES_P)-1:0]  host_kernel_tile_id,  // Which tile to target

    output logic                           host_kernel_done,

    // --- Host Memory Write (program loading) ---
    input  wire                            host_imem_wr_en,
    input  wire [$clog2(NUM_TILES_P)-1:0]  host_imem_tile_id,
    input  wire [$clog2(IMEM_SIZE_WORDS)-1:0] host_imem_wr_addr,
    input  wire [INSTR_WIDTH-1:0]          host_imem_wr_data,

    input  wire                            host_dmem_wr_en,
    input  wire [$clog2(NUM_TILES_P)-1:0]  host_dmem_tile_id,
    input  wire [$clog2(DMEM_SIZE_WORDS)-1:0] host_dmem_wr_addr,
    input  wire [DATA_WIDTH-1:0]           host_dmem_wr_data,

    // --- Host Memory Read (result reading) ---
    input  wire                            host_dmem_rd_en,
    input  wire [$clog2(NUM_TILES_P)-1:0]  host_dmem_rd_tile_id,
    input  wire [$clog2(DMEM_SIZE_WORDS)-1:0] host_dmem_rd_addr,
    output logic [DATA_WIDTH-1:0]          host_dmem_rd_data
);

    // ========================================================================
    // Per-Tile Signals
    // ========================================================================
    logic [NUM_TILES_P-1:0]         tile_kernel_valid;
    logic [NUM_TILES_P-1:0]         tile_kernel_ready;
    logic [NUM_TILES_P-1:0]         tile_kernel_done;

    logic [NUM_TILES_P-1:0]         tile_imem_wr_en;
    logic [NUM_TILES_P-1:0]         tile_dmem_wr_en;
    logic [NUM_TILES_P-1:0]         tile_dmem_rd_en;
    logic [DATA_WIDTH-1:0]          tile_dmem_rd_data [NUM_TILES_P];

    // ========================================================================
    // Route Host Signals to Correct Tile
    // ========================================================================
    always_comb begin
        // Default: no tile selected
        tile_kernel_valid = '0;
        tile_imem_wr_en   = '0;
        tile_dmem_wr_en   = '0;
        tile_dmem_rd_en   = '0;
        host_dmem_rd_data = '0;

        // Kernel launch
        tile_kernel_valid[host_kernel_tile_id] = host_kernel_valid;
        host_kernel_ready = tile_kernel_ready[host_kernel_tile_id];

        // Instruction memory write
        tile_imem_wr_en[host_imem_tile_id] = host_imem_wr_en;

        // Data memory write
        tile_dmem_wr_en[host_dmem_tile_id] = host_dmem_wr_en;

        // Data memory read
        tile_dmem_rd_en[host_dmem_rd_tile_id] = host_dmem_rd_en;
        host_dmem_rd_data = tile_dmem_rd_data[host_dmem_rd_tile_id];
    end

    // ========================================================================
    // Kernel completion (done when target tile completes)
    // ========================================================================
    always_comb begin
        host_kernel_done = |tile_kernel_done;
    end

    // ========================================================================
    // Tile Instances
    // ========================================================================
    genvar g;
    generate
        for (g = 0; g < NUM_TILES_P; g = g + 1) begin : tiles
            phoenix_tile #(
                .TILE_ID(g),
                .NUM_SMS(SMS_PER_TILE),
                .IMEM_SIZE_WORDS(IMEM_SIZE_WORDS),
                .DMEM_SIZE_WORDS(DMEM_SIZE_WORDS)
            ) tile_inst (
                .clk(clk), .rst_n(rst_n),

                // Kernel
                .kernel_valid(tile_kernel_valid[g]),
                .kernel_ready(tile_kernel_ready[g]),
                .kernel_pc(host_kernel_pc),
                .kernel_num_blocks(host_kernel_num_blocks),
                .kernel_threads_per_block(host_kernel_threads_per_block),
                .kernel_done(tile_kernel_done[g]),

                // Instruction Memory
                .host_imem_wr_en(tile_imem_wr_en[g]),
                .host_imem_wr_addr(host_imem_wr_addr),
                .host_imem_wr_data(host_imem_wr_data),

                // Data Memory
                .host_dmem_wr_en(tile_dmem_wr_en[g]),
                .host_dmem_wr_addr(host_dmem_wr_addr),
                .host_dmem_wr_data(host_dmem_wr_data),

                .host_dmem_rd_en(tile_dmem_rd_en[g]),
                .host_dmem_rd_addr(host_dmem_rd_addr),
                .host_dmem_rd_data(tile_dmem_rd_data[g])
            );
        end
    endgenerate

endmodule
