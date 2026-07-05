#!/usr/bin/env python3
"""
Phoenix-XM GPU — Assembler
===========================
Translates human-readable RISC-V-style assembly into 32-bit machine code.
Supports all Phoenix ISA instructions including GPGPU extensions.

Usage:
    from phoenix_asm import assemble
    binary = assemble([
        "addi x1, x0, 42",
        "add  x2, x1, x1",
        "sw   x2, 0(x0)",
        "ret",
    ])
"""

import re
from typing import List, Dict, Optional, Tuple

# =============================================================================
# Register name mapping
# =============================================================================
REG_MAP = {f"x{i}": i for i in range(32)}
REG_MAP.update({
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15,
    "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23,
    "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
})

# =============================================================================
# Opcode definitions
# =============================================================================
OP_LUI    = 0b0110111
OP_AUIPC  = 0b0010111
OP_JAL    = 0b1101111
OP_JALR   = 0b1100111
OP_BRANCH = 0b1100011
OP_LOAD   = 0b0000011
OP_STORE  = 0b0100011
OP_IMM    = 0b0010011
OP_REG    = 0b0110011
OP_GPU    = 0b0001011

F7_SUB    = 0b0100000
F7_MULDIV = 0b0000001

def _parse_reg(s: str) -> int:
    s = s.strip().rstrip(",")
    if s in REG_MAP:
        return REG_MAP[s]
    raise ValueError(f"Unknown register: {s}")

def _parse_imm(s: str) -> int:
    s = s.strip().rstrip(",")
    if s.startswith("0x") or s.startswith("0X"):
        return int(s, 16)
    if s.startswith("0b") or s.startswith("0B"):
        return int(s, 2)
    return int(s)

def _parse_mem(s: str) -> Tuple[int, int]:
    """Parse 'offset(reg)' -> (offset, reg_num)"""
    m = re.match(r'(-?\d+)\((\w+)\)', s.strip())
    if m:
        return _parse_imm(m.group(1)), _parse_reg(m.group(2))
    raise ValueError(f"Bad memory operand: {s}")

def _bits(val: int, width: int) -> int:
    """Truncate to width bits (handles negative via two's complement)."""
    return val & ((1 << width) - 1)

