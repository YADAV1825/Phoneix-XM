// ============================================================================
// Phoenix-XM GPU — Shared Memory (Scratchpad)
// ============================================================================
// Per-SM software-managed shared memory (scratchpad).
// Multi-banked SRAM with bank-conflict detection and stalling.
//
// This is a CRITICAL feature that tiny-gpu completely lacks.
// Shared memory enables:
//   - Tiled matrix multiplication (avoiding redundant global memory reads)
//   - Warp-level and block-level reductions
//   - Producer-consumer data sharing between threads in a block
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_shared_mem
    import phoenix_pkg::*;
#(
    parameter MEM_SIZE_BYTES = SHARED_MEM_SIZE,   // 4096 bytes
    parameter NUM_BANKS_P    = SHARED_MEM_BANKS,  // 4 banks
    parameter DATA_WIDTH_P   = DATA_WIDTH         // 32 bits
) (
    input  wire clk,
    input  wire rst_n,

    // --- Request Interface (per-lane) ---
    input  wire [THREADS_PER_WARP-1:0]    req_valid,
    input  wire [THREADS_PER_WARP-1:0]    req_is_write,
    input  wire [ADDR_WIDTH-1:0]          req_addr  [THREADS_PER_WARP],
    input  wire [DATA_WIDTH_P-1:0]        req_wdata [THREADS_PER_WARP],

    // --- Response Interface (per-lane, 1-cycle latency) ---
    output logic [THREADS_PER_WARP-1:0]   rsp_valid,
    output logic [DATA_WIDTH_P-1:0]       rsp_rdata [THREADS_PER_WARP],

    // --- Conflict Signal ---
    output logic                          bank_conflict  // Stall needed
);

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam WORDS         = MEM_SIZE_BYTES / (DATA_WIDTH_P / 8);  // 1024 words
    localparam WORDS_PER_BANK = WORDS / NUM_BANKS_P;                  // 256 words/bank
    localparam BANK_ADDR_BITS = $clog2(WORDS_PER_BANK);
    localparam BANK_SEL_BITS  = $clog2(NUM_BANKS_P);

    // ========================================================================
    // Bank Storage
    // ========================================================================
    logic [DATA_WIDTH_P-1:0] banks [NUM_BANKS_P][WORDS_PER_BANK];

    // ========================================================================
    // Bank Address Decoding
    // ========================================================================
    logic [BANK_SEL_BITS-1:0]  lane_bank [THREADS_PER_WARP];
    logic [BANK_ADDR_BITS-1:0] lane_word [THREADS_PER_WARP];

    logic [$clog2(WORDS)-1:0] word_addr [THREADS_PER_WARP];
    always_comb begin
        for (int i = 0; i < THREADS_PER_WARP; i++) begin
            // Word address (byte addr / 4)
            word_addr[i] = req_addr[i][$clog2(WORDS)+1:2];  // Skip byte offset
            lane_bank[i] = word_addr[i][BANK_SEL_BITS-1:0];     // Low bits = bank
            lane_word[i] = word_addr[i][BANK_ADDR_BITS+BANK_SEL_BITS-1:BANK_SEL_BITS]; // High bits = word in bank
        end
    end

    // ========================================================================
    // Bank Conflict Detection
    // ========================================================================
    always_comb begin
        bank_conflict = 1'b0;
        for (int i = 0; i < THREADS_PER_WARP; i++) begin
            for (int j = i + 1; j < THREADS_PER_WARP; j++) begin
                if (req_valid[i] && req_valid[j] &&
                    lane_bank[i] == lane_bank[j] &&
                    lane_word[i] != lane_word[j]) begin
                    // Two different words in the same bank = conflict
                    // (Same word = broadcast, no conflict)
                    bank_conflict = 1'b1;
                end
            end
        end
    end

    // ========================================================================
    // Read/Write Logic
    // ========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid <= '0;
            for (int i = 0; i < THREADS_PER_WARP; i++) begin
                rsp_rdata[i] <= '0;
            end
        end else begin
            for (int i = 0; i < THREADS_PER_WARP; i++) begin
                rsp_valid[i] <= 1'b0;

                if (req_valid[i] && !bank_conflict) begin
                    if (req_is_write[i]) begin
                        banks[lane_bank[i]][lane_word[i]] <= req_wdata[i];
                    end else begin
                        rsp_rdata[i] <= banks[lane_bank[i]][lane_word[i]];
                        rsp_valid[i] <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
