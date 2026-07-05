// ============================================================================
// Phoenix-XM GPU — Warp Scheduler
// ============================================================================
// Round-robin warp scheduler with stall detection.
// Selects the next ready warp to feed into the pipeline.
//
// Key improvement over tiny-gpu:
//   tiny-gpu: No warp switching at all. Core stalls entirely on memory.
//   Phoenix:  8 warps, round-robin scheduling. When one warp stalls on memory,
//             the scheduler immediately issues from another ready warp. This
//             hides memory latency — the #1 GPU performance technique.
//
// Also includes per-warp state tracking (PC, active mask, stall reason).
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_warp_scheduler
    import phoenix_pkg::*;
#(
    parameter NUM_WARPS_P        = NUM_WARPS,
    parameter THREADS_PER_WARP_P = THREADS_PER_WARP
) (
    input  wire clk,
    input  wire rst_n,

    // --- Kernel Launch ---
    input  wire                            launch_valid,
    input  wire [$clog2(NUM_WARPS_P)-1:0]  launch_warp_id,
    input  wire [ADDR_WIDTH-1:0]           launch_pc,
    input  wire [THREADS_PER_WARP_P-1:0]   launch_mask,

    // --- Pipeline Feedback ---
    input  wire                            pipeline_ready,  // Pipeline can accept new instruction
    input  wire                            stall_warp_valid, // A warp needs to stall (memory wait)
    input  wire [$clog2(NUM_WARPS_P)-1:0]  stall_warp_id,
    input  wire                            unstall_warp_valid, // Memory response arrived
    input  wire [$clog2(NUM_WARPS_P)-1:0]  unstall_warp_id,

    // --- Warp Completion ---
    input  wire                            retire_warp_valid,
    input  wire [$clog2(NUM_WARPS_P)-1:0]  retire_warp_id,

    // --- Execution Feedback ---
    input  wire                            exec_valid,
    input  wire [$clog2(NUM_WARPS_P)-1:0]  exec_warp_id,
    input  wire [INSTR_WIDTH-1:0]          exec_instr,
    input  wire [2:0]                      exec_fu_sel,

    // --- PC Update (from branch/commit) ---
    input  wire                            pc_update_valid,
    input  wire [$clog2(NUM_WARPS_P)-1:0]  pc_update_warp_id,
    input  wire [ADDR_WIDTH-1:0]           pc_update_value,

    // --- Active Mask Update (from SPLIT/JOIN) ---
    input  wire                            mask_update_valid,
    input  wire [$clog2(NUM_WARPS_P)-1:0]  mask_update_warp_id,
    input  wire [THREADS_PER_WARP_P-1:0]   mask_update_value,

    // --- Scheduled Output ---
    output logic                            sched_valid,
    output logic [$clog2(NUM_WARPS_P)-1:0]  sched_warp_id,
    output logic [ADDR_WIDTH-1:0]           sched_pc,
    output logic [THREADS_PER_WARP_P-1:0]   sched_active_mask,

    // --- Status ---
    output logic                            all_warps_done
);

    // ========================================================================
    // Per-Warp State
    // ========================================================================
    warp_state_t                    warp_state [NUM_WARPS_P];
    logic [ADDR_WIDTH-1:0]          warp_pc    [NUM_WARPS_P];
    logic [THREADS_PER_WARP_P-1:0]  warp_mask  [NUM_WARPS_P];

    // Round-robin pointer
    logic [$clog2(NUM_WARPS_P)-1:0] rr_ptr;

    // ========================================================================
    // Find Next Ready Warp (round-robin search)
    // ========================================================================
    logic                           found_ready;
    logic [$clog2(NUM_WARPS_P)-1:0] next_warp;

    always_comb begin
        found_ready = 1'b0;
        next_warp   = rr_ptr;

        for (int i = 0; i < NUM_WARPS_P; i++) begin
            if (!found_ready && warp_state[(rr_ptr + i[$clog2(NUM_WARPS_P)-1:0]) % NUM_WARPS_P] == WARP_READY) begin
                found_ready = 1'b1;
                next_warp   = (rr_ptr + i[$clog2(NUM_WARPS_P)-1:0]) % NUM_WARPS_P;
            end
        end
    end

    // ========================================================================
    // Scheduling Output
    // ========================================================================
    always_comb begin
        sched_valid       = found_ready && pipeline_ready;
        sched_warp_id     = next_warp;
        sched_pc          = warp_pc[next_warp];
        sched_active_mask = warp_mask[next_warp];
    end

    // ========================================================================
    // Check if All Warps Are Done
    // ========================================================================
    always_comb begin
        all_warps_done = 1'b1;
        for (int i = 0; i < NUM_WARPS_P; i++) begin
            if (warp_state[i] != WARP_DONE && warp_state[i] != CORE_IDLE) begin
                all_warps_done = 1'b0;
            end
        end
    end

    // ========================================================================
    // State Machine
    // ========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr <= '0;
            for (int i = 0; i < NUM_WARPS_P; i++) begin
                warp_state[i] <= WARP_DONE;  // Start as "not active"
                warp_pc[i]    <= '0;
                warp_mask[i]  <= '0;
            end
        end else begin
            // --- Launch: activate a warp ---
            if (launch_valid) begin
                warp_state[launch_warp_id] <= WARP_READY;
                warp_pc[launch_warp_id]    <= launch_pc;
                warp_mask[launch_warp_id]  <= launch_mask;
            end

            // --- Schedule: mark issued warp as FETCHING and advance PC ---
            if (sched_valid) begin
                warp_state[next_warp] <= WARP_FETCHING;
                warp_pc[next_warp]    <= warp_pc[next_warp] + 4;  // Next instruction (32-bit)
                rr_ptr <= (next_warp + 1) % NUM_WARPS_P;
            end

            // --- Stall: memory or barrier ---
            if (stall_warp_valid) begin
                warp_state[stall_warp_id] <= WARP_STALLED;
            end

            // --- Unstall: memory response arrived ---
            if (unstall_warp_valid) begin
                if (warp_state[unstall_warp_id] == WARP_STALLED) begin
                    warp_state[unstall_warp_id] <= WARP_READY;
                end
            end

            // --- PC Update: branch taken ---
            if (pc_update_valid) begin
                warp_pc[pc_update_warp_id] <= pc_update_value;
                // After a branch, the warp becomes ready again
                if (warp_state[pc_update_warp_id] == WARP_FETCHING ||
                    warp_state[pc_update_warp_id] == WARP_ISSUED) begin
                    warp_state[pc_update_warp_id] <= WARP_READY;
                end
            end

            // --- Mask Update: SPLIT/JOIN ---
            if (mask_update_valid) begin
                warp_mask[mask_update_warp_id] <= mask_update_value;
            end

            // --- Retire: warp finished ---
            if (retire_warp_valid) begin
                warp_state[retire_warp_id] <= WARP_DONE;
            end

            if (exec_valid && (exec_fu_sel == FU_SFU) && (exec_instr[6:0] == OP_GPU) && (exec_instr[14:12] == 3'b111)) begin
                warp_state[exec_warp_id] <= WARP_DONE;
            end else if (exec_valid && warp_state[exec_warp_id] != WARP_STALLED) begin
                warp_state[exec_warp_id] <= WARP_READY; // Ready for next instruction
            end

        end
    end

endmodule
