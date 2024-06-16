const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const maxInt = std.math.maxInt;

// pub extern "ntdll" fn RtlQueryPerformanceCounter(PerformanceCounter: *LARGE_INTEGER) callconv(WINAPI) BOOL;
comptime {
    asm (
        \\.global readTimeStamp;
        \\readTimeStamp:
        \\  rdtsc
        \\  salq $32, %rdx
        \\  orq %rdx, %rax
        \\  retq
    );
}

extern fn readTimeStamp() u64;

pub fn main() !void {
    const ms_start = std.time.milliTimestamp();
    // const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const args = try std.process.argsAlloc(gpa.backing_allocator);
    const stdout = std.io.getStdOut().writer();
    const ms_end = std.time.milliTimestamp();
    
    const diff = ms_end - ms_start;
    try stdout.print("Seconds: {d}\n", .{@divTrunc(diff, std.time.ms_per_s)});
    try stdout.print("Milliseconds: {d}\n", .{@rem(diff, std.time.ms_per_s)});

    var counter: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&counter);
    try stdout.print("{d}\n", .{counter});
    const other = readTimeStamp();
    try stdout.print("{d}\n", .{other});
}

