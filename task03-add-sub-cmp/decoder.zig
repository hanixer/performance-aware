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

const EAMode = struct {
    reg1: Reg = Reg.AX, // This should be available
    reg2: ?Reg = null,
    is_disp8: bool = false,
    disp8: u8 = 0,
    is_disp16: bool = false,
    disp16: u16 = 0,
    reg_only: bool = false,
    is_word: bool = false,
    direct_address: bool = false,
};

const Opcode = enum { MOV, ADD, SUB, CMP };

const DecoderState = struct {
    bytes: []u8,
    i: usize,
    strbuf: [128]u8 = undefined,
    out: std.fs.File.Writer,
};

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
        const firstb = state.bytes[state.i];
        if ((firstb & 0xFC) == 0x88) {
            try decodeRegMemInstruction(Opcode.MOV, &state);
        } else if ((firstb & 0xFC) == 0) {
            // ADD Reg/memory with register to either.
            try decodeRegMemInstruction(Opcode.ADD, &state);
        } else if ((firstb & 0xFC) == 0x28) {
            // SUB Reg/memory with register to either.
            try decodeRegMemInstruction(Opcode.SUB, &state);
        } else if ((firstb & 0xFC) == 0b00111000) {
            // CMP Reg/memory with register to either.
            try decodeRegMemInstruction(Opcode.CMP, &state);
        } else if ((firstb & 0xFC) == 0x80) {
            try decodeArithmeticImmediate(&state);
        } else if ((firstb & 0xFC) == 4) {
            try decodeArithmeticImmediateToAccum(Opcode.ADD, &state);
        } else if ((firstb & 0xFC) == 0b00101100) {
            try decodeArithmeticImmediateToAccum(Opcode.SUB, &state);
        } else if ((firstb & 0xFC) == 0b00111100) {
            try decodeArithmeticImmediateToAccum(Opcode.CMP, &state);
        } else if ((firstb & 0xF0) == 0xB0) {
            // MOV Immediate to register.
            const wide = (firstb & 8) == 8;
            const dest_reg = chooseReg(firstb & 7, wide);
            var val: i16 = undefined;
            if (wide) {
                val = (@as(i16, state.bytes[state.i + 2]) << 8) + state.bytes[state.i + 1];
                state.i += 3;
            } else {
                val = state.bytes[state.i + 1];
                state.i += 2;
            }
            try stdout.print("mov {s}, {d}\n", .{ regToString(dest_reg), val });
        } else {
            std.debug.print("first byte {b} index {d}\n\n", .{ firstb, state.i });
            @panic("Not implemented... Oh no... ohnooo, oh no no no no no...");
        }
    }
}

fn decodeArithmeticImmediateToAccum(opcode: Opcode, state: *DecoderState) !void {
    // ADD/SUB/... Immediate to accumulator.
    const firstb = state.bytes[state.i];
    const wide = (firstb & 1) == 1;
    var val: i16 = undefined;
    var reg: []const u8 = undefined;
    if (wide) {
        val = (@as(i16, state.bytes[state.i + 2]) << 8) + state.bytes[state.i + 1];
        state.i += 3;
        reg = "ax";
    } else {
        val = state.bytes[state.i + 1];
        state.i += 2;
        reg = "al";
    }
    try state.out.print("{s} {s}, {d}\n", .{ opcodeToString(opcode), reg, val });
}

fn decodeArithmeticImmediate(state: *DecoderState) !void {
    // ADD/SUB/... Immediate to register/memory.
    const firstb = state.bytes[state.i];
    const secondb = state.bytes[state.i + 1];
    const s = (firstb & 2) == 2;
    const wide = (firstb & 1) == 1;
    const mod = (secondb >> 6) & 3;
    const rm = secondb & 7;
    var eaMode = getEAMode(rm, mod, wide);
    if (eaMode.is_disp8) {
        eaMode.disp8 = state.bytes[state.i + 2];
        state.i += 3;
    } else if (eaMode.is_disp16) {
        eaMode.disp16 = (@as(u16, state.bytes[state.i + 3]) << 8) | state.bytes[state.i + 2];
        state.i += 4;
    } else {
        state.i += 2;
    }

    var val: i16 = undefined;
    if (!s and wide) {
        val = (@as(i16, state.bytes[state.i + 2]) << 8) + state.bytes[state.i + 1];
        state.i += 2;
    } else {
        val = state.bytes[state.i];
        state.i += 1;
    }

    const op_part = (secondb & 0x38) >> 3;
    const opcode =
        if (op_part == 0b101) Opcode.SUB else if (op_part == 0b111) Opcode.CMP else Opcode.ADD;

    try state.out.print("{s} {s}, {d}\n", .{ opcodeToString(opcode), eaModeToString(eaMode, &state.strbuf, !eaMode.reg_only), val });
}

