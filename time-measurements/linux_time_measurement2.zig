const std = @import("std");
const builtin = @import("builtin");
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
    const start: i128 = std.time.microTimestamp();

    const os = builtin.os.tag;

    if (os == .windows) {
        // Use Windows API
        // Example: windows_function();
        _ = std.os.windows.ntdll.NtClose(0);
    } else if (os == .linux) {
        // Use Linux API
        // Example: linux_function();
    } else {
        // Handle other operating systems
    }

    const freqToWait: i128 = @intCast(msToWait * 1000);
    var diff: i128 = 0;
    var end: i128 = 0;
    while (diff < freqToWait) {
        end = std.time.nanoTimestamp();
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
