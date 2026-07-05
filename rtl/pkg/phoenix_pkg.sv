// ============================================================================
// Phoenix-XM GPU — Central Architecture Package
// ============================================================================
// All configurable parameters, ISA definitions, and shared types live here.
// Every module imports this package.
// ============================================================================
`default_nettype none

package phoenix_pkg;

    // ========================================================================
    // ARCHITECTURE PARAMETERS
    // ========================================================================

    // --- GPU Top-Level ---
    parameter NUM_TILES           = 2;     // Number of compute tiles (chiplets)

    // --- Per-Tile ---
    parameter SMS_PER_TILE        = 4;     // Streaming Multiprocessors per tile
    parameter TOTAL_SMS           = NUM_TILES * SMS_PER_TILE;

    // --- Per-SM ---
    parameter NUM_WARPS           = 8;     // Warps per SM (for latency hiding)
    parameter THREADS_PER_WARP    = 4;     // SIMD width (lanes per warp)
    parameter MAX_BLOCKS_PER_SM   = 4;     // Max concurrent CTAs per SM

    // --- Register File ---
    parameter NUM_REGS            = 32;    // Registers per thread
    parameter REG_WIDTH           = 32;    // Bits per register
    parameter REG_ADDR_BITS       = 5;     // log2(NUM_REGS)

    // --- Data Widths ---
    parameter DATA_WIDTH          = 32;    // Data path width
    parameter ADDR_WIDTH          = 32;    // Address width
    parameter INSTR_WIDTH         = 32;    // Instruction width

    // --- Memory ---
    parameter SHARED_MEM_SIZE     = 4096;  // Bytes of shared memory per SM
    parameter SHARED_MEM_BANKS    = 4;     // Shared memory banks
    parameter L1_DCACHE_SETS      = 16;    // L1 data cache sets
    parameter L1_DCACHE_WAYS      = 2;     // L1 data cache ways
    parameter L1_DCACHE_LINE_BITS = 128;   // L1 cache line width (4 words)
    parameter L1_ICACHE_SETS      = 16;
    parameter L1_ICACHE_WAYS      = 2;
    parameter L1_ICACHE_LINE_BITS = 128;
    parameter L2_CACHE_SETS       = 64;
    parameter L2_CACHE_WAYS       = 4;
    parameter L2_CACHE_LINE_BITS  = 256;
    parameter MSHR_ENTRIES        = 4;     // Outstanding misses per cache

    // --- Fabric ---
    parameter FABRIC_LATENCY      = 20;    // Inter-tile latency (cycles)
    parameter FABRIC_BW_BITS      = 256;   // Fabric link width (bits)

    // --- Tensor Core ---
    parameter TC_DIM              = 4;     // 4x4 MAC array

    // ========================================================================
    // ISA DEFINITIONS — 32-bit RISC-V inspired with GPGPU extensions
    // ========================================================================

    // --- Major Opcode Field [6:0] ---
    // Standard RV32I-like encodings for base integer ops
    localparam OP_LUI       = 7'b0110111;   // Load Upper Immediate
    localparam OP_AUIPC     = 7'b0010111;   // Add Upper Imm to PC
    localparam OP_JAL       = 7'b1101111;   // Jump And Link
    localparam OP_JALR      = 7'b1100111;   // Jump And Link Register
    localparam OP_BRANCH    = 7'b1100011;   // Conditional Branch
    localparam OP_LOAD      = 7'b0000011;   // Load from memory
    localparam OP_STORE     = 7'b0100011;   // Store to memory
    localparam OP_IMM       = 7'b0010011;   // ALU Immediate
    localparam OP_REG       = 7'b0110011;   // ALU Register-Register

    // Custom GPGPU extensions (using RISC-V custom opcode space)
    localparam OP_GPU       = 7'b0001011;   // custom-0: GPU warp/thread control
    localparam OP_TENSOR    = 7'b0101011;   // custom-1: Tensor core operations
    localparam OP_BARRIER   = 7'b1011011;   // custom-2: Barrier / sync
    localparam OP_SPECIAL   = 7'b1111011;   // custom-3: Special / system

    // --- funct3 for OP_REG (R-type ALU) ---
    localparam F3_ADD  = 3'b000;
    localparam F3_SLL  = 3'b001;
    localparam F3_SLT  = 3'b010;
    localparam F3_SLTU = 3'b011;
    localparam F3_XOR  = 3'b100;
    localparam F3_SRL  = 3'b101;   // SRA when funct7[5]=1
    localparam F3_OR   = 3'b110;
    localparam F3_AND  = 3'b111;

    // --- funct7 for multiply (M extension) ---
    localparam F7_MULDIV = 7'b0000001;  // MUL/DIV/REM variants

    // --- funct3 for OP_GPU ---
    localparam F3_TMC    = 3'b000;  // Thread Mask Control
    localparam F3_WSPAWN = 3'b001;  // Warp Spawn
    localparam F3_SPLIT  = 3'b010;  // IPDOM Split
    localparam F3_JOIN   = 3'b011;  // IPDOM Join
    localparam F3_BAR    = 3'b100;  // Barrier
    localparam F3_RET    = 3'b111;  // Kernel Return (done)

    // --- funct3 for OP_BRANCH ---
    localparam F3_BEQ  = 3'b000;
    localparam F3_BNE  = 3'b001;
    localparam F3_BLT  = 3'b100;
    localparam F3_BGE  = 3'b101;
    localparam F3_BLTU = 3'b110;
    localparam F3_BGEU = 3'b111;

    // --- funct3 for OP_LOAD ---
    localparam F3_LW   = 3'b010;
    localparam F3_LH   = 3'b001;
    localparam F3_LB   = 3'b000;
    localparam F3_LHU  = 3'b101;
    localparam F3_LBU  = 3'b100;

    // --- funct3 for OP_STORE ---
    localparam F3_SW   = 3'b010;
    localparam F3_SH   = 3'b001;
    localparam F3_SB   = 3'b000;

    // --- funct3 for OP_TENSOR ---
    localparam F3_TMMA  = 3'b000;  // Tensor MMA (4x4 MAC)
    localparam F3_TLOAD = 3'b001;  // Tensor Load (tile from mem)

    // ========================================================================
    // PIPELINE TYPES
    // ========================================================================

    // --- Core State (for simple sub-modules) ---
    typedef enum logic [2:0] {
        CORE_IDLE     = 3'd0,
        CORE_FETCH    = 3'd1,
        CORE_DECODE   = 3'd2,
        CORE_ISSUE    = 3'd3,
        CORE_EXECUTE  = 3'd4,
        CORE_COMMIT   = 3'd5,
        CORE_DONE     = 3'd6
    } core_state_t;

    // --- Warp State ---
    typedef enum logic [2:0] {
        WARP_READY     = 3'd1,  // Can be scheduled
        WARP_FETCHING  = 3'd2,  // Waiting for I-cache
        WARP_ISSUED    = 3'd3,  // In pipeline
        WARP_STALLED   = 3'd4,  // Waiting on memory / barrier
        WARP_DONE      = 3'd5   // All threads returned
    } warp_state_t;

    // --- ALU Operation ---
    typedef enum logic [3:0] {
        ALU_ADD  = 4'd0,
        ALU_SUB  = 4'd1,
        ALU_AND  = 4'd2,
        ALU_OR   = 4'd3,
        ALU_XOR  = 4'd4,
        ALU_SLL  = 4'd5,
        ALU_SRL  = 4'd6,
        ALU_SRA  = 4'd7,
        ALU_SLT  = 4'd8,
        ALU_SLTU = 4'd9,
        ALU_MUL  = 4'd10,
        ALU_DIV  = 4'd11,
        ALU_REM  = 4'd12,
        ALU_LUI  = 4'd13,
        ALU_AUIPC= 4'd14,
        ALU_NOP  = 4'd15
    } alu_op_t;

    // --- Functional Unit Select ---
    typedef enum logic [2:0] {
        FU_ALU    = 3'd0,
        FU_LSU    = 3'd1,
        FU_SFU    = 3'd2,
        FU_TENSOR = 3'd3,
        FU_BRANCH = 3'd4,
        FU_NONE   = 3'd7
    } fu_select_t;

    // --- Decoded Instruction Bundle ---
    typedef struct packed {
        logic [INSTR_WIDTH-1:0]    raw_instr;
        logic [REG_ADDR_BITS-1:0]  rd;
        logic [REG_ADDR_BITS-1:0]  rs1;
        logic [REG_ADDR_BITS-1:0]  rs2;
        logic [DATA_WIDTH-1:0]     immediate;
        alu_op_t                   alu_op;
        fu_select_t                fu_sel;
        logic                      reg_write;
        logic                      mem_read;
        logic                      mem_write;
        logic                      is_branch;
        logic                      is_jump;
        logic                      use_imm;     // rs2 replaced by immediate
        logic                      is_ret;      // Kernel done
        logic [2:0]                funct3;
        logic [6:0]                funct7;
        logic [$clog2(NUM_WARPS)-1:0] warp_id;
        logic [THREADS_PER_WARP-1:0]  active_mask;
    } decoded_instr_t;

    // --- Memory Request ---
    typedef struct packed {
        logic                      valid;
        logic                      is_write;
        logic [ADDR_WIDTH-1:0]     addr;
        logic [DATA_WIDTH-1:0]     wdata;
        logic [3:0]                byte_en;
        logic [$clog2(NUM_WARPS)-1:0] warp_id;
        logic [REG_ADDR_BITS-1:0]  rd;       // Destination register for loads
    } mem_req_t;

    // --- Memory Response ---
    typedef struct packed {
        logic                      valid;
        logic [DATA_WIDTH-1:0]     rdata;
        logic [$clog2(NUM_WARPS)-1:0] warp_id;
        logic [REG_ADDR_BITS-1:0]  rd;
    } mem_rsp_t;

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    function automatic logic [DATA_WIDTH-1:0] sign_extend_12;
        input logic [11:0] imm12;
        sign_extend_12 = {{20{imm12[11]}}, imm12};
    endfunction

    function automatic logic [DATA_WIDTH-1:0] sign_extend_20;
        input logic [19:0] imm20;
        sign_extend_20 = {imm20, 12'b0};
    endfunction

endpackage
