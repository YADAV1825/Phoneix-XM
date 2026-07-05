// ============================================================================
// Phoenix-XM GPU — Instruction Fetch Unit
// ============================================================================
// Fetches instructions from I-cache or instruction memory.
// Receives PC from warp scheduler, issues memory read, buffers result.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_fetch
    import phoenix_pkg::*;
(
    input  wire clk,
    input  wire rst_n,

    // --- From Warp Scheduler ---
    input  wire                            sched_valid,
    input  wire [$clog2(NUM_WARPS)-1:0]    sched_warp_id,
    input  wire [ADDR_WIDTH-1:0]           sched_pc,
    input  wire [THREADS_PER_WARP-1:0]     sched_active_mask,

    // --- Instruction Memory Interface ---
    output logic                           imem_req_valid,
    output logic [ADDR_WIDTH-1:0]          imem_req_addr,
    input  wire                            imem_req_ready,
    input  wire                            imem_rsp_valid,
    input  wire [INSTR_WIDTH-1:0]          imem_rsp_data,

    // --- To Decode Stage ---
    output logic                           fetch_valid,
    output logic [INSTR_WIDTH-1:0]         fetch_instr,
    output logic [$clog2(NUM_WARPS)-1:0]   fetch_warp_id,
    output logic [ADDR_WIDTH-1:0]          fetch_pc,
    output logic [THREADS_PER_WARP-1:0]    fetch_active_mask,
    input  wire                            decode_ready
);

    // ========================================================================
    // Fetch State Machine
    // ========================================================================
    typedef enum logic [1:0] {
        F_IDLE    = 2'd0,
        F_REQUEST = 2'd1,
        F_WAIT    = 2'd2,
        F_DONE    = 2'd3
    } fetch_state_t;

    fetch_state_t                    state;
    logic [$clog2(NUM_WARPS)-1:0]    buf_warp_id;
    logic [ADDR_WIDTH-1:0]           buf_pc;
    logic [THREADS_PER_WARP-1:0]     buf_mask;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= F_IDLE;
            imem_req_valid <= 1'b0;
            fetch_valid    <= 1'b0;
            fetch_instr    <= '0;
            buf_warp_id    <= '0;
            buf_pc         <= '0;
            buf_mask       <= '0;
        end else begin
            case (state)
                F_IDLE: begin
                    fetch_valid <= 1'b0;
                    if (sched_valid) begin
                        // Latch request
                        buf_warp_id    <= sched_warp_id;
                        buf_pc         <= sched_pc;
                        buf_mask       <= sched_active_mask;
                        imem_req_valid <= 1'b1;
                        imem_req_addr  <= sched_pc;
                        state          <= F_REQUEST;
                    end
                end

                F_REQUEST: begin
                    if (imem_req_ready) begin
                        imem_req_valid <= 1'b0;
                        state          <= F_WAIT;
                    end
                end

                F_WAIT: begin
                    if (imem_rsp_valid) begin
                        fetch_valid       <= 1'b1;
                        fetch_instr       <= imem_rsp_data;
                        fetch_warp_id     <= buf_warp_id;
                        fetch_pc          <= buf_pc;
                        fetch_active_mask <= buf_mask;
                        state             <= F_DONE;
                    end
                end

                F_DONE: begin
                    if (decode_ready) begin
                        fetch_valid <= 1'b0;
                        state       <= F_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
