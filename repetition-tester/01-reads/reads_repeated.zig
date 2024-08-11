const std = @import("std");
const maxInt = std.math.maxInt;
const builtin = @import("builtin");
const windows = std.os.windows;

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

fn getCPUFrequencyUnix(msToWait: u64) u64 {
    const cpuStart = readTimeStamp();
    const start: i128 = std.time.nanoTimestamp();

    const freqToWait: i128 = @intCast(msToWait * 1000000);
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

fn getCPUFrequencyWindows(msToWait: u64) u64 {
    const cpuStart = readTimeStamp();
    var freq: i64 = 0;
    _ = windows.ntdll.RtlQueryPerformanceFrequency(&freq);
    var start: i64 = 0;
    _ = windows.ntdll.RtlQueryPerformanceCounter(&start);

    const freqToWait = @divTrunc(freq * @as(i64, @intCast(msToWait)), 1000);

    var diff: i64 = 0;
    var end: i64 = 0;
    while (diff < freqToWait) {
        _ = windows.ntdll.RtlQueryPerformanceCounter(&end);
        diff = end - start;
    }

    const cpuEnd = readTimeStamp();
    const cpuDiff = @divTrunc((cpuEnd - cpuStart) * 1000, msToWait);
    return cpuDiff;
}

// Return estimation of number of clocks per second.
fn getCPUFrequency(msToWait: u64) u64 {
    const os = builtin.os.tag;
    if (os == .windows) {
        // Use Windows API
        // Example: windows_function();
        return getCPUFrequencyWindows(msToWait);
    } else {
        return getCPUFrequencyUnix(msToWait);
        // Handle other operating systems
    }
}

const TestMode = enum {
    uninitialized,
    testing,
    completed,
    err
};

const RepetitionTestResults = struct {
    test_count: u64,
    total_time: u64,
    max_time: u64,
    min_time: u64,
};

const RepetitionTester = struct {
    mode: TestMode = TestMode.uninitialized,
    start_time: u64 = 0,
    elapsed_time: u64 = 0,
    min_time: u64 = 0,
    max_time: u64 = 0,
    cpu_timer_freq: u64 = 0,
    seconds_to_wait_for_update: u64 = 3,
    last_update_time: u64 = 0,
    target_byte_count: usize = 0,
    actual_byte_count: usize = 0,

    fn newTestWave(self: *RepetitionTester, byte_count: u64, cpu_timer_freq: u64) void {
        self.target_byte_count = byte_count;
        self.cpu_timer_freq = cpu_timer_freq;
        self.min_time = maxInt(u64);
        self.max_time = 0;
        self.mode = TestMode.testing;
        self.elapsed_time = 0;
        self.actual_byte_count = 0;
    }

    fn isTesting(self: *RepetitionTester) !bool {
        if (self.mode == TestMode.testing) {
            const curr_time = readTimeStamp();

            if (self.max_time < self.elapsed_time) {
                self.max_time = self.elapsed_time;
            }

            if (self.elapsed_time == 0) {
                // Do nothing.
            } else if (self.min_time > self.elapsed_time) {
                self.min_time = self.elapsed_time;
                self.last_update_time = curr_time;
                try self.printResults(true);
            } else {
                const dt = curr_time - self.last_update_time;
                if ((dt / self.cpu_timer_freq) > self.seconds_to_wait_for_update) {
                    self.mode = TestMode.completed;
                    
                    try self.printResults(false);
                }
            }

            self.elapsed_time = 0;
        }

        return self.mode == TestMode.testing;
    }

    fn beginTime(self: *RepetitionTester) void {
        self.start_time = readTimeStamp();
    }

    fn endTime(self: *RepetitionTester) void {
        self.elapsed_time += readTimeStamp() - self.start_time;
    }

    fn signalError(self: *RepetitionTester, message: []const u8) !void {
        self.mode = TestMode.err;
        const stderr = std.io.getStdErr().writer();
        try stderr.print("ERROR: {s}\n", .{message});
        // _ = message;
        // try stderr.print("ERROR: \n", .{});
    //    const stdout = std.io.getStdOut().writer();
    //    try stdout.print("Thing: %s\n", .{message});
    //    std.debug.print("Thing %d\n", .{2});
    }

    fn printResults(self: *RepetitionTester, intermediate: bool) !void {
        const stdout = std.io.getStdOut().writer();
        if (intermediate) {
            try stdout.print("                                               \r", .{});
            try self.printTime("Min", self.min_time, false);
        } else {
            try stdout.print("                                               \r", .{});
            try self.printTime("Min", self.min_time, true);
            try self.printTime("Max", self.max_time, true);
        }
    }

    fn printTime(self: *RepetitionTester, prefix: []const u8, value: u64, new_line: bool) !void {
        const stdout = std.io.getStdOut().writer();
        const ms = @as(f64, @floatFromInt(value)) * 1000.0 / @as(f64, @floatFromInt(self.cpu_timer_freq));
        try stdout.print("{s}: {d:.5} ({d:.5} ms) ", .{prefix, value, ms});

        if (self.actual_byte_count != 0) {
            const megabytes = @as(f64, @floatFromInt(self.actual_byte_count)) / (1024.0 * 1024.0);
            const gigabytes = megabytes / 1024.0;
            const gigabytes_per_second = @as(f64, @floatFromInt(self.cpu_timer_freq)) * gigabytes / @as(f64, @floatFromInt(value));
            try stdout.print("{d:.5} mb {d:.5} gb/s", .{megabytes, gigabytes_per_second});
        }

        if (new_line) {
            try stdout.print("\n", .{});
        }
    }

    fn countBytes(self: *RepetitionTester, bytes_count: usize) void {
        self.actual_byte_count = bytes_count;
    }
};

const ReadParameters = struct {
    dest: []u8,
    file_name: []const u8,
};

fn readViaReadAllAlloc(tester: *RepetitionTester, read_params: ReadParameters) !void {
    while (try tester.isTesting()) {
        if (std.fs.cwd().openFile(read_params.file_name, .{})) |file| {
            tester.beginTime();
            if (file.readAll(read_params.dest)) |count| {
                tester.endTime();
                tester.countBytes(count);
            } else |_| {
                tester.endTime();
                try tester.signalError("readAll failed");
            }
            file.close();
        } else |_| {
            try tester.signalError("openFile failed");
        }
    }
}

fn readViaWinRead(tester: *RepetitionTester, read_params: ReadParameters) !void {
    while (try tester.isTesting()) {
        if (std.fs.cwd().openFile(read_params.file_name, .{})) |file| {
            tester.beginTime();
            if (windows.ReadFile(file.handle, read_params.dest, null)) |count| {
                tester.endTime();
                tester.countBytes(count);
            } else |_| {
                tester.endTime();
                try tester.signalError("windows.ReadFile failed");
            }
            file.close();
        } else |_| {
            try tester.signalError("openFile failed");
        }
    }
}

pub fn main() !void {
    const cpu_timer_freq = getCPUFrequency(100);
    var ddd = [_]u8{0};
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const args = try std.process.argsAlloc(gpa.backing_allocator);
    const stdout = std.io.getStdOut().writer();
    if (args.len < 1) {
        try stdout.print("Usage:\n{s} [input.file]\n", .{args[0]});
        return;
    }
    var read_params = ReadParameters {
        .dest = &ddd,
        .file_name = args[1],
        // .file_name = "../../haversine-json-generator/data_10000000_uniform.json",
        // .file_name = "../../haversine-json-generator/data_1000000_uniform.json",
        // .file_name = "../../haversine-json-generator/data_10000_uniform.json",
    };
    
    if (std.fs.cwd().openFile(read_params.file_name, .{})) |file| {
        const stat = try file.stat();
        read_params.dest = try gpa.backing_allocator.alloc(u8, stat.size);
    } else |_| {
        std.debug.print("ERROR: failed to read file stat\n", .{});
        return;
    }

    var testers = [_]RepetitionTester{RepetitionTester{}} ** 2;

    while (true) {
        try stdout.print("\n--- read via readAll ---\n", .{});
        testers[0].newTestWave(read_params.dest.len, cpu_timer_freq);
        try readViaReadAllAlloc(&testers[0], read_params);
        
        try stdout.print("\n--- read via windows.ReadFile ---\n", .{});
        testers[1].newTestWave(read_params.dest.len, cpu_timer_freq);
        try readViaWinRead(&testers[1], read_params);
    }
}