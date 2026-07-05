// ============================================================================
// Phoenix-XM GPU — Instruction Decoder
// ============================================================================
// Decodes 32-bit RISC-V-style instructions into a decoded_instr_t bundle.
// Handles: R-type, I-type, S-type, B-type, U-type, J-type, and custom GPGPU.
//
// Key improvement over tiny-gpu's decoder:
//   tiny-gpu: 16-bit, 10 instructions, no branches, no immediates > 8 bits
//   Phoenix:  32-bit, full RV32IM + GPGPU extensions, proper immediate encoding
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_decode
    import phoenix_pkg::*;
(
    input  wire [INSTR_WIDTH-1:0]   instruction,
    input  wire [$clog2(NUM_WARPS)-1:0] warp_id,
    input  wire [THREADS_PER_WARP-1:0]  active_mask,
    input  wire [DATA_WIDTH-1:0]        pc,

    output decoded_instr_t              decoded
);

    // ========================================================================
    // Field Extraction
    // ========================================================================
    wire [6:0] opcode = instruction[6:0];
    wire [4:0] rd_raw = instruction[11:7];
    wire [2:0] funct3 = instruction[14:12];
    wire [4:0] rs1    = instruction[19:15];
    wire [4:0] rs2    = instruction[24:20];
    wire [6:0] funct7 = instruction[31:25];

    // ========================================================================
    // Immediate Extraction (RISC-V encoding)
    // ========================================================================
    wire [DATA_WIDTH-1:0] imm_i = {{20{instruction[31]}}, instruction[31:20]};
    wire [DATA_WIDTH-1:0] imm_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
    wire [DATA_WIDTH-1:0] imm_b = {{19{instruction[31]}}, instruction[31], instruction[7],
                                    instruction[30:25], instruction[11:8], 1'b0};
    wire [DATA_WIDTH-1:0] imm_u = {instruction[31:12], 12'b0};
    wire [DATA_WIDTH-1:0] imm_j = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                                    instruction[20], instruction[30:21], 1'b0};

    wire funct7_5 = funct7[5];

    // Debug wires for cocotb because Icarus cannot easily extract struct members via VPI
    wire [2:0]  dbg_fu_sel    = decoded.fu_sel;
    wire [3:0]  dbg_alu_op    = decoded.alu_op;
    wire        dbg_use_imm   = decoded.use_imm;
    wire [31:0] dbg_immediate = decoded.immediate;
    wire        dbg_mem_read  = decoded.mem_read;
    wire        dbg_mem_write = decoded.mem_write;
    wire        dbg_reg_write = decoded.reg_write;
    wire        dbg_is_branch = decoded.is_branch;
    wire        dbg_is_ret    = decoded.is_ret;

    // ========================================================================
    // Decode Logic
    // ========================================================================
    always_comb begin
        // Defaults
        decoded.raw_instr   = instruction;
        decoded.rd          = rd_raw;
        decoded.rs1         = rs1;
        decoded.rs2         = rs2;
        decoded.immediate   = '0;
        decoded.alu_op      = ALU_NOP;
        decoded.fu_sel      = FU_NONE;
        decoded.reg_write   = 1'b0;
        decoded.mem_read    = 1'b0;
        decoded.mem_write   = 1'b0;
        decoded.is_branch   = 1'b0;
        decoded.is_jump     = 1'b0;
        decoded.use_imm     = 1'b0;
        decoded.is_ret      = 1'b0;
        decoded.funct3      = funct3;
        decoded.funct7      = funct7;
        decoded.warp_id     = warp_id;
        decoded.active_mask = active_mask;

        case (opcode)
            // ============================================================
            // LUI — Load Upper Immediate
            // ============================================================
            OP_LUI: begin
                decoded.fu_sel    = FU_ALU;
                decoded.alu_op    = ALU_LUI;
                decoded.reg_write = 1'b1;
                decoded.use_imm   = 1'b1;
                decoded.immediate = imm_u;
            end

            // ============================================================
            // AUIPC — Add Upper Immediate to PC
            // ============================================================
            OP_AUIPC: begin
                decoded.fu_sel    = FU_ALU;
                decoded.alu_op    = ALU_AUIPC;
                decoded.reg_write = 1'b1;
                decoded.use_imm   = 1'b1;
                decoded.immediate = imm_u;
            end

            // ============================================================
            // JAL — Jump And Link
            // ============================================================
            OP_JAL: begin
                decoded.fu_sel    = FU_BRANCH;
                decoded.is_jump   = 1'b1;
                decoded.reg_write = 1'b1;
                decoded.immediate = imm_j;
            end

            // ============================================================
            // JALR — Jump And Link Register
            // ============================================================
            OP_JALR: begin
                decoded.fu_sel    = FU_BRANCH;
                decoded.is_jump   = 1'b1;
                decoded.reg_write = 1'b1;
                decoded.use_imm   = 1'b1;
                decoded.immediate = imm_i;
            end

            // ============================================================
            // BRANCH — Conditional branches (BEQ, BNE, BLT, BGE, BLTU, BGEU)
            // ============================================================
            OP_BRANCH: begin
                decoded.fu_sel    = FU_BRANCH;
                decoded.is_branch = 1'b1;
                decoded.immediate = imm_b;
            end

            // ============================================================
            // LOAD — Memory loads (LW, LH, LB, LHU, LBU)
            // ============================================================
            OP_LOAD: begin
                decoded.fu_sel    = FU_LSU;
                decoded.mem_read  = 1'b1;
                decoded.reg_write = 1'b1;
                decoded.use_imm   = 1'b1;
                decoded.immediate = imm_i;
            end

            // ============================================================
            // STORE — Memory stores (SW, SH, SB)
            // ============================================================
            OP_STORE: begin
                decoded.fu_sel    = FU_LSU;
                decoded.mem_write = 1'b1;
                decoded.use_imm   = 1'b1;
                decoded.immediate = imm_s;
            end

            // ============================================================
            // ALU Immediate (ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI)
            // ============================================================
            OP_IMM: begin
                decoded.fu_sel    = FU_ALU;
                decoded.reg_write = 1'b1;
                decoded.use_imm   = 1'b1;
                decoded.immediate = imm_i;
                case (funct3)
                    F3_ADD:  decoded.alu_op = ALU_ADD;  // ADDI
                    F3_SLT:  decoded.alu_op = ALU_SLT;  // SLTI
                    F3_SLTU: decoded.alu_op = ALU_SLTU; // SLTIU
                    F3_XOR:  decoded.alu_op = ALU_XOR;  // XORI
                    F3_OR:   decoded.alu_op = ALU_OR;   // ORI
                    F3_AND:  decoded.alu_op = ALU_AND;  // ANDI
                    F3_SLL:  decoded.alu_op = ALU_SLL;  // SLLI
                    F3_SRL: begin
                        if (funct7_5) decoded.alu_op = ALU_SRA;
                        else          decoded.alu_op = ALU_SRL;
                    end
                    default: decoded.alu_op = ALU_NOP;
                endcase
            end

            // ============================================================
            // ALU Register-Register (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND)
            // + M extension (MUL, DIV, REM)
            // ============================================================
            OP_REG: begin
                decoded.fu_sel    = FU_ALU;
                decoded.reg_write = 1'b1;
                if (funct7 == F7_MULDIV) begin
                    // M extension
                    case (funct3)
                        3'b000: decoded.alu_op = ALU_MUL;  // MUL
                        3'b100: decoded.alu_op = ALU_DIV;  // DIV
                        3'b110: decoded.alu_op = ALU_REM;  // REM
                        default: decoded.alu_op = ALU_MUL;
                    endcase
                end else begin
                    case (funct3)
                        F3_ADD: begin
                            if (funct7_5) decoded.alu_op = ALU_SUB;
                            else          decoded.alu_op = ALU_ADD;
                        end
                        F3_SLL:  decoded.alu_op = ALU_SLL;
                        F3_SLT:  decoded.alu_op = ALU_SLT;
                        F3_SLTU: decoded.alu_op = ALU_SLTU;
                        F3_XOR:  decoded.alu_op = ALU_XOR;
                        F3_SRL: begin
                            if (funct7_5) decoded.alu_op = ALU_SRA;
                            else          decoded.alu_op = ALU_SRL;
                        end
                        F3_OR:   decoded.alu_op = ALU_OR;
                        F3_AND:  decoded.alu_op = ALU_AND;
                        default: decoded.alu_op = ALU_NOP;
                    endcase
                end
            end

            // ============================================================
            // GPU — Warp/Thread control (TMC, WSPAWN, SPLIT, JOIN, BAR, RET)
            // ============================================================
            OP_GPU: begin
                decoded.fu_sel = FU_SFU;
                case (funct3)
                    F3_TMC:    begin /* Thread Mask Control */ end
                    F3_WSPAWN: begin /* Warp Spawn */ end
                    F3_SPLIT:  begin /* IPDOM Split */ end
                    F3_JOIN:   begin /* IPDOM Join */  end
                    F3_BAR:    begin /* Barrier */     end
                    F3_RET: begin
                        decoded.is_ret = 1'b1;
                    end
                    default: ;
                endcase
            end

            // ============================================================
            // TENSOR — Tensor core operations
            // ============================================================
            OP_TENSOR: begin
                decoded.fu_sel = FU_TENSOR;
                decoded.reg_write = (funct3 == F3_TMMA);
            end

            // ============================================================
            // BARRIER — Synchronization
            // ============================================================
            OP_BARRIER: begin
                decoded.fu_sel = FU_SFU;
            end

            default: begin
                // NOP / illegal instruction
                decoded.fu_sel = FU_NONE;
            end
        endcase
    end

endmodule
