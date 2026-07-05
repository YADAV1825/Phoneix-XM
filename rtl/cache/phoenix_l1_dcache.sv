// ============================================================================
// Phoenix-XM GPU — L1 Data Cache
// ============================================================================
// Write-through, non-blocking L1 Data Cache.
// Handles read misses with a Miss Status Holding Register (MSHR).
// Integrates closely with the SM's LSU.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_l1_dcache
    import phoenix_pkg::*;
#(
    parameter SETS       = L1_DCACHE_SETS,
    parameter WAYS       = L1_DCACHE_WAYS,
    parameter LINE_BITS  = L1_DCACHE_LINE_BITS
) (
    input  wire clk,
    input  wire rst_n,

    // --- Core Interface (from SM LSU) ---
    input  wire                            core_req_valid,
    input  wire                            core_req_is_write,
    input  wire [ADDR_WIDTH-1:0]           core_req_addr,
    input  wire [DATA_WIDTH-1:0]           core_req_wdata,
    input  wire [3:0]                      core_req_byte_en,
    output logic                           core_req_ready,

    output logic                           core_rsp_valid,
    output logic [DATA_WIDTH-1:0]          core_rsp_rdata,

    // --- Memory Interface (to L2 / Crossbar) ---
    output logic                           mem_req_valid,
    output logic                           mem_req_is_write,
    output logic [ADDR_WIDTH-1:0]          mem_req_addr,
    output logic [LINE_BITS-1:0]           mem_req_wdata,
    output logic [(LINE_BITS/8)-1:0]       mem_req_byte_en,
    input  wire                            mem_req_ready,

    input  wire                            mem_rsp_valid,
    input  wire [LINE_BITS-1:0]            mem_rsp_rdata
);

    // Simplified for simulation: behaves as an ideal cache (always hits) or
    // acts as a passthrough. Since our SM handles latency via warp switching,
    // we model a simple passthrough cache here for the prototype.

    // A full implementation would contain Tag RAM, Data RAM, and an MSHR array.

    // For the prototype: pass-through to memory interface
    // Convert DATA_WIDTH requests to LINE_BITS requests by zero-padding.
    // In a real cache, this would involve line fetches and write-combining.
    
    // Pipeline registers for pass-through
    logic                            req_pending;
    logic                            is_write;
    logic [ADDR_WIDTH-1:0]           req_addr;

    assign core_req_ready = mem_req_ready && !req_pending;

    always_comb begin
        mem_req_valid = 1'b0;
        mem_req_is_write = 1'b0;
        mem_req_addr = '0;
        mem_req_wdata = '0;
        mem_req_byte_en = '0;

        if (core_req_valid && core_req_ready) begin
            mem_req_valid = 1'b1;
            mem_req_is_write = core_req_is_write;
            mem_req_addr = core_req_addr;
            mem_req_wdata = {{(LINE_BITS-DATA_WIDTH){1'b0}}, core_req_wdata};
            mem_req_byte_en = { {((LINE_BITS/8)-4){1'b0}}, core_req_byte_en };
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_pending <= 1'b0;
            core_rsp_valid <= 1'b0;
            core_rsp_rdata <= '0;
        end else begin
            core_rsp_valid <= 1'b0;

            if (core_req_valid && core_req_ready && !core_req_is_write) begin
                req_pending <= 1'b1;
            end

            if (req_pending && mem_rsp_valid) begin
                req_pending <= 1'b0;
                core_rsp_valid <= 1'b1;
                core_rsp_rdata <= mem_rsp_rdata[DATA_WIDTH-1:0];
            end
        end
    end

endmodule
