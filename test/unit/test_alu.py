import cocotb
from cocotb.triggers import Timer, RisingEdge
import random
import pytest

# Note: We need a cocotb test wrapper to use pytest parametrization efficiently with hardware.
# This test directly instantiates and stimulates the ALU module.

@cocotb.test()
async def alu_random_add_test(dut):
    """ ISA Verification: Randomized ADD testing """
    # Initialize inputs
    dut.alu_op.value = 0 # Assuming 0 is ADD based on pkg
    dut.active_mask.value = 0b1111 # All 4 lanes active
    
    for _ in range(100):
        # Generate random 32-bit integers for 4 lanes
        rs1 = [random.randint(0, 0xFFFFFFFF) for _ in range(4)]
        rs2 = [random.randint(0, 0xFFFFFFFF) for _ in range(4)]
        
        # Drive inputs to the 4 parallel lanes
        for i in range(4):
            dut.rs1[i].value = rs1[i]
            dut.rs2[i].value = rs2[i]
        
        # Wait for combinational logic to settle
        await Timer(1, units="ns")
        
        # Check outputs against Python golden math
        for i in range(4):
            assert int(dut.result[i].value) == (rs1[i] + rs2[i]) & 0xFFFFFFFF, f"Lane {i} ADD failed"

@cocotb.test()
async def alu_random_sub_test(dut):
    """ ISA Verification: Randomized SUB testing """
    dut.alu_op.value = 1 # Assuming 1 is SUB
    dut.active_mask.value = 0b1111 
    
    for _ in range(100):
        rs1 = [random.randint(0, 0xFFFFFFFF) for _ in range(4)]
        rs2 = [random.randint(0, 0xFFFFFFFF) for _ in range(4)]
        
        for i in range(4):
            dut.rs1[i].value = rs1[i]
            dut.rs2[i].value = rs2[i]
        
        await Timer(1, units="ns")
        
        for i in range(4):
            assert int(dut.result[i].value) == (rs1[i] - rs2[i]) & 0xFFFFFFFF, f"Lane {i} SUB failed"

@cocotb.test()
async def alu_random_logical_test(dut):
    """ ISA Verification: Randomized AND, OR, XOR testing """
    dut.active_mask.value = 0b1111 
    
    ops = [("AND", 2, lambda a, b: a & b), 
           ("OR", 3, lambda a, b: a | b), 
           ("XOR", 4, lambda a, b: a ^ b)]
           
    for op_name, op_code, op_func in ops:
        dut.alu_op.value = op_code
        
        for _ in range(20):
            rs1 = [random.randint(0, 0xFFFFFFFF) for _ in range(4)]
            rs2 = [random.randint(0, 0xFFFFFFFF) for _ in range(4)]
            
            for i in range(4):
                dut.rs1[i].value = rs1[i]
                dut.rs2[i].value = rs2[i]
            
            await Timer(1, units="ns")
            
            for i in range(4):
                assert int(dut.result[i].value) == op_func(rs1[i], rs2[i]) & 0xFFFFFFFF, f"Lane {i} {op_name} failed"

@cocotb.test()
async def alu_random_shift_test(dut):
    """ ISA Verification: Randomized SLL, SRL testing """
    dut.active_mask.value = 0b1111 
    
    ops = [("SLL", 5, lambda a, b: a << (b & 0x1F)), 
           ("SRL", 6, lambda a, b: a >> (b & 0x1F))]
           
    for op_name, op_code, op_func in ops:
        dut.alu_op.value = op_code
        
        for _ in range(20):
            rs1 = [random.randint(0, 0xFFFFFFFF) for _ in range(4)]
            rs2 = [random.randint(0, 31) for _ in range(4)] # Shift amount is 5 bits
            
            for i in range(4):
                dut.rs1[i].value = rs1[i]
                dut.rs2[i].value = rs2[i]
            
            await Timer(1, units="ns")
            
            for i in range(4):
                assert int(dut.result[i].value) == op_func(rs1[i], rs2[i]) & 0xFFFFFFFF, f"Lane {i} {op_name} failed"

