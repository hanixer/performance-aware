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
    // const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const args = try std.process.argsAlloc(gpa.backing_allocator);
    const stdout = std.io.getStdOut().writer();
    
    var freq: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceFrequency(&freq);
    var start: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&start);

    var diff: i64 = 0;
    var end: i64 = 0;
    while (diff < freq) {
        _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&end);
        diff = end - start;
    }

    try stdout.print("Freq:  {d}\n", .{freq});
    try stdout.print("Start:  {d}\n", .{start});
    try stdout.print("End:    {d}\n", .{end});
    try stdout.print("Diff:   {d}\n", .{diff});

    const diffFloat: f64 = @floatFromInt(diff);
    const freqFloat: f64 = @floatFromInt(freq);
    const units: f64 = diffFloat / freqFloat + 0.0001;
    try stdout.print("Elapsed seconds: {d}\n", .{units});
}

