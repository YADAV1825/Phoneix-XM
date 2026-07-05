// ============================================================================
// Phoenix-XM GPU — Tile Crossbar
// ============================================================================
// Connects N SMs (L1 caches) to the shared L2 cache.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_tile_crossbar
    import phoenix_pkg::*;
#(
    parameter NUM_CLIENTS = SMS_PER_TILE,
    parameter LINE_BITS   = L1_DCACHE_LINE_BITS
) (
    input  wire clk,
    input  wire rst_n,

    // --- Client Interfaces (SMs) ---
    input  wire [NUM_CLIENTS-1:0]          client_req_valid,
    input  wire [NUM_CLIENTS-1:0]          client_req_is_write,
    input  wire [ADDR_WIDTH-1:0]           client_req_addr  [NUM_CLIENTS],
    input  wire [LINE_BITS-1:0]            client_req_wdata [NUM_CLIENTS],
    input  wire [(LINE_BITS/8)-1:0]        client_req_byte_en [NUM_CLIENTS],
    output logic [NUM_CLIENTS-1:0]         client_req_ready,

    output logic [NUM_CLIENTS-1:0]         client_rsp_valid,
    output logic [LINE_BITS-1:0]           client_rsp_rdata [NUM_CLIENTS],

    // --- Server Interface (L2 Cache) ---
    output logic                           server_req_valid,
    output logic                           server_req_is_write,
    output logic [ADDR_WIDTH-1:0]          server_req_addr,
    output logic [LINE_BITS-1:0]           server_req_wdata,
    output logic [(LINE_BITS/8)-1:0]       server_req_byte_en,
    input  wire                            server_req_ready,

    input  wire                            server_rsp_valid,
    input  wire [LINE_BITS-1:0]            server_rsp_rdata
);

    // Simple round-robin arbiter for simulation
    logic [$clog2(NUM_CLIENTS)-1:0] rr_ptr;
    logic                           req_in_flight;
    logic [$clog2(NUM_CLIENTS)-1:0] active_client;

    logic [$clog2(NUM_CLIENTS)-1:0] grant_idx [NUM_CLIENTS];
    always_comb begin
        server_req_valid = 1'b0;
        server_req_is_write = 1'b0;
        server_req_addr = '0;
        server_req_wdata = '0;
        server_req_byte_en = '0;

        for (int i = 0; i < NUM_CLIENTS; i++) begin
            client_req_ready[i] = 1'b0;
            client_rsp_valid[i] = 1'b0;
            client_rsp_rdata[i] = '0;
        end

        // Grant logic
        if (!req_in_flight) begin
            for (int i = 0; i < NUM_CLIENTS; i++) begin
                grant_idx[i] = (rr_ptr + i[$clog2(NUM_CLIENTS)-1:0]) % NUM_CLIENTS;

                if (client_req_valid[grant_idx[i]]) begin
                    server_req_valid = 1'b1;
                    server_req_is_write = client_req_is_write[grant_idx[i]];
                    server_req_addr = client_req_addr[grant_idx[i]];
                    server_req_wdata = client_req_wdata[grant_idx[i]];
                    server_req_byte_en = client_req_byte_en[grant_idx[i]];

                    client_req_ready[grant_idx[i]] = server_req_ready;
                    break;
                end
            end
        end

        // Response routing
        if (req_in_flight) begin
            client_rsp_valid[active_client] = server_rsp_valid;
            client_rsp_rdata[active_client] = server_rsp_rdata;
        end
    end

    logic [$clog2(NUM_CLIENTS)-1:0] route_idx [NUM_CLIENTS];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr <= '0;
            req_in_flight <= 1'b0;
            active_client <= '0;
        end else begin
            if (!req_in_flight) begin
                for (int i = 0; i < NUM_CLIENTS; i++) begin
                    route_idx[i] = (rr_ptr + i[$clog2(NUM_CLIENTS)-1:0]) % NUM_CLIENTS;

                    if (client_req_valid[route_idx[i]] && server_req_ready) begin
                        if (!client_req_is_write[route_idx[i]]) begin
                            req_in_flight <= 1'b1;
                            active_client <= route_idx[i];
                        end
                        rr_ptr <= (route_idx[i] + 1) % NUM_CLIENTS;
                        break;
                    end
                end
            end else begin
                if (server_rsp_valid) begin
                    req_in_flight <= 1'b0;
                end
            end
        end
    end

endmodule
