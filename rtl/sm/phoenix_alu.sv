// ============================================================================
// Phoenix-XM GPU — SIMD ALU
// ============================================================================
// Parallel Arithmetic Logic Unit with THREADS_PER_WARP lanes.
// Each lane independently computes the selected operation.
// Active mask gates which lanes actually execute.
//
// Supported operations (vs tiny-gpu's ADD/SUB/MUL/DIV/CMP only):
//   ADD, SUB, MUL, DIV, REM, AND, OR, XOR, SLL, SRL, SRA,
//   SLT, SLTU, LUI, AUIPC
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_alu
    import phoenix_pkg::*;
#(
    parameter THREADS_PER_WARP_P = THREADS_PER_WARP,
    parameter DATA_WIDTH_P       = DATA_WIDTH
) (
    // --- Operands (per-lane) ---
    input  wire [DATA_WIDTH_P-1:0]  rs1 [THREADS_PER_WARP_P],
    input  wire [DATA_WIDTH_P-1:0]  rs2 [THREADS_PER_WARP_P],  // or immediate
    input  wire [DATA_WIDTH_P-1:0]  pc_in,                     // For AUIPC

    // --- Control ---
    input  wire [THREADS_PER_WARP_P-1:0] active_mask,
    input  alu_op_t                      alu_op,

    // --- Results (per-lane) ---
    output logic [DATA_WIDTH_P-1:0] result [THREADS_PER_WARP_P],

    // --- Branch comparison (for branch unit, single flag) ---
    output logic [THREADS_PER_WARP_P-1:0] cmp_zero,    // rs1 == rs2
    output logic [THREADS_PER_WARP_P-1:0] cmp_lt_s,    // signed rs1 < rs2
    output logic [THREADS_PER_WARP_P-1:0] cmp_lt_u     // unsigned rs1 < rs2
);

    // ========================================================================
    // Per-Lane Combinational Logic
    // ========================================================================
    always_comb begin
        for (int i = 0; i < THREADS_PER_WARP_P; i++) begin
            // Default outputs
            result[i] = '0;
            cmp_zero[i] = (rs1[i] == rs2[i]);
            cmp_lt_s[i] = ($signed(rs1[i]) < $signed(rs2[i]));
            cmp_lt_u[i] = (rs1[i] < rs2[i]);

            if (active_mask[i]) begin
                case (alu_op)
                    ALU_ADD:   result[i] = rs1[i] + rs2[i];
                    ALU_SUB:   result[i] = rs1[i] - rs2[i];
                    ALU_AND:   result[i] = rs1[i] & rs2[i];
                    ALU_OR:    result[i] = rs1[i] | rs2[i];
                    ALU_XOR:   result[i] = rs1[i] ^ rs2[i];
                    ALU_SLL:   result[i] = rs1[i] << (rs2[i] & 32'h1F);
                    ALU_SRL:   result[i] = rs1[i] >> (rs2[i] & 32'h1F);
                    ALU_SRA:   result[i] = $signed(rs1[i]) >>> (rs2[i] & 32'h1F);
                    ALU_SLT:   result[i] = {31'b0, cmp_lt_s[i]};
                    ALU_SLTU:  result[i] = {31'b0, cmp_lt_u[i]};
                    ALU_MUL:   result[i] = rs1[i] * rs2[i];  // Lower 32 bits
                    ALU_DIV: begin
                        if (rs2[i] != '0)
                            result[i] = $signed(rs1[i]) / $signed(rs2[i]);
                        else
                            result[i] = '1;  // RISC-V spec: div by zero → all 1s
                    end
                    ALU_REM: begin
                        if (rs2[i] != '0)
                            result[i] = $signed(rs1[i]) % $signed(rs2[i]);
                        else
                            result[i] = rs1[i];  // RISC-V spec: rem by zero → dividend
                    end
                    ALU_LUI:   result[i] = rs2[i];  // Upper immediate (already shifted)
                    ALU_AUIPC: result[i] = pc_in + rs2[i];
                    ALU_NOP:   result[i] = '0;
                    default:   result[i] = '0;
                endcase
            end
        end
    end

endmodule
