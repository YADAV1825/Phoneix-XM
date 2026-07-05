// ============================================================================
// Phoenix-XM GPU — Register File
// ============================================================================
// Per-warp, per-thread banked register file.
// 32 registers × 32 bits per thread, per warp.
// Supports 2 reads + 1 write per cycle.
//
// Key improvement over tiny-gpu:
//   tiny-gpu: 16 registers × 8 bits, single-ported, shared across all threads
//   Phoenix:  32 registers × 32 bits, multi-ported, per-warp isolation
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_regfile
    import phoenix_pkg::*;
#(
    parameter NUM_WARPS_P        = NUM_WARPS,
    parameter THREADS_PER_WARP_P = THREADS_PER_WARP,
    parameter NUM_REGS_P         = NUM_REGS,
    parameter DATA_WIDTH_P       = DATA_WIDTH
) (
    input  wire clk,
    input  wire rst_n,

    // --- Read Port A (rs1) ---
    input  wire [$clog2(NUM_WARPS_P)-1:0]  rd_warp_a,
    input  wire [REG_ADDR_BITS-1:0]        rd_addr_a,
    output logic [DATA_WIDTH_P-1:0]        rd_data_a [THREADS_PER_WARP_P],

    // --- Read Port B (rs2) ---
    input  wire [$clog2(NUM_WARPS_P)-1:0]  rd_warp_b,
    input  wire [REG_ADDR_BITS-1:0]        rd_addr_b,
    output logic [DATA_WIDTH_P-1:0]        rd_data_b [THREADS_PER_WARP_P],

    // --- Write Port ---
    input  wire                            wr_en,
    input  wire [$clog2(NUM_WARPS_P)-1:0]  wr_warp,
    input  wire [REG_ADDR_BITS-1:0]        wr_addr,
    input  wire [DATA_WIDTH_P-1:0]         wr_data [THREADS_PER_WARP_P],
    input  wire [THREADS_PER_WARP_P-1:0]   wr_mask  // Per-lane write enable
);

    // ========================================================================
    // Register Storage
    // ========================================================================
    // Organized as: regfile[warp][thread][register]
    logic [DATA_WIDTH_P-1:0] regfile [NUM_WARPS_P][THREADS_PER_WARP_P][NUM_REGS_P];

    // ========================================================================
    // Read Logic (combinational, same-cycle read)
    // ========================================================================
    always_comb begin
        for (int t = 0; t < THREADS_PER_WARP_P; t++) begin
            // x0 is always zero (RISC-V convention)
            rd_data_a[t] = (rd_addr_a == '0) ? '0 : regfile[rd_warp_a][t][rd_addr_a];
            rd_data_b[t] = (rd_addr_b == '0) ? '0 : regfile[rd_warp_b][t][rd_addr_b];
        end
    end

    // ========================================================================
    // Write Logic (synchronous, rising edge)
    // ========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers to zero
            for (int w = 0; w < NUM_WARPS_P; w++) begin
                for (int t = 0; t < THREADS_PER_WARP_P; t++) begin
                    for (int r = 0; r < NUM_REGS_P; r++) begin
                        regfile[w][t][r] <= '0;
                    end
                end
            end
        end else if (wr_en && wr_addr != '0) begin
            // Write to all active lanes (respecting mask)
            // x0 is hardwired to zero — never written
            for (int t = 0; t < THREADS_PER_WARP_P; t++) begin
                if (wr_mask[t]) begin
                    regfile[wr_warp][t][wr_addr] <= wr_data[t];
                end
            end
        end
    end

endmodule
