// ============================================================================
// Phoenix-XM GPU — Global Scheduler
// ============================================================================
// Responsible for Locality-First Scheduling across tiles.
// Receives full kernel launch parameters and decides which tile(s)
// get which blocks, based on data location.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_global_scheduler
    import phoenix_pkg::*;
#(
    parameter NUM_TILES_P = NUM_TILES
) (
    input  wire clk,
    input  wire rst_n,

    // --- Host Interface ---
    input  wire                            host_kernel_valid,
    input  wire [ADDR_WIDTH-1:0]           host_kernel_pc,
    input  wire [DATA_WIDTH-1:0]           host_kernel_num_blocks,
    input  wire [$clog2(THREADS_PER_WARP):0] host_kernel_threads_per_block,
    output logic                           host_kernel_ready,

    // --- Tile Interfaces ---
    output logic [NUM_TILES_P-1:0]         tile_kernel_valid,
    input  wire  [NUM_TILES_P-1:0]         tile_kernel_ready,
    output logic [ADDR_WIDTH-1:0]          tile_kernel_pc [NUM_TILES_P],
    output logic [DATA_WIDTH-1:0]          tile_kernel_num_blocks [NUM_TILES_P],
    output logic [$clog2(THREADS_PER_WARP):0] tile_kernel_threads_per_block [NUM_TILES_P]
);

    // Placeholder: pass-through to tile 0 for now
    assign host_kernel_ready = tile_kernel_ready[0];

    always_comb begin
        for (int i = 0; i < NUM_TILES_P; i++) begin
            tile_kernel_valid[i] = 1'b0;
            tile_kernel_pc[i] = '0;
            tile_kernel_num_blocks[i] = '0;
            tile_kernel_threads_per_block[i] = '0;
        end

        tile_kernel_valid[0] = host_kernel_valid;
        tile_kernel_pc[0] = host_kernel_pc;
        tile_kernel_num_blocks[0] = host_kernel_num_blocks;
        tile_kernel_threads_per_block[0] = host_kernel_threads_per_block;
    end

endmodule
