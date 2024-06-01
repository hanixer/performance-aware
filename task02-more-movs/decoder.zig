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
    reg1: Reg,
    reg2: ?Reg = null,
    is_disp8: bool = false,
    disp8: u8 = 0,
    is_disp16: bool = false,
    disp16: u16 = 0,
};

pub fn main() !void {
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const stdout = std.io.getStdOut().writer();
    const args = try std.process.argsAlloc(gpa.backing_allocator);
    // std.debug.print("Hello, {s}!\n", .{"World"});
    const file = try std.fs.cwd().openFile(args[1], .{});

    const bytes = try file.reader().readAllAlloc(gpa.backing_allocator, maxInt(i32));

    // const x: i32 = @intCast(n);
    // try stdout.print("Read: {d} bytes. {s}\n", .{ bytes.len, bytes });

    try stdout.print("\nbits 16\n\n", .{});

    // const mooo = getEAMode(1, 2, true);
    // std.debug.print("{s}", .{mooo});

    var i: usize = 0;
    var buf: [100]u8 = undefined;
    while (i < bytes.len) {
        const firstb = bytes[i];
        if ((firstb & 0xFC) == 0x88) {
            // If d == 0 then source is spec. in REG.
            // If d == 1 then dest is spec. in REG.
            const secondb = bytes[i + 1];
            const wide = (firstb & 1) == 1;
            const d = (firstb >> 1) & 1;
            const mod = (secondb >> 6) & 3;
            const reg_raw = (secondb >> 3) & 7;
            const rm = secondb & 7;

            const reg = chooseReg(reg_raw, wide);
            var eaMode = getEAMode(rm, mod, wide);
            if (eaMode.is_disp8) {
                // get 1 byte
                eaMode.disp8 = bytes[i + 2];
                i += 3;
            } else if (eaMode.is_disp16) {
                // get 2 bytes.
                eaMode.disp16 = (@as(u16, bytes[i + 3]) << 8) | bytes[i + 2];
                i += 4;
            } else {
                // increment by 2.
                i += 2;
            }

            if (d == 0) {
                try stdout.print("mov {s}, {s}\n", .{ eaModeToString(eaMode, &buf), regToString(reg) });
            } else {
                try stdout.print("mov {s}, {s}\n", .{ regToString(reg), eaModeToString(eaMode, &buf) });
            }
        } else if ((firstb & 0xF0) == 0xB0) {
            // Immediate to register.
            const wide = (firstb & 8) == 8;
            const dest_reg = chooseReg(firstb & 7, wide);
            var val: i16 = undefined;
            if (wide) {
                val = (@as(i16, bytes[i + 2]) << 8) + bytes[i + 1];
                i += 3;
            } else {
                val = bytes[i + 1];
                i += 2;
            }
            try stdout.print("mov {s}, {d}\n", .{ regToString(dest_reg), val });
        } else {
            @panic("Not implemented... Oh no... ohnooo, oh no no no no no...");
        }
    }
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

fn eaModeToString(mode: EAMode, buf: []u8) []u8 {
    // mode: EAMode
    // var buf: [100]u8 = undefined;
    // if (mode.disp8) {
    //     if (mode.reg2) |reg2| {
    //         fmt.bufPrint(buf, "{s} + {s} + disp8", args: anytype)
    //     } else {}
    // }

    // if (mode.reg2)
    // [reg + reg2 + disp8]
    // [reg1 + reg2 + disp16]
    // [reg1 + reg2]
    // [reg1]
    if (mode.is_disp8) {
        if (mode.reg2) |reg2| {
            return simplyBufPrint(buf, "[{s} + {s} + {d}]", .{ regToString(mode.reg1), regToString(reg2), mode.disp8 });
        } else {
            return simplyBufPrint(buf, "[{s} + {d}]", .{ regToString(mode.reg1), mode.disp8 });
        }
    } else if (mode.is_disp16) {
        if (mode.reg2) |reg2| {
            return simplyBufPrint(buf, "[{s} + {s} + {d}]", .{ regToString(mode.reg1), regToString(reg2), mode.disp16 });
        } else {
            return simplyBufPrint(buf, "[{s} + {d}]", .{ regToString(mode.reg1), mode.disp8 });
        }
    } else if (mode.reg2) |reg2| {
        return simplyBufPrint(buf, "[{s} + {s}]", .{ regToString(mode.reg1), regToString(reg2)});
    } else {
        return simplyBufPrint(buf, "{s}", .{ regToString(mode.reg1) });
    }

    @panic("Unhandled case...");
}

fn getEAMode(rm: u8, mod: u8, wide: bool) EAMode {
    if (mod == 0) {
        return switch (rm) {
            0 => EAMode{ .reg1 = Reg.BX, .reg2 = Reg.SI },
            1 => EAMode{ .reg1 = Reg.BX, .reg2 = Reg.DI },
            2 => EAMode{ .reg1 = Reg.BP, .reg2 = Reg.SI },
            3 => EAMode{ .reg1 = Reg.BP, .reg2 = Reg.DI },
            4 => EAMode{ .reg1 = Reg.SI },
            5 => EAMode{ .reg1 = Reg.DI },
            6 => EAMode{ .reg1 = Reg.DI }, // TODO: direct address
            7 => EAMode{ .reg1 = Reg.BX },
            else => @panic("Wrong rm for mod == 0"),
        };
    } else if (mod == 1) {
        return switch (rm) {
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
        return switch (rm) {
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
            return switch (rm) {
                0 => EAMode{ .reg1 = Reg.AX },
                1 => EAMode{ .reg1 = Reg.CX },
                2 => EAMode{ .reg1 = Reg.DX },
                3 => EAMode{ .reg1 = Reg.BX },
                4 => EAMode{ .reg1 = Reg.SP },
                5 => EAMode{ .reg1 = Reg.BP },
                6 => EAMode{ .reg1 = Reg.SI },
                7 => EAMode{ .reg1 = Reg.DI },
                else => @panic("wrong value provided for register"),
            };
        } else {
            return switch (rm) {
                0 => EAMode{ .reg1 = Reg.AL },
                1 => EAMode{ .reg1 = Reg.CL },
                2 => EAMode{ .reg1 = Reg.DL },
                3 => EAMode{ .reg1 = Reg.BL },
                4 => EAMode{ .reg1 = Reg.AH },
                5 => EAMode{ .reg1 = Reg.CH },
                6 => EAMode{ .reg1 = Reg.DH },
                7 => EAMode{ .reg1 = Reg.BH },
                else => @panic("wrong value provided for register"),
            };
        }
    }
    @panic("Wrong mod or rm field");
}
