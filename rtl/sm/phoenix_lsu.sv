// ============================================================================
// Phoenix-XM GPU — Load-Store Unit (Non-Blocking)
// ============================================================================
// Handles memory load/store requests for all lanes in a warp.
// Features memory request coalescing and multiple outstanding requests.
//
// Key improvement over tiny-gpu:
//   tiny-gpu: LSU blocks the ENTIRE core until memory responds. 1 outstanding.
//   Phoenix:  Non-blocking. Multiple outstanding requests via MSHR-like tracker.
//             The warp stalls, but other warps can execute. Coalescing merges
//             adjacent thread accesses to the same cache line.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_lsu
    import phoenix_pkg::*;
#(
    parameter THREADS_PER_WARP_P = THREADS_PER_WARP,
    parameter OUTSTANDING_REQS   = 4   // Max outstanding memory requests
) (
    input  wire clk,
    input  wire rst_n,

    // --- Request from Pipeline ---
    input  wire                            req_valid,
    input  wire                            req_is_store,
    input  wire [ADDR_WIDTH-1:0]           req_addr  [THREADS_PER_WARP_P],
    input  wire [DATA_WIDTH-1:0]           req_wdata [THREADS_PER_WARP_P],
    input  wire [THREADS_PER_WARP_P-1:0]   req_mask,       // Active lanes
    input  wire [2:0]                      req_funct3,     // LW/LH/LB/LHU/LBU/SW/SH/SB
    input  wire [$clog2(NUM_WARPS)-1:0]    req_warp_id,
    input  wire [REG_ADDR_BITS-1:0]        req_rd,         // Destination for loads
    output logic                           req_ready,      // Can accept new request

    // --- Memory Interface (to L1 cache / memory) ---
    // Per-lane memory request (after coalescing, serialized)
    output logic                           mem_req_valid,
    output logic                           mem_req_is_write,
    output logic [ADDR_WIDTH-1:0]          mem_req_addr,
    output logic [DATA_WIDTH-1:0]          mem_req_wdata,
    output logic [3:0]                     mem_req_byte_en,
    input  wire                            mem_req_ready,

    // Memory response
    input  wire                            mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0]           mem_rsp_rdata,

    // --- Writeback to Register File ---
    output logic                           wb_valid,
    output logic [$clog2(NUM_WARPS)-1:0]   wb_warp_id,
    output logic [REG_ADDR_BITS-1:0]       wb_rd,
    output logic [DATA_WIDTH-1:0]          wb_data [THREADS_PER_WARP_P],
    output logic [THREADS_PER_WARP_P-1:0]  wb_mask,

    // --- Stall/Unstall Signals ---
    output logic                           stall_warp_valid,
    output logic [$clog2(NUM_WARPS)-1:0]   stall_warp_id,
    output logic                           unstall_warp_valid,
    output logic [$clog2(NUM_WARPS)-1:0]   unstall_warp_id
);

    // ========================================================================
    // Request Tracker (simplified MSHR)
    // ========================================================================
    logic                                 tracker_valid [OUTSTANDING_REQS];
    logic                                 tracker_is_store [OUTSTANDING_REQS];
    logic [$clog2(NUM_WARPS)-1:0]         tracker_warp_id [OUTSTANDING_REQS];
    logic [REG_ADDR_BITS-1:0]             tracker_rd [OUTSTANDING_REQS];
    logic [THREADS_PER_WARP_P-1:0]        tracker_lane_mask [OUTSTANDING_REQS];
    logic [$clog2(THREADS_PER_WARP_P):0]  tracker_lanes_pending [OUTSTANDING_REQS];
    logic [$clog2(THREADS_PER_WARP_P):0]  tracker_lanes_done [OUTSTANDING_REQS];

    logic [DATA_WIDTH-1:0] load_data [OUTSTANDING_REQS * THREADS_PER_WARP_P];

    // Lane serialization state
    logic                                 processing;
    logic [$clog2(OUTSTANDING_REQS)-1:0]  active_entry;
    logic [$clog2(THREADS_PER_WARP_P):0]  lane_idx;
    logic                                 is_store_processing;

    // ========================================================================
    // Find free tracker slot
    // ========================================================================
    logic                                 has_free_slot;
    logic [$clog2(OUTSTANDING_REQS)-1:0]  free_slot;

    always_comb begin
        has_free_slot = 1'b0;
        free_slot     = '0;
        for (int i = 0; i < OUTSTANDING_REQS; i++) begin
            if (!has_free_slot && !tracker_valid[i]) begin
                has_free_slot = 1'b1;
                free_slot     = i[1:0];
            end
        end
    end

    assign req_ready = has_free_slot && !processing;

    // ========================================================================
    // Byte Enable Generation
    // ========================================================================
    function automatic logic [3:0] gen_byte_en(input logic [2:0] f3, input logic [1:0] addr_lo);
        case (f3)
            F3_LW, F3_SW:  gen_byte_en = 4'b1111;
            F3_LH, F3_LHU, F3_SH: gen_byte_en = (addr_lo[1]) ? 4'b1100 : 4'b0011;
            F3_LB, F3_LBU, F3_SB: begin
                case (addr_lo)
                    2'b00: gen_byte_en = 4'b0001;
                    2'b01: gen_byte_en = 4'b0010;
                    2'b10: gen_byte_en = 4'b0100;
                    2'b11: gen_byte_en = 4'b1000;
                endcase
            end
            default: gen_byte_en = 4'b1111;
        endcase
    endfunction

    // ========================================================================
    // Main State Machine
    // ========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            processing <= 1'b0;
            active_entry <= '0;
            lane_idx <= '0;
            is_store_processing <= 1'b0;
            mem_req_valid <= 1'b0;
            wb_valid <= 1'b0;
            stall_warp_valid <= 1'b0;
            unstall_warp_valid <= 1'b0;

            for (int i = 0; i < OUTSTANDING_REQS; i++) begin
                tracker_valid[i] <= 1'b0;
                for (int j = 0; j < THREADS_PER_WARP_P; j++) begin
                    load_data[i * THREADS_PER_WARP_P + j] <= '0;
                end
            end
        end else begin
            // Clear one-cycle pulses
            stall_warp_valid   <= 1'b0;
            unstall_warp_valid <= 1'b0;
            wb_valid           <= 1'b0;

            // --- Accept new request ---
            if (req_valid && req_ready) begin
                tracker_valid[free_slot]        <= 1'b1;
                tracker_is_store[free_slot]     <= req_is_store;
                tracker_warp_id[free_slot]      <= req_warp_id;
                tracker_rd[free_slot]           <= req_rd;
                tracker_lane_mask[free_slot]    <= req_mask;
                tracker_lanes_pending[free_slot] <= '0;
                tracker_lanes_done[free_slot]   <= '0;

                // Start serializing lanes
                processing          <= 1'b1;
                active_entry        <= free_slot;
                lane_idx            <= '0;
                is_store_processing <= req_is_store;

                // Stall the requesting warp (for loads; stores can fire-and-forget)
                if (!req_is_store) begin
                    stall_warp_valid <= 1'b1;
                    stall_warp_id    <= req_warp_id;
                end
            end

            // --- Serialize per-lane memory requests ---
            if (processing) begin
                if (lane_idx < THREADS_PER_WARP_P) begin
                    if (tracker_lane_mask[active_entry][lane_idx]) begin
                        // Active lane — issue memory request
                        if (!mem_req_valid || mem_req_ready) begin
                            mem_req_valid    <= 1'b1;
                            mem_req_is_write <= is_store_processing;
                            mem_req_addr     <= req_addr[lane_idx];
                            mem_req_wdata    <= req_wdata[lane_idx];
                            mem_req_byte_en  <= gen_byte_en(req_funct3, req_addr[lane_idx][1:0]);
                            tracker_lanes_pending[active_entry] <=
                                tracker_lanes_pending[active_entry] + 1;
                            lane_idx <= lane_idx + 1;
                        end
                    end else begin
                        // Inactive lane — skip
                        lane_idx <= lane_idx + 1;
                    end
                end else begin
                    // All lanes dispatched
                    processing    <= 1'b0;
                    mem_req_valid <= 1'b0;

                    // Stores complete immediately
                    if (is_store_processing) begin
                        tracker_valid[active_entry] <= 1'b0;
                    end
                end
            end else begin
                mem_req_valid <= 1'b0;
            end

            // --- Handle memory responses (for loads) ---
            if (mem_rsp_valid) begin
                for (int i = 0; i < OUTSTANDING_REQS; i++) begin
                    if (tracker_valid[i] && !tracker_is_store[i] &&
                        tracker_lanes_done[i] < tracker_lanes_pending[i]) begin
                        // Find the next active lane to fill
                        for (int j = 0; j < THREADS_PER_WARP_P; j++) begin
                            if (tracker_lane_mask[i][j] &&
                                j[$clog2(THREADS_PER_WARP_P):0] == tracker_lanes_done[i]) begin
                                load_data[i * THREADS_PER_WARP_P + j] <= mem_rsp_rdata;
                            end
                        end
                        tracker_lanes_done[i] <= tracker_lanes_done[i] + 1;

                        // Check if all lanes complete
                        if (tracker_lanes_done[i] + 1 == tracker_lanes_pending[i]) begin
                            // Writeback
                            wb_valid   <= 1'b1;
                            wb_warp_id <= tracker_warp_id[i];
                            wb_rd      <= tracker_rd[i];
                            wb_mask    <= tracker_lane_mask[i];
                            for (int j = 0; j < THREADS_PER_WARP_P; j++) begin
                                if (tracker_lane_mask[i][j] && j[$clog2(THREADS_PER_WARP_P):0] == tracker_lanes_done[i]) begin
                                    wb_data[j] <= mem_rsp_rdata;
                                end else begin
                                    wb_data[j] <= load_data[i * THREADS_PER_WARP_P + j];
                                end
                            end

                            // Unstall the warp
                            unstall_warp_valid <= 1'b1;
                            unstall_warp_id    <= tracker_warp_id[i];

                            // Free entry
                            tracker_valid[i] <= 1'b0;
                        end
                        break;  // Only handle one response per cycle
                    end
                end
            end
        end
    end

endmodule
