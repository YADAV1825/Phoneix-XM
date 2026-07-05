// ============================================================================
// Phoenix-XM GPU — L1 Instruction Cache
// ============================================================================
// Read-only instruction cache.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_l1_icache
    import phoenix_pkg::*;
#(
    parameter SETS       = L1_ICACHE_SETS,
    parameter WAYS       = L1_ICACHE_WAYS,
    parameter LINE_BITS  = L1_ICACHE_LINE_BITS
) (
    input  wire clk,
    input  wire rst_n,

    // --- Core Interface ---
    input  wire                            core_req_valid,
    input  wire [ADDR_WIDTH-1:0]           core_req_addr,
    output logic                           core_req_ready,

    output logic                           core_rsp_valid,
    output logic [INSTR_WIDTH-1:0]         core_rsp_rdata,

    // --- Memory Interface (to L2 / Crossbar) ---
    output logic                           mem_req_valid,
    output logic [ADDR_WIDTH-1:0]          mem_req_addr,
    input  wire                            mem_req_ready,

    input  wire                            mem_rsp_valid,
    input  wire [LINE_BITS-1:0]            mem_rsp_rdata
);

    // Simplified pass-through for the prototype
    logic req_pending;

    assign core_req_ready = mem_req_ready && !req_pending;

    always_comb begin
        mem_req_valid = core_req_valid && core_req_ready;
        mem_req_addr  = core_req_addr;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_pending <= 1'b0;
            core_rsp_valid <= 1'b0;
            core_rsp_rdata <= '0;
        end else begin
            core_rsp_valid <= 1'b0;

            if (core_req_valid && core_req_ready) begin
                req_pending <= 1'b1;
            end

            if (req_pending && mem_rsp_valid) begin
                req_pending <= 1'b0;
                core_rsp_valid <= 1'b1;
                core_rsp_rdata <= mem_rsp_rdata[INSTR_WIDTH-1:0];
            end
        end
    end

endmodule
