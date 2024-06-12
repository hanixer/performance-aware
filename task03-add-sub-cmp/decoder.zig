const std = @import("std");
const fmt = std.fmt;
const maxInt = std.math.maxInt;

const Reg = enum {
    AX,
    BX,
    CX,
    DX,
    SP,
    BP,
    SI,
    DI,
    AL,
    BL,
    CL,
    DL,
    AH,
    BH,
    CH,
    DH,
};

const Opcode = enum {
    MOV,
    ADD,
    SUB,
    CMP,
    JA,
    JB,
    JBE,
    JCXZ,
    JE,
    JG,
    JL,
    JLE,
    JNB,
    JNE,
    JNL,
    JNO,
    JNP,
    JNS,
    JO,
    JP,
    JS,
    JZ,
    JNZ,
    LOOP,
    LOOPNZ,
    LOOPZ,
};

const DecoderState = struct {
    bytes: []u8,
    i: usize,
    strbuf: [128]u8 = undefined,
    out: std.fs.File.Writer,
};

const RegMemory = struct {
    reg1: Reg = Reg.AX, // This should be always available
    reg2: ?Reg = null,
    is_disp8: bool = false,
    is_disp16: bool = false,
    disp: u16 = 0,
    reg_only: bool = false,
    is_word: bool = false,
    direct_address: bool = false,
};

const OperandsMode = enum {
    RegMemoryAndReg,
    ImmediateToRegMemory,
    IpIncrement,
};

const Instruction = struct {
    opcode: Opcode = Opcode.ADD,
    reg: Reg = Reg.AH,
    reg_memory: RegMemory = .{},
    immediate: u16 = 0,
    ip_increment: i8 = 0,
    destination_in_reg: bool = false,
    operands_mode: OperandsMode = OperandsMode.ImmediateToRegMemory,
};

fn printRegMemory(reg_memory: RegMemory, writer: std.fs.File.Writer, specify_width: bool) !void {
    const width_specifier: []const u8 = if (!specify_width)
        ""
    else if (reg_memory.is_word)
        "word "
    else
        "byte ";

    if (reg_memory.direct_address) {
        try writer.print("{s}[{d}]", .{ width_specifier, reg_memory.disp });
    } else if (reg_memory.is_disp8 or reg_memory.is_disp16) {
        if (reg_memory.reg2) |reg2| {
            try writer.print("{s}[{s} + {s} + {d}]", .{ width_specifier, regToString(reg_memory.reg1), regToString(reg2), reg_memory.disp });
        } else {
            try writer.print("{s}[{s} + {d}]", .{ width_specifier, regToString(reg_memory.reg1), reg_memory.disp });
        }
    } else if (reg_memory.reg2) |reg2| {
        try writer.print("{s}[{s} + {s}]", .{ width_specifier, regToString(reg_memory.reg1), regToString(reg2) });
    } else if (reg_memory.reg_only) {
        try writer.print("{s}", .{regToString(reg_memory.reg1)});
    } else {
        try writer.print("{s}[{s}]", .{ width_specifier, regToString(reg_memory.reg1) });
    }

    // @panic("Unhandled case...");

}

fn printInstruction(instruction: Instruction, writer: std.fs.File.Writer) !void {
    try writer.print("{s} ", .{opcodeToString(instruction.opcode)});
    switch (instruction.operands_mode) {        
        OperandsMode.IpIncrement => {
            const sign = if (instruction.ip_increment >= 0) "+" else "";
            try writer.print("${s}{d}", .{ sign, instruction.ip_increment });
        },
        OperandsMode.ImmediateToRegMemory => {
            try printRegMemory(instruction.reg_memory, writer, !instruction.reg_memory.reg_only);
            try writer.print(", {d}", .{instruction.immediate});
        },
        OperandsMode.RegMemoryAndReg => {
            const reg_string = regToString(instruction.reg);
            if (instruction.destination_in_reg) {
                try writer.print("{s}, ", .{reg_string});
                try printRegMemory(instruction.reg_memory, writer, false);
            } else {
                try printRegMemory(instruction.reg_memory, writer, false);
                try writer.print(", {s}", .{reg_string});
            }
        },
    }
    try writer.print("\n", .{});
}

pub fn main() !void {
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const args = try std.process.argsAlloc(gpa.backing_allocator);
    const file = try std.fs.cwd().openFile(args[1], .{});

    const bytes = try file.reader().readAllAlloc(gpa.backing_allocator, maxInt(i32));
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\nbits 16\n\n", .{});

    var state = DecoderState{
        .bytes = bytes,
        .i = 0,
        .out = stdout,
    };

    while (state.i < state.bytes.len) {
        const instruction = decodeInstruction(state.bytes, &state.i);
        try printInstruction(instruction, stdout);
    }
}

