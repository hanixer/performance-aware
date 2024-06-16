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

// Return estimation of number of clocks per second.
fn getCPUFrequency(msToWait: u64) u64 {
    const cpuStart = readTimeStamp();
    var freq: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceFrequency(&freq);
    var start: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&start);

    const freqToWait = @divTrunc(freq * @as(i64, @intCast(msToWait)), 1000);
    var diff: i64 = 0;
    var end: i64 = 0;
    while (diff < freqToWait) {
        _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&end);
        diff = end - start;
    }
    const cpuEnd = readTimeStamp();
    const cpuFreq = @divTrunc((cpuEnd - cpuStart) * 1000, msToWait);
    return cpuFreq;
}

pub fn main() !void {
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const args = try std.process.argsAlloc(gpa.backing_allocator);
    const stdout = std.io.getStdOut().writer();
    if (args.len < 2) {
        try stdout.print("Usage:\n{s} [ms to measure QPC]\n", .{args[0]});
        return;
    }

    const timeMs = try fmt.parseInt(u64, args[1], 10);
    const cpuFreq = getCPUFrequency(timeMs);
    try stdout.print("\nEstimated CPU frequency:   {d} MHz\n", .{cpuFreq});
}