fn decodeRegMemInstruction(opcode: Opcode, state: *DecoderState) !void {
    const firstb = state.bytes[state.i];
    const secondb = state.bytes[state.i + 1];
    const wide = (firstb & 1) == 1;
    const d = (firstb >> 1) & 1;
    const mod = (secondb >> 6) & 3;
    const reg_raw = (secondb >> 3) & 7;
    const rm = secondb & 7;

    const reg = chooseReg(reg_raw, wide);
    var eaMode = getEAMode(rm, mod, wide);
    if (eaMode.is_disp8) {
        // get 1 byte
        eaMode.disp8 = state.bytes[state.i + 2];
        state.i += 3;
    } else if (eaMode.is_disp16) {
        // get 2 bytes.
        eaMode.disp16 = (@as(u16, state.bytes[state.i + 3]) << 8) | state.bytes[state.i + 2];
        state.i += 4;
    } else {
        // increment by 2.
        state.i += 2;
    }

    if (d == 0) {
        try state.out.print("{s} {s}, {s}\n", .{ opcodeToString(opcode), eaModeToString(eaMode, &state.strbuf, false), regToString(reg) });
    } else {
        try state.out.print("{s} {s}, {s}\n", .{ opcodeToString(opcode), regToString(reg), eaModeToString(eaMode, &state.strbuf, false) });
    }
}

