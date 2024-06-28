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

// Return estimation of number of clocks per second.
fn getCPUFrequency(msToWait: u64) u64 {
    const os = builtin.os.tag;
    if (os == .windows) {
        // Use Windows API
        // Example: windows_function();
        _ = std.os.windows.ntdll.NtClose(0);
        return 0;
    } else {
        return getCPUFrequencyUnix(msToWait);
        // Handle other operating systems
    }
}

const NameTimer = struct {
    name: []const u8,
    elapsed: u64,
};

const TimerData = struct {
    cpu_frequency: u64 = 0,
    curr_name: []const u8 = "",
    curr_start: u64 = 0,
    timers: std.ArrayList(NameTimer),

    fn init(self: *TimerData) void {
        self.cpu_frequency = getCPUFrequency(100);
    }

    fn startTimer(self: *TimerData, name: []const u8) void {
        self.curr_start = readTimeStamp();
        self.curr_name = name;
    }

    fn endTimer(self: *TimerData) !void {
        const end = readTimeStamp();
        var new_one = try self.timers.addOne();
        new_one.name = self.curr_name;
        new_one.elapsed = end - self.curr_start;
    }

    fn printResults(self: *TimerData, out: std.fs.File.Writer) !void {
        var total: u64 = 0;
        for (self.timers.items) |value| {
            total += value.elapsed;
        }

        const ms_elapsed = total * 1000 / self.cpu_frequency;
        const minutes = @divTrunc(ms_elapsed, std.time.ms_per_min);
        const seconds = (ms_elapsed % std.time.ms_per_min) / std.time.ms_per_s;
        const ms = (ms_elapsed % std.time.ms_per_s);

        try out.print("Total time: ~{d}:{d}.{d} ({d} ticks, {d} approximate frequency\n", .{ minutes, seconds, ms, total, self.cpu_frequency });
        for (self.timers.items, 0..) |value, i| {
            const percents: f64 = @as(f64, @floatFromInt(value.elapsed)) * 100 / @as(f64, @floatFromInt(total));
            try out.print("\t {d}. {s} -- {d} ticks, {d:.2}%\n", .{ i + 1, value.name, value.elapsed, percents });
        }
    }
};

const PointPair = struct {
    x0: f64 = 0,
    y0: f64 = 0,
    x1: f64 = 0,
    y1: f64 = 0,
};

const ParseData = struct {
    text: []u8,
    index: usize,

    inline fn isAnyMore(self: *ParseData) bool {
        return self.index < self.text.len;
    }

    inline fn currentChar(self: *ParseData) u8 {
        return self.text[self.index];
    }
};

const ParseError = error{ InvalidChar, InvalidKey, InvalidFloat };

fn skipWhitespaces(data: *ParseData) void {
    while (data.index < data.text.len and std.ascii.isWhitespace(data.text[data.index])) {
        data.index += 1;
    }
}

fn consumeChar(data: *ParseData, c: u8) bool {
    if (data.index < data.text.len and data.text[data.index] == c) {
        data.index += 1;
        return true;
    }
    return false;
}

fn readKey(data: *ParseData) ParseError![]u8 {
    if (!consumeChar(data, '"')) {
        // error
        return ParseError.InvalidChar;
    }

    const keyStart = data.index;
    while (data.index < data.text.len) {
        if (data.text[data.index] == '"') {
            break;
        }
        data.index += 1;
    }

    const key = data.text[keyStart..data.index];

    if (!consumeChar(data, '"')) {
        // error
        return ParseError.InvalidChar;
    }

    return key;
}

fn readFloat(data: *ParseData) ParseError!f64 {
    const start = data.index;
    _ = consumeChar(data, '-');

    while (data.isAnyMore()) {
        const c = data.currentChar();
        if (std.ascii.isDigit(c)) {
            data.index += 1;
        } else {
            break;
        }
    }

    if (consumeChar(data, '.')) {
        while (data.isAnyMore()) {
            const c = data.currentChar();
            if (std.ascii.isDigit(c)) {
                data.index += 1;
            } else {
                break;
            }
        }
    }

    if (start >= data.index) {
        // error
        return ParseError.InvalidFloat;
    }

    const textPart = data.text[start..data.index];
    const float = std.fmt.parseFloat(f64, textPart) catch return ParseError.InvalidFloat;
    return float;
}

fn readPointComponent(data: *ParseData, expected_key: []const u8) ParseError!f64 {
    const key = try readKey(data);
    if (!std.mem.eql(u8, expected_key, key)) {
        return ParseError.InvalidKey;
    }
    skipWhitespaces(data);

    if (!consumeChar(data, ':')) {
        return ParseError.InvalidChar;
    }
    skipWhitespaces(data);

    return try readFloat(data);
}