fn decodeInstruction(bytes: []u8, ip: *usize) Instruction {
    const byte = bytes[ip.*];

    switch (byte & 0b11111100) {
        0b10001000 => return decodeRegMemoryAndRegInstruction(Opcode.MOV, bytes, ip),
        0b00000000 => return decodeRegMemoryAndRegInstruction(Opcode.ADD, bytes, ip),
        0b00101000 => return decodeRegMemoryAndRegInstruction(Opcode.SUB, bytes, ip),
        0b00111000 => return decodeRegMemoryAndRegInstruction(Opcode.CMP, bytes, ip),
        0b10000000 => return decodeArithmeticImmediate(bytes, ip),
        0b00000100 => return decodeArithmeticImmediateToAccum(Opcode.ADD, bytes, ip),
        0b00101100 => return decodeArithmeticImmediateToAccum(Opcode.SUB, bytes, ip),
        0b00111100 => return decodeArithmeticImmediateToAccum(Opcode.CMP, bytes, ip),
        else => {},
    }

    if ((byte & 0b11110000) == 0xB0) {
        return decodeMovImmediateToReg(bytes, ip);
    }

    switch (byte) {
        0x70 => return decodeJump(Opcode.JO, bytes, ip),
        0x71 => return decodeJump(Opcode.JNO, bytes, ip),
        0x72 => return decodeJump(Opcode.JB, bytes, ip),
        0x73 => return decodeJump(Opcode.JNB, bytes, ip),
        0x74 => return decodeJump(Opcode.JZ, bytes, ip),
        0x75 => return decodeJump(Opcode.JNZ, bytes, ip),
        0x76 => return decodeJump(Opcode.JBE, bytes, ip),
        0x77 => return decodeJump(Opcode.JA, bytes, ip),
        0x78 => return decodeJump(Opcode.JS, bytes, ip),
        0x79 => return decodeJump(Opcode.JNS, bytes, ip),
        0x7A => return decodeJump(Opcode.JP, bytes, ip),
        0x7B => return decodeJump(Opcode.JNP, bytes, ip),
        0x7C => return decodeJump(Opcode.JL, bytes, ip),
        0x7D => return decodeJump(Opcode.JNL, bytes, ip),
        0x7E => return decodeJump(Opcode.JLE, bytes, ip),
        0x7F => return decodeJump(Opcode.JG, bytes, ip),
        0xE0 => return decodeJump(Opcode.LOOPNZ, bytes, ip),
        0xE1 => return decodeJump(Opcode.LOOPZ, bytes, ip),
        0xE2 => return decodeJump(Opcode.LOOP, bytes, ip),
        0xE3 => return decodeJump(Opcode.JCXZ, bytes, ip),
        else => @panic("Unrecognized instruction")
    }

    @panic("Unrecognized instruction");
}

// Arithmetic reg/memory with register to either
// MOV reg/memory and register to either
fn decodeRegMemoryAndRegInstruction(opcode: Opcode, bytes: []u8, ip: *usize) Instruction {
    const byte1 = bytes[ip.*];
    const byte2 = bytes[ip.* + 1];
    const w = (byte1 & 1) == 1;
    const d = (byte1 & 0b10) == 0b10;
    const mod = (byte2 >> 6) & 0b11;
    const reg_raw = (byte2 >> 3) & 0b111;
    const rm = byte2 & 7;
    ip.* += 2;

    const reg = chooseReg(reg_raw, w);
    const reg_memory = getRegMemory(rm, mod, w, bytes, ip);

    return Instruction{ .opcode = opcode, .reg = reg, .reg_memory = reg_memory, .destination_in_reg = d, .operands_mode = OperandsMode.RegMemoryAndReg };
}

fn decodeMovImmediateToReg(bytes: []u8, ip: *usize) Instruction {
    const byte1 = bytes[ip.*];
    const w = (byte1 & 8) == 8;
    const reg = chooseReg(byte1 & 0b111, w);
    ip.* += 1;

    var immediate: u16 = undefined;
    if (w) {
        immediate = readU16(bytes, ip.*);
        ip.* += 2;
    } else {
        immediate = bytes[ip.*];
        ip.* += 1;
    }

    return Instruction{
        .opcode = Opcode.MOV,
        .immediate = immediate,
        .reg_memory = RegMemory{
            .reg1 = reg,
            .reg_only = true,
        },
        .operands_mode = OperandsMode.ImmediateToRegMemory,
    };
}

