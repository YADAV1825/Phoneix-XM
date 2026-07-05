// ============================================================================
// Phoenix-XM GPU — Tensor Core (4×4 Integer MAC Array)
// ============================================================================
// Performs D = A × B + C where A, B, C, D are 4×4 matrices of 32-bit integers.
// Single-instruction invocation: load tiles from registers, compute, writeback.
//
// This is a major differentiator — neither tiny-gpu nor MIAOW have tensor cores.
// Inspired by modern Tensor Cores and Vortex's WGMMA engine, but simplified
// to an integer-only 4×4 systolic-like array.
//
// A single TMMA instruction performs 64 multiply-accumulate operations in
// TC_DIM * TC_DIM * TC_DIM = 64 MACs.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_tensor_core
    import phoenix_pkg::*;
#(
    parameter DIM = TC_DIM  // 4×4
) (
    input  wire clk,
    input  wire rst_n,

    // --- Control ---
    input  wire                    start,     // Begin MMA operation
    output logic                   done,      // Result ready
    output logic                   busy,

    // --- Input Matrices (flattened) ---
    input  wire [DATA_WIDTH-1:0]   mat_a [DIM*DIM],  // A matrix
    input  wire [DATA_WIDTH-1:0]   mat_b [DIM*DIM],  // B matrix
    input  wire [DATA_WIDTH-1:0]   mat_c [DIM*DIM],  // C accumulator (input)

    // --- Output Matrix ---
    output logic [DATA_WIDTH-1:0]  mat_d [DIM*DIM]   // D = A*B + C
);

    // ========================================================================
    // Computation State Machine
    // ========================================================================
    // We pipeline the computation over DIM cycles (k-dimension reduction).
    // Each cycle computes one k-step: D[i][j] += A[i][k] * B[k][j]

    typedef enum logic [1:0] {
        TC_IDLE    = 2'd0,
        TC_COMPUTE = 2'd1,
        TC_DONE    = 2'd2
    } tc_state_t;

    tc_state_t state;
    logic [$clog2(DIM):0] k_step;

    // Accumulator registers
    logic [DATA_WIDTH-1:0] accum [DIM*DIM];

    assign busy = (state != TC_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= TC_IDLE;
            k_step <= '0;
            done   <= 1'b0;
            for (int i = 0; i < DIM; i++)
                for (int j = 0; j < DIM; j++) begin
                    accum[i*DIM + j]  <= '0;
                    mat_d[i*DIM + j]  <= '0;
                end
        end else begin
            done <= 1'b0;

            case (state)
                TC_IDLE: begin
                    if (start) begin
                        // Initialize accumulators with C matrix
                        for (int i = 0; i < DIM; i++)
                            for (int j = 0; j < DIM; j++)
                                accum[i*DIM + j] <= mat_c[i*DIM + j];
                        k_step <= '0;
                        state  <= TC_COMPUTE;
                    end
                end

                TC_COMPUTE: begin
                    // D[i][j] += A[i][k] * B[k][j]  for all i,j at current k
                    for (int i = 0; i < DIM; i++)
                        for (int j = 0; j < DIM; j++)
                            accum[i*DIM + j] <= accum[i*DIM + j] +
                                           (mat_a[i*DIM + k_step[$clog2(DIM)-1:0]] *
                                            mat_b[k_step[$clog2(DIM)-1:0]*DIM + j]);

                    if (k_step == DIM - 1) begin
                        state <= TC_DONE;
                    end else begin
                        k_step <= k_step + 1;
                    end
                end

                TC_DONE: begin
                    // Output final results
                    for (int i = 0; i < DIM; i++)
                        for (int j = 0; j < DIM; j++)
                            mat_d[i*DIM + j] <= accum[i*DIM + j];
                    done  <= 1'b1;
                    state <= TC_IDLE;
                end
            endcase
        end
    end

endmodule
