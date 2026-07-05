// ============================================================================
// Phoenix-XM GPU — Streaming Multiprocessor (SM) Top-Level
// ============================================================================
// The SM is the fundamental compute unit of Phoenix-XM.
// Each SM contains:
//   - Warp Scheduler (8 warps, round-robin)
//   - Instruction Fetch
//   - Instruction Decode
//   - SIMD ALU (THREADS_PER_WARP lanes)
//   - Non-blocking LSU
//   - Register File (32 regs × 32 bits per thread per warp)
//   - Shared Memory (4KB scratchpad)
//   - Tensor Core (4×4 MAC)
//
// Architectural comparison:
//   tiny-gpu core: 1 block at a time, no warp switching, 8-bit data, no cache
//   Phoenix SM:    8 warps, pipelined, 32-bit data, shared mem, tensor core
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_sm
    import phoenix_pkg::*;
#(
    parameter SM_ID = 0
) (
    input  wire clk,
    input  wire rst_n,

    // --- Block Dispatch Interface ---
    input  wire                            dispatch_valid,
    output logic                           dispatch_ready,
    input  wire [DATA_WIDTH-1:0]           dispatch_pc,         // Kernel entry point
    input  wire [DATA_WIDTH-1:0]           dispatch_block_id,
    input  wire [$clog2(THREADS_PER_WARP):0] dispatch_thread_count,

    // --- Completion ---
    output logic                           block_done,
    output logic [DATA_WIDTH-1:0]          block_done_id,

    // --- Instruction Memory Interface ---
    output logic                           imem_req_valid,
    output logic [ADDR_WIDTH-1:0]          imem_req_addr,
    input  wire                            imem_req_ready,
    input  wire                            imem_rsp_valid,
    input  wire [INSTR_WIDTH-1:0]          imem_rsp_data,

    // --- Data Memory Interface (to L1 cache or memory) ---
    output logic                           dmem_req_valid,
    output logic                           dmem_req_is_write,
    output logic [ADDR_WIDTH-1:0]          dmem_req_addr,
    output logic [DATA_WIDTH-1:0]          dmem_req_wdata,
    output logic [3:0]                     dmem_req_byte_en,
    input  wire                            dmem_req_ready,
    input  wire                            dmem_rsp_valid,
    input  wire [DATA_WIDTH-1:0]           dmem_rsp_rdata
);

    // ========================================================================
    // Internal Wires
    // ========================================================================

    // Warp Scheduler <-> Fetch
    logic                           sched_valid;
    logic [$clog2(NUM_WARPS)-1:0]   sched_warp_id;
    logic [ADDR_WIDTH-1:0]          sched_pc;
    logic [THREADS_PER_WARP-1:0]    sched_active_mask;
    logic                           pipeline_ready;

    // Fetch <-> Decode
    logic                           fetch_valid;
    logic [INSTR_WIDTH-1:0]         fetch_instr;
    logic [$clog2(NUM_WARPS)-1:0]   fetch_warp_id;
    logic [ADDR_WIDTH-1:0]          fetch_pc;
    logic [THREADS_PER_WARP-1:0]    fetch_active_mask;
    logic                           decode_ready;

    // Decoded instruction
    decoded_instr_t                 decoded;

    // Register File
    logic [DATA_WIDTH-1:0]          rs1_data [THREADS_PER_WARP];
    logic [DATA_WIDTH-1:0]          rs2_data [THREADS_PER_WARP];
    logic                           rf_wr_en;
    logic [$clog2(NUM_WARPS)-1:0]   rf_wr_warp;
    logic [REG_ADDR_BITS-1:0]       rf_wr_addr;
    logic [DATA_WIDTH-1:0]          rf_wr_data [THREADS_PER_WARP];
    logic [THREADS_PER_WARP-1:0]    rf_wr_mask;

    // ALU
    logic [DATA_WIDTH-1:0]          alu_operand_b [THREADS_PER_WARP];
    logic [DATA_WIDTH-1:0]          alu_result [THREADS_PER_WARP];
    logic [THREADS_PER_WARP-1:0]    alu_cmp_zero;
    logic [THREADS_PER_WARP-1:0]    alu_cmp_lt_s;
    logic [THREADS_PER_WARP-1:0]    alu_cmp_lt_u;

    // LSU
    logic                           lsu_stall_valid;
    logic [$clog2(NUM_WARPS)-1:0]   lsu_stall_warp;
    logic                           lsu_unstall_valid;
    logic [$clog2(NUM_WARPS)-1:0]   lsu_unstall_warp;
    logic                           lsu_wb_valid;
    logic [$clog2(NUM_WARPS)-1:0]   lsu_wb_warp;
    logic [REG_ADDR_BITS-1:0]       lsu_wb_rd;
    logic [DATA_WIDTH-1:0]          lsu_wb_data [THREADS_PER_WARP];
    logic [THREADS_PER_WARP-1:0]    lsu_wb_mask;
    logic                           lsu_req_ready;

    // Warp scheduler control
    logic                           retire_warp_valid;
    logic [$clog2(NUM_WARPS)-1:0]   retire_warp_id;
    logic                           pc_update_valid;
    logic [$clog2(NUM_WARPS)-1:0]   pc_update_warp;
    logic [ADDR_WIDTH-1:0]          pc_update_value;
    logic                           all_warps_done;
    
    // SFU Mask update (must be declared before warp_sched instance)
    logic                           sfu_mask_update_valid;
    logic [$clog2(NUM_WARPS)-1:0]   sfu_mask_update_warp;
    logic [THREADS_PER_WARP-1:0]    sfu_mask_update_value;

    // ========================================================================
    // Pipeline State (simplified execute stage register)
    // ========================================================================
    logic                           exec_valid;
    decoded_instr_t                 exec_decoded;
    logic [ADDR_WIDTH-1:0]          exec_pc;  // PC of the executing instruction
    logic [DATA_WIDTH-1:0]          exec_rs1 [THREADS_PER_WARP];
    logic [DATA_WIDTH-1:0]          exec_rs2 [THREADS_PER_WARP];

    // ========================================================================
    // Block Dispatch — Accept new blocks and launch warps
    // ========================================================================
    logic                           sm_busy;
    logic [DATA_WIDTH-1:0]          current_block_id;

    assign dispatch_ready = !sm_busy;
    assign sm_busy = !all_warps_done || exec_valid || fetch_valid;

    logic                           all_warps_done_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_done    <= 1'b0;
            block_done_id <= '0;
            current_block_id <= '0;
            all_warps_done_reg <= 1'b1;
        end else begin
            block_done <= 1'b0;
            all_warps_done_reg <= all_warps_done;

            if (all_warps_done && !all_warps_done_reg) begin
                block_done    <= 1'b1;
                block_done_id <= current_block_id;
            end

            if (dispatch_valid && dispatch_ready) begin
                current_block_id <= dispatch_block_id;
            end
        end
    end

    // Launch warp 0 on dispatch
    wire launch_valid = dispatch_valid && dispatch_ready;
    wire [$clog2(NUM_WARPS)-1:0] launch_warp_id = '0;
    wire [THREADS_PER_WARP-1:0] launch_mask =
        (dispatch_thread_count >= THREADS_PER_WARP) ?
            {THREADS_PER_WARP{1'b1}} :
            ((1 << dispatch_thread_count) - 1);

    // ========================================================================
    // Module Instantiations
    // ========================================================================

    // --- Warp Scheduler ---
    phoenix_warp_scheduler warp_sched (
        .clk(clk), .rst_n(rst_n),
        .launch_valid(launch_valid),
        .launch_warp_id(launch_warp_id),
        .launch_pc(dispatch_pc),
        .launch_mask(launch_mask),
        .pipeline_ready(pipeline_ready),
        .stall_warp_valid(lsu_stall_valid),
        .stall_warp_id(lsu_stall_warp),
        .unstall_warp_valid(lsu_unstall_valid),
        .unstall_warp_id(lsu_unstall_warp),
        .retire_warp_valid(retire_warp_valid),
        .retire_warp_id(retire_warp_id),
        .pc_update_valid(pc_update_valid),
        .pc_update_warp_id(pc_update_warp),
        .pc_update_value(pc_update_value),
        .exec_valid(exec_valid),
        .exec_warp_id(exec_decoded.warp_id),
        .exec_instr(exec_decoded.raw_instr),
        .exec_fu_sel(exec_decoded.fu_sel),
        .mask_update_valid(sfu_mask_update_valid),
        .mask_update_warp_id(sfu_mask_update_warp),
        .mask_update_value(sfu_mask_update_value),
        .sched_valid(sched_valid),
        .sched_warp_id(sched_warp_id),
        .sched_pc(sched_pc),
        .sched_active_mask(sched_active_mask),
        .all_warps_done(all_warps_done)
    );

    // --- Fetch Unit ---
    assign pipeline_ready = !fetch_valid || decode_ready;

    phoenix_fetch fetch_unit (
        .clk(clk), .rst_n(rst_n),
        .sched_valid(sched_valid),
        .sched_warp_id(sched_warp_id),
        .sched_pc(sched_pc),
        .sched_active_mask(sched_active_mask),
        .imem_req_valid(imem_req_valid),
        .imem_req_addr(imem_req_addr),
        .imem_req_ready(imem_req_ready),
        .imem_rsp_valid(imem_rsp_valid),
        .imem_rsp_data(imem_rsp_data),
        .fetch_valid(fetch_valid),
        .fetch_instr(fetch_instr),
        .fetch_warp_id(fetch_warp_id),
        .fetch_pc(fetch_pc),
        .fetch_active_mask(fetch_active_mask),
        .decode_ready(decode_ready)
    );

    // --- Decoder (combinational) ---
    phoenix_decode decoder (
        .instruction(fetch_instr),
        .warp_id(fetch_warp_id),
        .active_mask(fetch_active_mask),
        .pc(fetch_pc),
        .decoded(decoded)
    );

    // --- Issue / Execute Pipeline Register ---
    assign decode_ready = !exec_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exec_valid   <= 1'b0;
        end else begin
            if (fetch_valid && decode_ready) begin
                exec_valid   <= 1'b1;
                exec_decoded <= decoded;
                for (int i = 0; i < THREADS_PER_WARP; i++) begin
                    exec_rs1[i] <= rs1_data[i];
                    exec_rs2[i] <= rs2_data[i];
                end
                exec_pc <= fetch_pc;
            end else if (exec_valid) begin
                // Instruction completes in 1 cycle (for ALU)
                exec_valid <= 1'b0;
            end
        end
    end

    // --- Register File ---
    phoenix_regfile regfile (
        .clk(clk), .rst_n(rst_n),
        .rd_warp_a(fetch_valid ? fetch_warp_id : '0),
        .rd_addr_a(decoded.rs1),
        .rd_data_a(rs1_data),
        .rd_warp_b(fetch_valid ? fetch_warp_id : '0),
        .rd_addr_b(decoded.rs2),
        .rd_data_b(rs2_data),
        .wr_en(rf_wr_en),
        .wr_warp(rf_wr_warp),
        .wr_addr(rf_wr_addr),
        .wr_data(rf_wr_data),
        .wr_mask(rf_wr_mask)
    );

    // --- ALU ---
    // Select operand B: register or immediate
    always_comb begin
        for (int i = 0; i < THREADS_PER_WARP; i++) begin
            alu_operand_b[i] = exec_decoded.use_imm ? exec_decoded.immediate : exec_rs2[i];
        end
    end

    phoenix_alu alu (
        .rs1(exec_rs1),
        .rs2(alu_operand_b),
        .pc_in(exec_decoded.raw_instr),  // Will be replaced with actual PC
        .active_mask(exec_decoded.active_mask),
        .alu_op(exec_decoded.alu_op),
        .result(alu_result),
        .cmp_zero(alu_cmp_zero),
        .cmp_lt_s(alu_cmp_lt_s),
        .cmp_lt_u(alu_cmp_lt_u)
    );

    // --- SFU ---
    logic sfu_done;
    logic sfu_stall_req;

    phoenix_sfu sfu (
        .clk(clk), .rst_n(rst_n),
        .valid(exec_valid && exec_decoded.fu_sel == FU_SFU),
        .funct3(exec_decoded.funct3),
        .warp_id(exec_decoded.warp_id),
        .active_mask(exec_decoded.active_mask),
        .rs1_data(exec_rs1),
        .rs2_data(exec_rs2),
        .done(sfu_done),
        .stall_req(sfu_stall_req),
        .mask_update_valid(sfu_mask_update_valid),
        .mask_update_warp_id(sfu_mask_update_warp),
        .mask_update_value(sfu_mask_update_value)
    );

    // --- LSU ---
    phoenix_lsu lsu (
        .clk(clk), .rst_n(rst_n),
        .req_valid(exec_valid && (exec_decoded.mem_read || exec_decoded.mem_write)),
        .req_is_store(exec_decoded.mem_write),
        .req_addr(alu_result),  // Address = rs1 + imm (computed by ALU)
        .req_wdata(exec_rs2),
        .req_mask(exec_decoded.active_mask),
        .req_funct3(exec_decoded.funct3),
        .req_warp_id(exec_decoded.warp_id),
        .req_rd(exec_decoded.rd),
        .req_ready(lsu_req_ready),
        .mem_req_valid(dmem_req_valid),
        .mem_req_is_write(dmem_req_is_write),
        .mem_req_addr(dmem_req_addr),
        .mem_req_wdata(dmem_req_wdata),
        .mem_req_byte_en(dmem_req_byte_en),
        .mem_req_ready(dmem_req_ready),
        .mem_rsp_valid(dmem_rsp_valid),
        .mem_rsp_rdata(dmem_rsp_rdata),
        .wb_valid(lsu_wb_valid),
        .wb_warp_id(lsu_wb_warp),
        .wb_rd(lsu_wb_rd),
        .wb_data(lsu_wb_data),
        .wb_mask(lsu_wb_mask),
        .stall_warp_valid(lsu_stall_valid),
        .stall_warp_id(lsu_stall_warp),
        .unstall_warp_valid(lsu_unstall_valid),
        .unstall_warp_id(lsu_unstall_warp)
    );

    // ========================================================================
    // Writeback Mux — ALU results or LSU load results
    // ========================================================================
    always_comb begin
        rf_wr_en   = 1'b0;
        rf_wr_warp = '0;
        rf_wr_addr = '0;
        rf_wr_mask = '0;
        for (int i = 0; i < THREADS_PER_WARP; i++)
            rf_wr_data[i] = '0;

        if (lsu_wb_valid) begin
            // LSU writeback has priority (it unstalls a warp)
            rf_wr_en   = 1'b1;
            rf_wr_warp = lsu_wb_warp;
            rf_wr_addr = lsu_wb_rd;
            rf_wr_mask = lsu_wb_mask;
            for (int i = 0; i < THREADS_PER_WARP; i++)
                rf_wr_data[i] = lsu_wb_data[i];
        end else if (exec_valid && exec_decoded.reg_write && exec_decoded.fu_sel == FU_ALU) begin
            // ALU writeback
            rf_wr_en   = 1'b1;
            rf_wr_warp = exec_decoded.warp_id;
            rf_wr_addr = exec_decoded.rd;
            rf_wr_mask = exec_decoded.active_mask;
            for (int i = 0; i < THREADS_PER_WARP; i++)
                rf_wr_data[i] = alu_result[i];
        end
    end

    // ========================================================================
    // Branch Resolution & Warp Retirement
    // ========================================================================
    assign retire_warp_valid = exec_valid && exec_decoded.is_ret;
    assign retire_warp_id    = exec_decoded.warp_id;

    // ========================================================================
    // Branch Resolution Unit
    // ========================================================================
    logic branch_taken;
    always_comb begin
        branch_taken = 1'b0;
        if (exec_valid && exec_decoded.is_branch) begin
            // Use lane 0 comparison (all lanes execute same branch)
            case (exec_decoded.funct3)
                3'b000: branch_taken =  alu_cmp_zero[0];                     // BEQ
                3'b001: branch_taken = !alu_cmp_zero[0];                     // BNE
                3'b100: branch_taken =  alu_cmp_lt_s[0];                     // BLT
                3'b101: branch_taken = !alu_cmp_lt_s[0] || alu_cmp_zero[0];  // BGE
                3'b110: branch_taken =  alu_cmp_lt_u[0];                     // BLTU
                3'b111: branch_taken = !alu_cmp_lt_u[0] || alu_cmp_zero[0];  // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

    assign pc_update_valid = branch_taken;
    assign pc_update_warp  = exec_decoded.warp_id;
    assign pc_update_value = exec_pc + exec_decoded.immediate;

endmodule
