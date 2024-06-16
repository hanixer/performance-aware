const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const maxInt = std.math.maxInt;

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
    const stdout = std.io.getStdOut().writer();
    const cpuStart = readTimeStamp();    
    const start = std.time.microTimestamp();
    var diff: i64 = 0;
    var end: i64 = 0;
    while (diff < 1000000) {
        _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&end);
        end = std.time.microTimestamp();
        diff = end - start;
    }

    const cpuEnd = readTimeStamp();

    try stdout.print("Freq:   {d}\n", .{1000000});
    try stdout.print("Start:  {d}\n", .{start});
    try stdout.print("End:    {d}\n", .{end});
    try stdout.print("Diff:   {d}\n", .{diff});

    const diffFloat: f64 = @floatFromInt(diff);
    const freqFloat: f64 = 1000000;
    const units: f64 = diffFloat / freqFloat;
    try stdout.print("Elapsed seconds: {d}\n", .{units});
    
    try stdout.print("CPU Start:  {d}\n", .{cpuStart});
    try stdout.print("CPU End:    {d}\n", .{cpuEnd});
    try stdout.print("CPU Diff:   {d}\n", .{cpuEnd - cpuStart});
}

