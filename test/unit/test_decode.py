import cocotb
from cocotb.triggers import Timer
import random

# Opcodes based on standard RISC-V RV32I
OP_LUI    = 0x37
OP_AUIPC  = 0x17
OP_JAL    = 0x6F
OP_JALR   = 0x67
OP_BRANCH = 0x63
OP_LOAD   = 0x03
OP_STORE  = 0x23
OP_IMM    = 0x13
OP_REG    = 0x33

# Custom Phoenix Opcodes (Must match phoenix_pkg.sv)
OP_GPU    = 0x0B
OP_TENSOR = 0x2B

# FU selections
FU_ALU    = 0
FU_LSU    = 1
FU_SFU    = 2
FU_TENSOR = 3
FU_BRANCH = 4

@cocotb.test()
async def test_decode_add(dut):
    """ ISA Verification: Verify standard ADD decoding """
    # Build a standard R-type instruction: ADD x1, x2, x3
    # funct7 = 0x00, rs2 = x3(3), rs1 = x2(2), funct3 = 0x0, rd = x1(1), opcode = 0x33
    inst = (0x00 << 25) | (3 << 20) | (2 << 15) | (0 << 12) | (1 << 7) | OP_REG
    
    dut.instruction.value = inst
    await Timer(1, units="ns")
    
    assert dut.dbg_fu_sel.value == FU_ALU
    assert dut.dbg_alu_op.value == 0 # ALU_ADD
    assert dut.dbg_use_imm.value == 0
    assert dut.dbg_reg_write.value == 1

@cocotb.test()
async def test_decode_load(dut):
    """ ISA Verification: Verify LW decoding """
    # Build I-type instruction: LW x5, 16(x10)
    # imm = 16, rs1 = x10(10), funct3 = 0x2, rd = x5(5), opcode = 0x03
    inst = (16 << 20) | (10 << 15) | (2 << 12) | (5 << 7) | OP_LOAD
    
    dut.instruction.value = inst
    await Timer(1, units="ns")
    
    assert dut.dbg_fu_sel.value == FU_LSU
    assert dut.dbg_mem_read.value == 1
    assert dut.dbg_mem_write.value == 0
    assert dut.dbg_reg_write.value == 1

@cocotb.test()
async def test_decode_tmma(dut):
    """ ISA Verification: Verify Tensor TMMA decoding """
    # Build custom instruction: TMMA (funct3 = 0x00 inside OP_TENSOR)
    inst = (0x00 << 25) | (0 << 20) | (0 << 15) | (0 << 12) | (0 << 7) | OP_TENSOR
    
    dut.instruction.value = inst
    await Timer(1, units="ns")
    
    assert dut.dbg_fu_sel.value == FU_TENSOR
    assert dut.dbg_reg_write.value == 1 # TMMA writes back to RF