// ADD/SUB/CMP Immediate to register/memory.
fn decodeArithmeticImmediate(bytes: []u8, ip: *usize) Instruction {
    const byte1 = bytes[ip.*];
    const byte2 = bytes[ip.* + 1];
    const w = (byte1 & 1) == 1;
    const s = (byte1 & 0b10) == 0b10;
    const mod = (byte2 >> 6) & 0b11;
    const rm = byte2 & 7;

    ip.* += 2;

    const reg_memory = getRegMemory(rm, mod, w, bytes, ip);

    var immediate: u16 = undefined;
    if (!s and w) {
        immediate = readU16(bytes, ip.*);
        ip.* += 2;
    } else {
        immediate = bytes[ip.*];
        ip.* += 1;
    }

    const op_part = (byte2 & 0b00111000) >> 3;
    const opcode =
        if (op_part == 0b101) Opcode.SUB else if (op_part == 0b111) Opcode.CMP else Opcode.ADD;

    return Instruction{
        .opcode = opcode,
        .reg_memory = reg_memory,
        .immediate = immediate,
        .operands_mode = OperandsMode.ImmediateToRegMemory,
    };
}

// ADD/SUB/CMP Immediate to accumulator register.
fn decodeArithmeticImmediateToAccum(opcode: Opcode, bytes: []u8, ip: *usize) Instruction {
    const byte1 = bytes[ip.*];
    const w = (byte1 & 1) == 1;

    ip.* += 1;

    var immediate: u16 = undefined;
    var reg: Reg = undefined;
    if (w) {
        immediate = readU16(bytes, ip.*);
        ip.* += 2;
        reg = Reg.AX;
    } else {
        immediate = bytes[ip.*];
        ip.* += 1;
        reg = Reg.AL;
    }

    return Instruction{
        .opcode = opcode,
        .immediate = immediate,
        .reg_memory = RegMemory{
            .reg1 = reg,
            .reg_only = true,
        },
        .operands_mode = OperandsMode.ImmediateToRegMemory,
    };
}

fn decodeJump(opcode: Opcode, bytes: []u8, ip: *usize) Instruction {
    const realval = bytes[ip.* + 1];
    var ipinc: i8 = @bitCast(realval);
    ipinc += 2;
    ip.* += 2;

    return Instruction {
        .opcode = opcode,
        .ip_increment = ipinc,
        .operands_mode = OperandsMode.IpIncrement
    };
}

fn getRegMemory(rm: u8, mod: u8, w: bool, bytes: []u8, ip: *usize) RegMemory {
    var result: RegMemory = undefined;
    if (mod == 0) {
        result = switch (rm) {
            0 => RegMemory{ .reg1 = Reg.BX, .reg2 = Reg.SI },
            1 => RegMemory{ .reg1 = Reg.BX, .reg2 = Reg.DI },
            2 => RegMemory{ .reg1 = Reg.BP, .reg2 = Reg.SI },
            3 => RegMemory{ .reg1 = Reg.BP, .reg2 = Reg.DI },
            4 => RegMemory{ .reg1 = Reg.SI },
            5 => RegMemory{ .reg1 = Reg.DI },
            6 => RegMemory{ .direct_address = true, .is_disp16 = w, .is_disp8 = !w },
            7 => RegMemory{ .reg1 = Reg.BX },
            else => @panic("Wrong rm for mod == 0"),
        };
        if (result.direct_address) {
            if (w) {
                result.disp = readU16(bytes, ip.*);
                ip.* += 2;
            } else {
                result.disp = bytes[ip.*];
                ip.* += 1;
            }
        }
    } else if (mod == 1) {
        result = switch (rm) {
            0 => RegMemory{ .reg1 = Reg.BX, .reg2 = Reg.SI, .is_disp8 = true },
            1 => RegMemory{ .reg1 = Reg.BX, .reg2 = Reg.DI, .is_disp8 = true },
            2 => RegMemory{ .reg1 = Reg.BP, .reg2 = Reg.SI, .is_disp8 = true },
            3 => RegMemory{ .reg1 = Reg.BP, .reg2 = Reg.DI, .is_disp8 = true },
            4 => RegMemory{ .reg1 = Reg.SI, .is_disp8 = true },
            5 => RegMemory{ .reg1 = Reg.DI, .is_disp8 = true },
            6 => RegMemory{ .reg1 = Reg.BP, .is_disp8 = true },
            7 => RegMemory{ .reg1 = Reg.BX, .is_disp8 = true },
            else => @panic("Wrong rm for mod == 1"),
        };
        result.disp = bytes[ip.*];
        ip.* += 1;
    } else if (mod == 2) {
        result = switch (rm) {
            0 => RegMemory{ .reg1 = Reg.BX, .reg2 = Reg.SI, .is_disp16 = true },
            1 => RegMemory{ .reg1 = Reg.BX, .reg2 = Reg.DI, .is_disp16 = true },
            2 => RegMemory{ .reg1 = Reg.BP, .reg2 = Reg.SI, .is_disp16 = true },
            3 => RegMemory{ .reg1 = Reg.BP, .reg2 = Reg.DI, .is_disp16 = true },
            4 => RegMemory{ .reg1 = Reg.SI, .is_disp16 = true },
            5 => RegMemory{ .reg1 = Reg.DI, .is_disp16 = true },
            6 => RegMemory{ .reg1 = Reg.BP, .is_disp16 = true },
            7 => RegMemory{ .reg1 = Reg.BX, .is_disp16 = true },
            else => @panic("Wrong rm for mod == 2"),
        };
        result.disp = readU16(bytes, ip.*);
        ip.* += 2;
    } else if (mod == 3) {
        if (w) {
            result = switch (rm) {
                0 => RegMemory{ .reg1 = Reg.AX, .reg_only = true },
                1 => RegMemory{ .reg1 = Reg.CX, .reg_only = true },
                2 => RegMemory{ .reg1 = Reg.DX, .reg_only = true },
                3 => RegMemory{ .reg1 = Reg.BX, .reg_only = true },
                4 => RegMemory{ .reg1 = Reg.SP, .reg_only = true },
                5 => RegMemory{ .reg1 = Reg.BP, .reg_only = true },
                6 => RegMemory{ .reg1 = Reg.SI, .reg_only = true },
                7 => RegMemory{ .reg1 = Reg.DI, .reg_only = true },
                else => @panic("wrong value provided for register"),
            };
        } else {
            result = switch (rm) {
                0 => RegMemory{ .reg1 = Reg.AL, .reg_only = true },
                1 => RegMemory{ .reg1 = Reg.CL, .reg_only = true },
                2 => RegMemory{ .reg1 = Reg.DL, .reg_only = true },
                3 => RegMemory{ .reg1 = Reg.BL, .reg_only = true },
                4 => RegMemory{ .reg1 = Reg.AH, .reg_only = true },
                5 => RegMemory{ .reg1 = Reg.CH, .reg_only = true },
                6 => RegMemory{ .reg1 = Reg.DH, .reg_only = true },
                7 => RegMemory{ .reg1 = Reg.BH, .reg_only = true },
                else => @panic("wrong value provided for register"),
            };
        }
    }
    result.is_word = w;
    return result;
}