fn readPoint(data: *ParseData) ParseError!PointPair {
    if (!consumeChar(data, '{')) {
        // error
        std.debug.print("consuming point at {d}: {d}\n", .{ data.index, data.text[data.index] });
        return ParseError.InvalidChar;
    }
    skipWhitespaces(data);

    var pair = PointPair{};

    pair.x0 = try readPointComponent(data, "x0");
    skipWhitespaces(data);
    if (!consumeChar(data, ',')) {
        return ParseError.InvalidChar;
    }
    skipWhitespaces(data);

    pair.y0 = try readPointComponent(data, "y0");
    skipWhitespaces(data);
    if (!consumeChar(data, ',')) {
        return ParseError.InvalidChar;
    }
    skipWhitespaces(data);

    pair.x1 = try readPointComponent(data, "x1");
    skipWhitespaces(data);
    if (!consumeChar(data, ',')) {
        return ParseError.InvalidChar;
    }
    skipWhitespaces(data);

    pair.y1 = try readPointComponent(data, "y1");
    skipWhitespaces(data);

    if (!consumeChar(data, '}')) {
        return ParseError.InvalidChar;
    }

    return pair;
}

fn readPoints(text: []u8, allocator: std.mem.Allocator) !std.ArrayList(PointPair) {
    var data = ParseData{ .text = text, .index = 0 };
    var result = std.ArrayList(PointPair).init(allocator);
    skipWhitespaces(&data);
    if (!consumeChar(&data, '{')) {
        // error
        return ParseError.InvalidChar;
    }
    skipWhitespaces(&data);

    const key = try readKey(&data);
    if (!std.mem.eql(u8, "pairs", key)) {
        // error
        return ParseError.InvalidKey;
    }
    skipWhitespaces(&data);

    if (!consumeChar(&data, ':')) {
        // error
        return ParseError.InvalidChar;
    }
    skipWhitespaces(&data);

    if (!consumeChar(&data, '[')) {
        // error
        return ParseError.InvalidChar;
    }
    skipWhitespaces(&data);

    if (data.isAnyMore() and data.currentChar() == '{') {
        skipWhitespaces(&data);
        while (true) {
            const point = try readPoint(&data);
            try result.append(point);
            skipWhitespaces(&data);

            if (!consumeChar(&data, ',')) {
                break;
            }
            skipWhitespaces(&data);
        }
    }

    return result;
}

fn square(a: f64) f64 {
    return a * a;
}

fn radiansFromDegrees(degrees: f64) f64 {
    return 0.01745329251994329577 * degrees;
}

// EarthRadius is generally expected to be 6372.8
fn referenceHaversine(point_pair: PointPair, earthRadius: f64) f64 {
    var lat1 = point_pair.y0;
    var lat2 = point_pair.y1;
    const lon1 = point_pair.x0;
    const lon2 = point_pair.x1;

    const dLat = radiansFromDegrees(lat2 - lat1);
    const dLon = radiansFromDegrees(lon2 - lon1);
    lat1 = radiansFromDegrees(lat1);
    lat2 = radiansFromDegrees(lat2);

    const a = square(math.sin(dLat / 2.0)) + math.cos(lat1) * math.cos(lat2) * square(math.sin(dLon / 2));
    const c = 2.0 * math.asin(math.sqrt(a));

    const result = earthRadius * c;

    return result;
}

pub fn main() !void {
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const args = try std.process.argsAlloc(gpa.backing_allocator);
    const stdout = std.io.getStdOut().writer();
    const timers = std.ArrayList(NameTimer).init(gpa.backing_allocator);
    var timer = TimerData{ .timers = timers };
    timer.init();
    defer timer.timers.deinit();

    if (args.len < 2) {
        try stdout.print("Usage:\n{s} [input.json] [result_check.f64]?\n", .{args[0]});
        return;
    }
    var expected_result: ?f64 = null;
    if (args.len == 3) {
        const file = try std.fs.cwd().openFile(args[2], .{});
        defer file.close();
        const bytes = try file.reader().readAllAlloc(gpa.backing_allocator, maxInt(i32));
        defer gpa.backing_allocator.free(bytes);
        expected_result = try fmt.parseFloat(f64, bytes);
    }

    timer.startTimer("Read file");
    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();
    const bytes = try file.reader().readAllAlloc(gpa.backing_allocator, maxInt(i32));
    defer gpa.backing_allocator.free(bytes);
    try timer.endTimer();

    timer.startTimer("Parse points");
    const points = try readPoints(bytes, gpa.backing_allocator);
    defer points.deinit();
    try timer.endTimer();

    timer.startTimer("Compute haversine for all points");
    var sum: f64 = 0;
    for (points.items) |pair| {
        sum += referenceHaversine(pair, 6372.8);
    }
    const avg_sum = sum / @as(f64, @floatFromInt(points.items.len));
    try timer.endTimer();

    try stdout.print("Computed result: \t{d}\n", .{avg_sum});
    if (expected_result) |exp_res| {
        try stdout.print("Expected result: \t{d}\n", .{exp_res});
        if (exp_res == avg_sum) {
            try stdout.print("Result matches\n", .{});
        } else {
            try stdout.print("Result does not match\n", .{});
        }
    }

    try timer.printResults(stdout);
}
