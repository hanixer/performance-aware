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
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const args = try std.process.argsAlloc(gpa.backing_allocator);
    const stdout = std.io.getStdOut().writer();
    if (args.len < 2) {
        try stdout.print("Usage:\n{s} [ms to measure QPC]\n", .{args[0]});
        return;
    }

    const timeMs = try fmt.parseInt(i64, args[1], 10);

    const cpuStart = readTimeStamp();
    var freq: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceFrequency(&freq);
    var start: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&start);

    const freqToWait = @divTrunc(freq * timeMs, 1000);

    var diff: i64 = 0;
    var end: i64 = 0;
    while (diff < freqToWait) {
        _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&end);
        diff = end - start;
    }

    const cpuEnd = readTimeStamp();

    try stdout.print("Freq:            {d}\n", .{freq});
    try stdout.print("Freq to wait:    {d}\n", .{freqToWait});
    try stdout.print("Start:           {d}\n", .{start});
    try stdout.print("End:             {d}\n", .{end});
    try stdout.print("Diff:            {d}\n", .{diff});

    const diffFloat: f64 = @floatFromInt(diff);
    const freqToWaitF: f64 = @floatFromInt(freqToWait);
    const elapsedSec: f64 = diffFloat / freqToWaitF;
    try stdout.print("Elapsed seconds: {d}\n", .{elapsedSec});
    
    const cpuDiff = @divTrunc((cpuEnd - cpuStart) * 1000, @as(u64, @intCast(timeMs)));
    // const cpuDiff = @divTrunc((cpuEnd - cpuStart) * 1000, @as(u64, @intCast(freq)));
    // const cpuDiff = @divTrunc(cpuEnd - cpuStart * 1000, @as(u64, @truncate(freq)));
    try stdout.print("CPU Start:       {d}\n", .{cpuStart});
    try stdout.print("CPU End:         {d}\n", .{cpuEnd});
    try stdout.print("CPU Diff:        {d}\n", .{cpuDiff});

    const cpuDiffF: f64 = @floatFromInt(cpuDiff);
    const cpuFreq = cpuDiffF / 1000000;
    try stdout.print("\nEstimated CPU frequency:   {d} MHz\n", .{cpuFreq});
}