fn readU16(bytes: []u8, ip: usize) u16 {
    return (@as(u16, bytes[ip + 1]) << 8) | bytes[ip];
}

fn chooseReg(v: u8, wide: bool) Reg {
    if (wide) {
        return switch (v) {
            0 => Reg.AX,
            1 => Reg.CX,
            2 => Reg.DX,
            3 => Reg.BX,
            4 => Reg.SP,
            5 => Reg.BP,
            6 => Reg.SI,
            7 => Reg.DI,
            else => @panic("wrong value provided for register"),
        };
    } else {
        return switch (v) {
            0 => Reg.AL,
            1 => Reg.CL,
            2 => Reg.DL,
            3 => Reg.BL,
            4 => Reg.AH,
            5 => Reg.CH,
            6 => Reg.DH,
            7 => Reg.BH,
            else => @panic("wrong value provided for register"),
        };
    }
}

fn regToString(reg: Reg) []const u8 {
    return switch (reg) {
        Reg.AX => "ax",
        Reg.BX => "bx",
        Reg.CX => "cx",
        Reg.DX => "dx",
        Reg.AL => "al",
        Reg.BL => "bl",
        Reg.CL => "cl",
        Reg.DL => "dl",
        Reg.AH => "ah",
        Reg.BH => "bh",
        Reg.CH => "ch",
        Reg.DH => "dh",
        Reg.SP => "sp",
        Reg.BP => "bp",
        Reg.SI => "si",
        Reg.DI => "di",
    };
}

fn opcodeToString(opcode: Opcode) []const u8 {
    return switch (opcode) {
        Opcode.MOV => "mov",
        Opcode.ADD => "add",
        Opcode.SUB => "sub",
        Opcode.CMP => "cmp",
        Opcode.JA => "ja",
        Opcode.JB => "jb",
        Opcode.JBE => "jbe",
        Opcode.JCXZ => "jcxz",
        Opcode.JE => "je",
        Opcode.JG => "jg",
        Opcode.JL => "jl",
        Opcode.JLE => "jle",
        Opcode.JNB => "jnb",
        Opcode.JNE => "jne",
        Opcode.JNL => "jnl",
        Opcode.JNO => "jno",
        Opcode.JNP => "jnp",
        Opcode.JNS => "jns",
        Opcode.JO => "jo",
        Opcode.JP => "jp",
        Opcode.JS => "js",
        Opcode.JZ => "jz",
        Opcode.JNZ => "jnz",
        Opcode.LOOP => "loop",
        Opcode.LOOPNZ => "loopnz",
        Opcode.LOOPZ => "loopz",
    };
}