fn opcodeToString(opcode: Opcode) []const u8 {
    return switch (opcode) {
        Opcode.MOV => "mov",
        Opcode.ADD => "add",
        Opcode.SUB => "sub",
        Opcode.CMP => "cmp",
    };
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

fn simplyBufPrint(buf: []u8, comptime f: []const u8, args: anytype) []u8 {
    if (fmt.bufPrint(buf, f, args)) |res| {
        return res;
    } else |_| {
        @panic("Cannot print to buffer");
    }
}

fn eaModeToString(mode: EAMode, buf: []u8, specify_width: bool) []u8 {
    const width_specifier: []const u8 = if (!specify_width)
        ""
    else if (mode.is_word)
        "word "
    else
        "byte ";

    if (mode.direct_address) {
        if (mode.is_disp16) {
            return simplyBufPrint(buf, "{s}[{d}]", .{ width_specifier, mode.disp16 });
        } else {
            return simplyBufPrint(buf, "{s}[{d}]", .{ width_specifier, mode.disp8 });
        }
    } else if (mode.is_disp8) {
        if (mode.reg2) |reg2| {
            return simplyBufPrint(buf, "{s}[{s} + {s} + {d}]", .{ width_specifier, regToString(mode.reg1), regToString(reg2), mode.disp8 });
        } else {
            return simplyBufPrint(buf, "{s}[{s} + {d}]", .{ width_specifier, regToString(mode.reg1), mode.disp8 });
        }
    } else if (mode.is_disp16) {
        if (mode.reg2) |reg2| {
            return simplyBufPrint(buf, "{s}[{s} + {s} + {d}]", .{ width_specifier, regToString(mode.reg1), regToString(reg2), mode.disp16 });
        } else {
            return simplyBufPrint(buf, "{s}[{s} + {d}]", .{ width_specifier, regToString(mode.reg1), mode.disp8 });
        }
    } else if (mode.reg2) |reg2| {
        return simplyBufPrint(buf, "{s}[{s} + {s}]", .{ width_specifier, regToString(mode.reg1), regToString(reg2) });
    } else if (mode.reg_only) {
        return simplyBufPrint(buf, "{s}", .{regToString(mode.reg1)});
    } else {
        return simplyBufPrint(buf, "{s}[{s}]", .{ width_specifier, regToString(mode.reg1) });
    }

    @panic("Unhandled case...");
}

fn getEAMode(rm: u8, mod: u8, wide: bool) EAMode {
    var result: EAMode = undefined;
    if (mod == 0) {
        result = switch (rm) {
            0 => EAMode{ .reg1 = Reg.BX, .reg2 = Reg.SI },
            1 => EAMode{ .reg1 = Reg.BX, .reg2 = Reg.DI },
            2 => EAMode{ .reg1 = Reg.BP, .reg2 = Reg.SI },
            3 => EAMode{ .reg1 = Reg.BP, .reg2 = Reg.DI },
            4 => EAMode{ .reg1 = Reg.SI },
            5 => EAMode{ .reg1 = Reg.DI },
            6 => EAMode{ .direct_address = true, .is_disp16 = wide, .is_disp8 = !wide },
            7 => EAMode{ .reg1 = Reg.BX },
            else => @panic("Wrong rm for mod == 0"),
        };
    } else if (mod == 1) {
        result = switch (rm) {
            0 => EAMode{ .reg1 = Reg.BX, .reg2 = Reg.SI, .is_disp8 = true },
            1 => EAMode{ .reg1 = Reg.BX, .reg2 = Reg.DI, .is_disp8 = true },
            2 => EAMode{ .reg1 = Reg.BP, .reg2 = Reg.SI, .is_disp8 = true },
            3 => EAMode{ .reg1 = Reg.BP, .reg2 = Reg.DI, .is_disp8 = true },
            4 => EAMode{ .reg1 = Reg.SI, .is_disp8 = true },
            5 => EAMode{ .reg1 = Reg.DI, .is_disp8 = true },
            6 => EAMode{ .reg1 = Reg.BP, .is_disp8 = true },
            7 => EAMode{ .reg1 = Reg.BX, .is_disp8 = true },
            else => @panic("Wrong rm for mod == 1"),
        };
    } else if (mod == 2) {
        result = switch (rm) {
            0 => EAMode{ .reg1 = Reg.BX, .reg2 = Reg.SI, .is_disp16 = true },
            1 => EAMode{ .reg1 = Reg.BX, .reg2 = Reg.DI, .is_disp16 = true },
            2 => EAMode{ .reg1 = Reg.BP, .reg2 = Reg.SI, .is_disp16 = true },
            3 => EAMode{ .reg1 = Reg.BP, .reg2 = Reg.DI, .is_disp16 = true },
            4 => EAMode{ .reg1 = Reg.SI, .is_disp16 = true },
            5 => EAMode{ .reg1 = Reg.DI, .is_disp16 = true },
            6 => EAMode{ .reg1 = Reg.BP, .is_disp16 = true },
            7 => EAMode{ .reg1 = Reg.BX, .is_disp16 = true },
            else => @panic("Wrong rm for mod == 2"),
        };
    } else if (mod == 3) {
        if (wide) {
            result = switch (rm) {
                0 => EAMode{ .reg1 = Reg.AX, .reg_only = true },
                1 => EAMode{ .reg1 = Reg.CX, .reg_only = true },
                2 => EAMode{ .reg1 = Reg.DX, .reg_only = true },
                3 => EAMode{ .reg1 = Reg.BX, .reg_only = true },
                4 => EAMode{ .reg1 = Reg.SP, .reg_only = true },
                5 => EAMode{ .reg1 = Reg.BP, .reg_only = true },
                6 => EAMode{ .reg1 = Reg.SI, .reg_only = true },
                7 => EAMode{ .reg1 = Reg.DI, .reg_only = true },
                else => @panic("wrong value provided for register"),
            };
        } else {
            result = switch (rm) {
                0 => EAMode{ .reg1 = Reg.AL, .reg_only = true },
                1 => EAMode{ .reg1 = Reg.CL, .reg_only = true },
                2 => EAMode{ .reg1 = Reg.DL, .reg_only = true },
                3 => EAMode{ .reg1 = Reg.BL, .reg_only = true },
                4 => EAMode{ .reg1 = Reg.AH, .reg_only = true },
                5 => EAMode{ .reg1 = Reg.CH, .reg_only = true },
                6 => EAMode{ .reg1 = Reg.DH, .reg_only = true },
                7 => EAMode{ .reg1 = Reg.BH, .reg_only = true },
                else => @panic("wrong value provided for register"),
            };
        }
    }
    result.is_word = wide;
    return result;
}
