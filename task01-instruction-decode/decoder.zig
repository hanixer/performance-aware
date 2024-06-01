const std = @import("std");
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

pub fn main() !void {
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const stdout = std.io.getStdOut().writer();
    const args = try std.process.argsAlloc(gpa.backing_allocator);
    // std.debug.print("Hello, {s}!\n", .{"World"});
    const file = try std.fs.cwd().openFile(args[1], .{});

    const bytes = try file.reader().readAllAlloc(gpa.backing_allocator, maxInt(i32));

    // const x: i32 = @intCast(n);
    // try stdout.print("Read: {d} bytes. {s}\n", .{ bytes.len, bytes });

    try stdout.print("\r\nbits 16\r\n\r\n", .{});

    var i: usize = 0;
    while (i < bytes.len) {
        const firstb = bytes[i];
        if ((firstb & 0x88) == 0x88) {
            const secondb = bytes[i + 1];
            const wide = (firstb & 1) == 1;
            const src_reg = chooseReg((secondb >> 3) & 7, wide);
            const dest_reg = chooseReg(secondb & 7, wide);
            try stdout.print("mov {s}, {s}\r\n", .{ regToString(dest_reg), regToString(src_reg) });
            i += 2;
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
