// ============================================================================
// Phoenix-XM GPU — Block Dispatcher
// ============================================================================
// Dispatches thread blocks (CTAs) to available SMs within a tile.
// Tracks which SMs are busy and which are free.
//
// Key improvement over tiny-gpu:
//   tiny-gpu: Simple counter dispatches blocks round-robin with no awareness
//             of SM occupancy or resource limits.
//   Phoenix:  Occupancy-aware dispatch. Waits for an SM to complete before
//             assigning it a new block. Supports variable block sizes.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_dispatcher
    import phoenix_pkg::*;
#(
    parameter NUM_SMS = SMS_PER_TILE
) (
    input  wire clk,
    input  wire rst_n,

    // --- Kernel Launch Interface ---
    input  wire                            kernel_valid,
    output logic                           kernel_ready,
    input  wire [ADDR_WIDTH-1:0]           kernel_pc,          // Program entry
    input  wire [DATA_WIDTH-1:0]           kernel_num_blocks,  // Total blocks
    input  wire [$clog2(THREADS_PER_WARP):0] kernel_threads_per_block,

    // --- SM Dispatch Interface ---
    output logic [NUM_SMS-1:0]             sm_dispatch_valid,
    input  wire  [NUM_SMS-1:0]             sm_dispatch_ready,
    output logic [ADDR_WIDTH-1:0]          sm_dispatch_pc,
    output logic [DATA_WIDTH-1:0]          sm_dispatch_block_id,
    output logic [$clog2(THREADS_PER_WARP):0] sm_dispatch_thread_count,

    // --- SM Completion Interface ---
    input  wire  [NUM_SMS-1:0]             sm_block_done,

    // --- Kernel Completion ---
    output logic                           kernel_done
);

    // ========================================================================
    // State
    // ========================================================================
    typedef enum logic [1:0] {
        DISP_IDLE      = 2'd0,
        DISP_DISPATCH  = 2'd1,
        DISP_WAIT_ALL  = 2'd2,
        DISP_DONE      = 2'd3
    } disp_state_t;

    disp_state_t state;

    logic [DATA_WIDTH-1:0]  blocks_dispatched;
    logic [DATA_WIDTH-1:0]  blocks_completed;
    logic [DATA_WIDTH-1:0]  total_blocks;
    logic [ADDR_WIDTH-1:0]  program_pc;
    logic [$clog2(THREADS_PER_WARP):0] threads_per_block;

    // SM busy tracking
    logic [NUM_SMS-1:0] sm_busy;

    // ========================================================================
    // Find free SM
    // ========================================================================
    logic                            found_free_sm;
    logic [$clog2(NUM_SMS)-1:0]      free_sm_id;

    always_comb begin
        found_free_sm = 1'b0;
        free_sm_id    = '0;
        for (int i = 0; i < NUM_SMS; i++) begin
            if (!found_free_sm && !sm_busy[i] && sm_dispatch_ready[i]) begin
                found_free_sm = 1'b1;
                free_sm_id    = i[$clog2(NUM_SMS)-1:0];
            end
        end
    end

    // ========================================================================
    // Dispatch Logic
    // ========================================================================
    assign kernel_ready = (state == DISP_IDLE);
    assign sm_dispatch_pc = program_pc;
    assign sm_dispatch_thread_count = threads_per_block;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= DISP_IDLE;
            blocks_dispatched <= '0;
            blocks_completed  <= '0;
            total_blocks      <= '0;
            program_pc        <= '0;
            threads_per_block <= '0;
            sm_busy           <= '0;
            sm_dispatch_valid <= '0;
            sm_dispatch_block_id <= '0;
            kernel_done       <= 1'b0;
        end else begin
            kernel_done       <= 1'b0;
            sm_dispatch_valid <= '0;

            // Track SM completions
            for (int i = 0; i < NUM_SMS; i++) begin
                if (sm_block_done[i]) begin
                    sm_busy[i] <= 1'b0;
                    blocks_completed <= blocks_completed + 1;
                end
            end

            case (state)
                DISP_IDLE: begin
                    if (kernel_valid) begin
                        total_blocks      <= kernel_num_blocks;
                        program_pc        <= kernel_pc;
                        threads_per_block <= kernel_threads_per_block;
                        blocks_dispatched <= '0;
                        blocks_completed  <= '0;
                        state             <= DISP_DISPATCH;
                    end
                end

                DISP_DISPATCH: begin
                    if (blocks_dispatched < total_blocks) begin
                        if (found_free_sm) begin
                            // Dispatch block to free SM
                            sm_dispatch_valid[free_sm_id] <= 1'b1;
                            sm_dispatch_block_id          <= blocks_dispatched;
                            sm_busy[free_sm_id]           <= 1'b1;
                            blocks_dispatched             <= blocks_dispatched + 1;
                        end
                    end else begin
                        // All blocks dispatched, wait for completion
                        state <= DISP_WAIT_ALL;
                    end
                end

                DISP_WAIT_ALL: begin
                    if (blocks_completed >= total_blocks) begin
                        kernel_done <= 1'b1;
                        state       <= DISP_DONE;
                    end
                end

                DISP_DONE: begin
                    state <= DISP_IDLE;
                end
            endcase
        end
    end

endmodule
