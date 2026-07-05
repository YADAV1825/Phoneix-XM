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
async def test_matmul(dut):
    """ Integration Verification: Matrix Multiplication Real Benchmark """
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

    # 3. Assemble MatMul Program (2x2)
    # A unrolled 2x2 matrix multiplication for benchmarking
    # Matrix A at base 0, Matrix B at base 4, Output at 8
    # Since addresses are words, base A is 0, B is 4, C is 8
    asm_source = [
        "li x4, 0",     # base A
        "li x5, 16",    # base B (offset by 4 words = 16 bytes)
        "li x6, 32",    # base C (offset by 8 words = 32 bytes)
    ]
    # C00 = A00*B00 + A01*B10
    asm_source.extend([
        "lw x7, 0(x4)",
        "lw x8, 0(x5)",
        "mul x9, x7, x8",
        "lw x7, 4(x4)",
        "lw x8, 8(x5)",
        "mul x10, x7, x8",
        "add x11, x9, x10",
        "sw x11, 0(x6)",
    ])
    # C01 = A00*B01 + A01*B11
    asm_source.extend([
        "lw x7, 0(x4)",
        "lw x8, 4(x5)",
        "mul x9, x7, x8",
        "lw x7, 4(x4)",
        "lw x8, 12(x5)",
        "mul x10, x7, x8",
        "add x11, x9, x10",
        "sw x11, 4(x6)",
    ])
    # C10 = A10*B00 + A11*B10
    asm_source.extend([
        "lw x7, 8(x4)",
        "lw x8, 0(x5)",
        "mul x9, x7, x8",
        "lw x7, 12(x4)",
        "lw x8, 8(x5)",
        "mul x10, x7, x8",
        "add x11, x9, x10",
        "sw x11, 8(x6)",
    ])
    # C11 = A10*B01 + A11*B11
    asm_source.extend([
        "lw x7, 8(x4)",
        "lw x8, 4(x5)",
        "mul x9, x7, x8",
        "lw x7, 12(x4)",
        "lw x8, 12(x5)",
        "mul x10, x7, x8",
        "add x11, x9, x10",
        "sw x11, 12(x6)",
    ])
    asm_source.append("ret")
    
    program = assemble(asm_source)
    await load_program(dut, program)

    # 4. Load Data
    data_a = [1, 2, 3, 4]
    data_b = [1, 2, 3, 4]
    await load_data(dut, data_a + data_b + [0]*4)

    # 5. Launch Kernel & Count Cycles
    dut.host_kernel_pc.value = 0
    dut.host_kernel_num_blocks.value = 1
    dut.host_kernel_threads_per_block.value = 4 # 1 Warp (THREADS_PER_WARP = 4)
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
            
        # Track metrics by sampling internal signals
        sm0 = dut.tiles[0].tile_inst.sms[0].sm_inst
        
        try:
            if sm0.lsu.state.value != 0:
                lsu_active_cycles += 1
        except Exception:
            pass
            
        if sm0.all_warps_done.value == 0 and sm0.fetch_valid.value == 0:
            sched_stall_cycles += 1

        try:
            if sm0.exec_valid.value == 1:
                dut._log.info(f"Exec Cycle {cycles}: PC={sm0.exec_pc.value}, Instr={hex(sm0.exec_instr.value)}")
        except Exception:
            pass

        dut._log.info(f"Cycle {cycles}: all_warps_done={sm0.all_warps_done.value} sm_busy={sm0.sm_busy.value} block_done={sm0.block_done.value} warp0={sm0.warp_sched.warp_state[0].value}")

        if cycles > 2000:
            dut._log.error("Timeout! Kernel did not finish.")
            break

    lsu_util = (lsu_active_cycles / cycles) * 100 if cycles > 0 else 0
    stall_rate = (sched_stall_cycles / cycles) * 100 if cycles > 0 else 0
    
    dut._log.info(f"Completed MatMul in {cycles} cycles")
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
        # print(f"Index {i}: expected {expected}, got {val}")