# =============================================================================
# Instruction encoding
# =============================================================================
def _encode_r(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def _encode_i(imm: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    return (_bits(imm, 12) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def _encode_s(imm: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
    imm12 = _bits(imm, 12)
    return ((imm12 >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm12 & 0x1F) << 7) | opcode

def _encode_b(imm: int, rs2: int, rs1: int, funct3: int) -> int:
    i = _bits(imm, 13)
    return (((i >> 12) & 1) << 31) | (((i >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (((i >> 1) & 0xF) << 8) | (((i >> 11) & 1) << 7) | OP_BRANCH

def _encode_u(imm: int, rd: int, opcode: int) -> int:
    return (_bits(imm >> 12, 20) << 12) | (rd << 7) | opcode

def _encode_j(imm: int, rd: int) -> int:
    i = _bits(imm, 21)
    return (((i >> 20) & 1) << 31) | (((i >> 1) & 0x3FF) << 21) | (((i >> 11) & 1) << 20) | \
           (((i >> 12) & 0xFF) << 12) | (rd << 7) | OP_JAL


# =============================================================================
# Assembler
# =============================================================================
def assemble_line(line: str, labels: Dict[str, int], pc: int) -> Optional[int]:
    """Assemble a single line of assembly into a 32-bit integer."""
    line = line.strip()
    if not line or line.startswith("#") or line.startswith("//"):
        return None
    if line.endswith(":"):
        return None  # Label

    parts = re.split(r'[,\s]+', line)
    mnemonic = parts[0].lower()

    # =========================================================================
    # R-type
    # =========================================================================
    if mnemonic == "add":
        return _encode_r(0, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b000, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "sub":
        return _encode_r(F7_SUB, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b000, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "mul":
        return _encode_r(F7_MULDIV, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b000, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "div":
        return _encode_r(F7_MULDIV, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b100, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "rem":
        return _encode_r(F7_MULDIV, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b110, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "and":
        return _encode_r(0, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b111, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "or":
        return _encode_r(0, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b110, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "xor":
        return _encode_r(0, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b100, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "sll":
        return _encode_r(0, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b001, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "srl":
        return _encode_r(0, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b101, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "sra":
        return _encode_r(F7_SUB, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b101, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "slt":
        return _encode_r(0, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b010, _parse_reg(parts[1]), OP_REG)
    if mnemonic == "sltu":
        return _encode_r(0, _parse_reg(parts[3]), _parse_reg(parts[2]), 0b011, _parse_reg(parts[1]), OP_REG)

    # =========================================================================
    # I-type (ALU immediate)
    # =========================================================================
    if mnemonic == "addi":
        return _encode_i(_parse_imm(parts[3]), _parse_reg(parts[2]), 0b000, _parse_reg(parts[1]), OP_IMM)
    if mnemonic == "andi":
        return _encode_i(_parse_imm(parts[3]), _parse_reg(parts[2]), 0b111, _parse_reg(parts[1]), OP_IMM)
    if mnemonic == "ori":
        return _encode_i(_parse_imm(parts[3]), _parse_reg(parts[2]), 0b110, _parse_reg(parts[1]), OP_IMM)
    if mnemonic == "xori":
        return _encode_i(_parse_imm(parts[3]), _parse_reg(parts[2]), 0b100, _parse_reg(parts[1]), OP_IMM)
    if mnemonic == "slti":
        return _encode_i(_parse_imm(parts[3]), _parse_reg(parts[2]), 0b010, _parse_reg(parts[1]), OP_IMM)
    if mnemonic == "sltiu":
        return _encode_i(_parse_imm(parts[3]), _parse_reg(parts[2]), 0b011, _parse_reg(parts[1]), OP_IMM)
    if mnemonic == "slli":
        return _encode_i(_parse_imm(parts[3]) & 0x1F, _parse_reg(parts[2]), 0b001, _parse_reg(parts[1]), OP_IMM)
    if mnemonic == "srli":
        return _encode_i(_parse_imm(parts[3]) & 0x1F, _parse_reg(parts[2]), 0b101, _parse_reg(parts[1]), OP_IMM)
    if mnemonic == "srai":
        return _encode_i((_parse_imm(parts[3]) & 0x1F) | 0x400, _parse_reg(parts[2]), 0b101, _parse_reg(parts[1]), OP_IMM)

    # =========================================================================
    # Load/Store
    # =========================================================================
    if mnemonic in ("lw", "lh", "lb", "lhu", "lbu"):
        funct3_map = {"lw": 0b010, "lh": 0b001, "lb": 0b000, "lhu": 0b101, "lbu": 0b100}
        off, base = _parse_mem(parts[2])
        return _encode_i(off, base, funct3_map[mnemonic], _parse_reg(parts[1]), OP_LOAD)

    if mnemonic in ("sw", "sh", "sb"):
        funct3_map = {"sw": 0b010, "sh": 0b001, "sb": 0b000}
        off, base = _parse_mem(parts[2])
        return _encode_s(off, _parse_reg(parts[1]), base, funct3_map[mnemonic], OP_STORE)

    # =========================================================================
    # Branch
    # =========================================================================
    if mnemonic in ("beq", "bne", "blt", "bge", "bltu", "bgeu"):
        funct3_map = {"beq": 0b000, "bne": 0b001, "blt": 0b100, "bge": 0b101, "bltu": 0b110, "bgeu": 0b111}
        target = parts[3].strip()
        if target in labels:
            offset = labels[target] - pc
        else:
            offset = _parse_imm(target)
        return _encode_b(offset, _parse_reg(parts[2]), _parse_reg(parts[1]), funct3_map[mnemonic])

    # =========================================================================
    # U-type
    # =========================================================================
    if mnemonic == "lui":
        return _encode_u(_parse_imm(parts[2]), _parse_reg(parts[1]), OP_LUI)
    if mnemonic == "auipc":
        return _encode_u(_parse_imm(parts[2]), _parse_reg(parts[1]), OP_AUIPC)

    # =========================================================================
    # Jump
    # =========================================================================
    if mnemonic == "jal":
        target = parts[2].strip() if len(parts) > 2 else parts[1].strip()
        rd = _parse_reg(parts[1]) if len(parts) > 2 else 1
        if target in labels:
            offset = labels[target] - pc
        else:
            offset = _parse_imm(target)
        return _encode_j(offset, rd)

    # =========================================================================
    # Pseudo-instructions
    # =========================================================================
    if mnemonic == "nop":
        return _encode_i(0, 0, 0b000, 0, OP_IMM)  # addi x0, x0, 0
    if mnemonic == "li":
        return _encode_i(_parse_imm(parts[2]), 0, 0b000, _parse_reg(parts[1]), OP_IMM)
    if mnemonic == "mv":
        return _encode_i(0, _parse_reg(parts[2]), 0b000, _parse_reg(parts[1]), OP_IMM)

    # =========================================================================
    # GPU Extensions
    # =========================================================================
    if mnemonic == "ret":
        return (_parse_reg("x0") << 15) | (0b111 << 12) | OP_GPU

    raise ValueError(f"Unknown instruction: {mnemonic}")


def assemble(lines: List[str]) -> List[int]:
    """Two-pass assembler: first pass collects labels, second pass encodes."""
    # Pass 1: collect labels
    labels: Dict[str, int] = {}
    pc = 0
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        if line.endswith(":"):
            labels[line[:-1]] = pc
        else:
            pc += 4

    # Pass 2: assemble
    result = []
    pc = 0
    for line in lines:
        encoded = assemble_line(line, labels, pc)
        if encoded is not None:
            result.append(encoded)
            pc += 4

    return result


if __name__ == "__main__":
    # Quick test
    program = assemble([
        "addi x1, x0, 10",   # x1 = 10
        "addi x2, x0, 20",   # x2 = 20
        "add  x3, x1, x2",   # x3 = 30
        "sw   x3, 0(x0)",    # mem[0] = 30
        "ret",
    ])
    for i, instr in enumerate(program):
        print(f"  [{i}] 0x{instr:08X}  ({instr:032b})")
