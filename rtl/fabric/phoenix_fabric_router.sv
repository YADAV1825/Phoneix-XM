// ============================================================================
// Phoenix-XM GPU — Fabric Router
// ============================================================================
// Per-tile router that decides if memory requests are local or remote.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_fabric_router
    import phoenix_pkg::*;
#(
    parameter TILE_ID     = 0,
    parameter NUM_TILES_P = NUM_TILES,
    parameter BW_BITS     = FABRIC_BW_BITS
) (
    input  wire clk,
    input  wire rst_n,

    // --- Local Tile Interface ---
    input  wire                            local_req_valid,
    input  wire [ADDR_WIDTH-1:0]           local_req_addr,
    input  wire [BW_BITS-1:0]              local_req_data,
    output logic                           local_req_ready,

    output logic                           local_rsp_valid,
    output logic [BW_BITS-1:0]             local_rsp_data,

    // --- Fabric Interface ---
    output logic                           fab_req_valid,
    output logic [ADDR_WIDTH-1:0]          fab_req_addr,
    output logic [BW_BITS-1:0]             fab_req_data,
    output logic [$clog2(NUM_TILES_P)-1:0] fab_req_dest,
    input  wire                            fab_req_ready,

    input  wire                            fab_rsp_valid,
    input  wire [BW_BITS-1:0]              fab_rsp_data,
    output logic                           fab_rsp_ready
);

    // Placeholder
    assign local_req_ready = 1'b1;
    assign local_rsp_valid = 1'b0;
    assign fab_req_valid = 1'b0;
    assign fab_rsp_ready = 1'b1;

endmodule
