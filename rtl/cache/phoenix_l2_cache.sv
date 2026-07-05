// ============================================================================
// Phoenix-XM GPU — L2 Cache
// ============================================================================
// Shared L2 Cache for a Compute Tile.
// Connects the tile crossbar to the global memory interconnect.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_l2_cache
    import phoenix_pkg::*;
#(
    parameter SETS       = L2_CACHE_SETS,
    parameter WAYS       = L2_CACHE_WAYS,
    parameter LINE_BITS  = L2_CACHE_LINE_BITS
) (
    input  wire clk,
    input  wire rst_n,

    // --- Tile Crossbar Interface ---
    input  wire                            xbar_req_valid,
    input  wire                            xbar_req_is_write,
    input  wire [ADDR_WIDTH-1:0]           xbar_req_addr,
    input  wire [LINE_BITS-1:0]            xbar_req_wdata,
    input  wire [(LINE_BITS/8)-1:0]        xbar_req_byte_en,
    output logic                           xbar_req_ready,

    output logic                           xbar_rsp_valid,
    output logic [LINE_BITS-1:0]           xbar_rsp_rdata,

    // --- Global Fabric / Memory Interface ---
    output logic                           mem_req_valid,
    output logic                           mem_req_is_write,
    output logic [ADDR_WIDTH-1:0]          mem_req_addr,
    output logic [LINE_BITS-1:0]           mem_req_wdata,
    output logic [(LINE_BITS/8)-1:0]       mem_req_byte_en,
    input  wire                            mem_req_ready,

    input  wire                            mem_rsp_valid,
    input  wire [LINE_BITS-1:0]            mem_rsp_rdata
);

    // Placeholder: pass-through for simulation
    logic req_pending;

    assign xbar_req_ready = mem_req_ready && !req_pending;

    always_comb begin
        mem_req_valid = 1'b0;
        mem_req_is_write = 1'b0;
        mem_req_addr = '0;
        mem_req_wdata = '0;
        mem_req_byte_en = '0;

        if (xbar_req_valid && xbar_req_ready) begin
            mem_req_valid = 1'b1;
            mem_req_is_write = xbar_req_is_write;
            mem_req_addr = xbar_req_addr;
            mem_req_wdata = xbar_req_wdata;
            mem_req_byte_en = xbar_req_byte_en;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_pending <= 1'b0;
            xbar_rsp_valid <= 1'b0;
            xbar_rsp_rdata <= '0;
        end else begin
            xbar_rsp_valid <= 1'b0;

            if (xbar_req_valid && xbar_req_ready && !xbar_req_is_write) begin
                req_pending <= 1'b1;
            end

            if (req_pending && mem_rsp_valid) begin
                req_pending <= 1'b0;
                xbar_rsp_valid <= 1'b1;
                xbar_rsp_rdata <= mem_rsp_rdata;
            end
        end
    end

endmodule
