import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import sys
import os

sys.path.append(os.getcwd())
from sw.assembler.phoenix_asm import assemble

async def load_program(dut, program):
    dut.host_imem_wr_en.value = 1
    dut.host_imem_tile_id.value = 0
    for i, inst in enumerate(program):
        dut.host_imem_wr_addr.value = i
        dut.host_imem_wr_data.value = inst
        await RisingEdge(dut.clk)
    dut.host_imem_wr_en.value = 0
    await RisingEdge(dut.clk)

async def load_data(dut, data_list):
    dut.host_dmem_wr_en.value = 1
    dut.host_dmem_tile_id.value = 0
    for i, data in enumerate(data_list):
        dut.host_dmem_wr_addr.value = i
        dut.host_dmem_wr_data.value = data
        await RisingEdge(dut.clk)
    dut.host_dmem_wr_en.value = 0
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_matmul_looped(dut):
    """ Benchmark: Looped 2x2 MatMul (apples-to-apples with tiny-gpu looped) """
    # 1. Start Clock
    cocotb.start_soon(Clock(dut.clk, 2, units="ns").start())

    # 2. Reset
    dut.rst_n.value = 0
    dut.host_kernel_valid.value = 0
    dut.host_imem_wr_en.value = 0
    dut.host_dmem_wr_en.value = 0
    dut.host_dmem_rd_en.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # 3. Assemble Looped MatMul Program (2x2)
    # Equivalent to tiny-gpu's looped approach:
    #   For each output element (i,j), loop over k: C[i][j] += A[i][k] * B[k][j]
    # Single thread computes all 4 elements using 3 nested loops.
    # Memory layout: A at word 0..3, B at word 4..7, C at word 8..11
    # A[i][j] at address (base_A + (i*N + j) * 4) bytes
    asm_source = [
        "li x20, 2",        # N = 2
        "li x4, 0",         # base A (byte addr)
        "li x5, 16",        # base B (4 words * 4 bytes)
        "li x6, 32",        # base C (8 words * 4 bytes)
        "li x21, 0",        # i = 0 (row loop counter)
        # outer_loop:        (row i)
        "outer_loop:",
        "li x22, 0",        # j = 0 (col loop counter)
        # col_loop:          (col j)
        "col_loop:",
        "li x23, 0",        # acc = 0
        "li x24, 0",        # k = 0
        # k_loop:
        "k_loop:",
        # addr_A = base_A + (i*N + k) * 4
        "mul x10, x21, x20",    # i * N
        "add x10, x10, x24",    # + k
        "slli x10, x10, 2",     # * 4 (byte offset)
        "add x10, x10, x4",     # + base_A
        "lw x11, 0(x10)",       # A[i][k]
        # addr_B = base_B + (k*N + j) * 4
        "mul x12, x24, x20",    # k * N
        "add x12, x12, x22",    # + j
        "slli x12, x12, 2",     # * 4
        "add x12, x12, x5",     # + base_B
        "lw x13, 0(x12)",       # B[k][j]
        # acc += A[i][k] * B[k][j]
        "mul x14, x11, x13",
        "add x23, x23, x14",
        # k++
        "addi x24, x24, 1",
        "blt x24, x20, k_loop",  # if k < N, loop
        # Store C[i][j]
        # addr_C = base_C + (i*N + j) * 4
        "mul x10, x21, x20",    # i * N
        "add x10, x10, x22",    # + j
        "slli x10, x10, 2",     # * 4
        "add x10, x10, x6",     # + base_C
        "sw x23, 0(x10)",       # C[i][j] = acc
        # j++
        "addi x22, x22, 1",
        "blt x22, x20, col_loop", # if j < N, loop
        # i++
        "addi x21, x21, 1",
        "blt x21, x20, outer_loop", # if i < N, loop
        "ret",
    ]

    program = assemble(asm_source)
    await load_program(dut, program)

    # 4. Load Data (same matrices as tiny-gpu: A=[[1,2],[3,4]], B=[[1,2],[3,4]])
    data_a = [1, 2, 3, 4]
    data_b = [1, 2, 3, 4]
    await load_data(dut, data_a + data_b + [0]*4)

    # 5. Launch Kernel
    dut.host_kernel_pc.value = 0
    dut.host_kernel_num_blocks.value = 1
    dut.host_kernel_threads_per_block.value = 4
    dut.host_kernel_tile_id.value = 0

    dut.host_kernel_valid.value = 1
    await RisingEdge(dut.clk)
    dut.host_kernel_valid.value = 0

    # 6. Wait for Completion & Count Cycles
    cycles = 0
    lsu_active_cycles = 0
    sched_stall_cycles = 0

    while True:
        await RisingEdge(dut.clk)
        cycles += 1

        if dut.host_kernel_done.value == 1:
            break

        sm0 = dut.tiles[0].tile_inst.sms[0].sm_inst

        try:
            if sm0.lsu.state.value != 0:
                lsu_active_cycles += 1
        except Exception:
            pass

        if sm0.all_warps_done.value == 0 and sm0.fetch_valid.value == 0:
            sched_stall_cycles += 1

        dut._log.info(f"Cycle {cycles}: all_warps_done={sm0.all_warps_done.value} sm_busy={sm0.sm_busy.value} block_done={sm0.block_done.value} warp0={sm0.warp_sched.warp_state[0].value}")

        if cycles > 3000:
            dut._log.error("Timeout! Kernel did not finish.")
            break

    lsu_util = (lsu_active_cycles / cycles) * 100 if cycles > 0 else 0
    stall_rate = (sched_stall_cycles / cycles) * 100 if cycles > 0 else 0

    dut._log.info(f"Completed MatMulLooped in {cycles} cycles")
    dut._log.info(f"LSU Active: {lsu_active_cycles} cycles ({lsu_util:.1f}%)")
    dut._log.info(f"Scheduler Stalled: {sched_stall_cycles} cycles ({stall_rate:.1f}%)")

    # 7. Verification
    dut.host_dmem_rd_en.value = 1
    dut.host_dmem_rd_tile_id.value = 0
    expected_results = [
        1*1 + 2*3, # 7
        1*2 + 2*4, # 10
        3*1 + 4*3, # 15
        3*2 + 4*4, # 22
    ]
    for i in range(4):
        dut.host_dmem_rd_addr.value = 8 + i
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        val = int(dut.host_dmem_rd_data.value)
        expected = expected_results[i]
        dut._log.info(f"C[{i}]: expected={expected}, got={val}")
