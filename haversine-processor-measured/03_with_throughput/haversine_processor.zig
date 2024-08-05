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

fn getCPUFrequencyWindows(msToWait: u64) u64 {
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

const ProfilerAnchor = struct {
    elapsed_total: u64 = 0,
    elapsed_children: u64 = 0,
    processed_byte_count: u64 = 0,
};

const ProfilerZone = struct {
    start_time: u64,
    profiler: *ProfilerData,
    anchor_index: usize,
    parent_index: ?usize,
    old_elapsed_total: u64 = 0,

    fn endZone(self: *ProfilerZone) void {
        self.profiler.endZone(self);
    }

    fn endZoneBytes(self: *ProfilerZone, byte_count: u64) void {
        self.profiler.endZoneBytes(self, byte_count);
    }
};

const ProfilerData = struct {
    cpu_frequency: u64 = 0,
    anchors: [4096]ProfilerAnchor = undefined,
    anchor_names: []const []const u8 = undefined,
    anchors_count: usize = 0,
    curr_anchor_index: ?usize = null,
    profile_start: u64 = 0,
    profile_end: u64 = 0,

    fn init(self: *ProfilerData, anchor_names: []const []const u8) void {
        self.cpu_frequency = getCPUFrequency(100);
        self.anchor_names = anchor_names;
        self.anchors_count = anchor_names.len;
    }

    fn startProfile(self: *ProfilerData) void {
        self.profile_start = readTimeStamp();
    }

    fn endProfile(self: *ProfilerData) void {
        self.profile_end = readTimeStamp();
    }

    fn startZone(self: *ProfilerData, anchor_id: anytype) ProfilerZone {
        return startZoneBytes(self, anchor_id, 0);
    }

    // Use either startZoneBytes or endZoneBytes for each zone, but on both.
    fn startZoneBytes(self: *ProfilerData, anchor_id: anytype, byte_count: u64) ProfilerZone {
        const index = @intFromEnum(anchor_id);

        const parent_index = self.curr_anchor_index;
        self.curr_anchor_index = index;

        self.anchors[index].processed_byte_count += byte_count;

        return ProfilerZone {
            .start_time = readTimeStamp(),
            .profiler = self,
            .anchor_index = index,
            .parent_index = parent_index,
            .old_elapsed_total = self.anchors[index].elapsed_total,
        };
    }

    fn endZone(self: *ProfilerData, zone: *ProfilerZone) void {
        endZoneBytes(self, zone, 0);
    }

    fn endZoneBytes(self: *ProfilerData, zone: *ProfilerZone, byte_count: u64) void {
        const start_time = zone.start_time;
        const end_time = readTimeStamp();
        const elapsed = end_time - start_time;
        const anchor = &self.anchors[zone.anchor_index];

        anchor.processed_byte_count += byte_count;
        
        if (zone.parent_index) |parent_index| {
            const parent = &self.anchors[parent_index];
            parent.elapsed_children += elapsed;
        }
        self.curr_anchor_index = zone.parent_index;

        anchor.elapsed_total = zone.old_elapsed_total + elapsed;
    }

    fn printResults(self: *ProfilerData, out: std.fs.File.Writer) !void {
        const total: u64 = self.profile_end - self.profile_start;

        const ms_elapsed = total * 1000 / self.cpu_frequency;
        const minutes = @divTrunc(ms_elapsed, std.time.ms_per_min);
        const seconds = (ms_elapsed % std.time.ms_per_min) / std.time.ms_per_s;
        const ms = (ms_elapsed % std.time.ms_per_s);

        try out.print("Total time: ~{d}:{d}.{d} ({d} ticks, {d} approximate frequency\n", .{ minutes, seconds, ms, total, self.cpu_frequency });
        var i: usize = 0;
        while (i < self.anchors_count) {
            const anchor = self.anchors[i];
            const zone_name = self.anchor_names[i];
            const elapsed_exclusive = anchor.elapsed_total - anchor.elapsed_children;
            const elapsed_inclusive = anchor.elapsed_total;
            const percents: f64 = @as(f64, @floatFromInt(elapsed_exclusive)) * 100 / @as(f64, @floatFromInt(total));
            try out.print("\t {d}. {s} -- {d} ticks, {d:.2}%", .{ i + 1, zone_name, elapsed_exclusive, percents });
            if (elapsed_exclusive != elapsed_inclusive) {
                const percents_with_children = @as(f64, @floatFromInt(elapsed_inclusive)) * 100 / @as(f64, @floatFromInt(total));
                try out.print(", w/ children {d} ticks, {d:.2}%", .{ elapsed_inclusive, percents_with_children });
            }

            if (anchor.processed_byte_count != 0) {
                const megabytes = @as(f64, @floatFromInt(anchor.processed_byte_count)) / (1024.0 * 1024.0);
                const gigabytes = megabytes / 1024.0;
                const gigabytes_per_second = @as(f64, @floatFromInt(self.cpu_frequency)) * gigabytes / @as(f64, @floatFromInt(elapsed_inclusive));
                try out.print(" {d:.2} mb, {d:.2} gb/sec", .{megabytes, gigabytes_per_second});
            }

            try out.print("\n", .{});
            i += 1;
        }
    }
};

const TimerStep = enum {
    readFile,
    parsePoints,
    parseFirstComponent,
    computeHaversine,
};

const haversine_anchor_names = [_][]const u8{
    "Read file",
    "Parse points",
    "Parse first component",
    "Compute haversine",
};

var haversine_profiler = ProfilerData{};

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

    var first_zone = haversine_profiler.startZone(TimerStep.parseFirstComponent);
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
    first_zone.endZone();

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

    haversine_profiler.init(&haversine_anchor_names);
    haversine_profiler.startProfile();

    var readFileZone = haversine_profiler.startZone(TimerStep.readFile);
    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();
    const bytes = try file.reader().readAllAlloc(gpa.backing_allocator, maxInt(i32));
    defer gpa.backing_allocator.free(bytes);
    readFileZone.endZoneBytes(bytes.len);

    var parse_points_zone = haversine_profiler.startZone(TimerStep.parsePoints);
    const points = try readPoints(bytes, gpa.backing_allocator);
    defer points.deinit();
    parse_points_zone.endZone();

    var compute_zone = haversine_profiler.startZoneBytes(TimerStep.computeHaversine, points.items.len * @sizeOf(PointPair));
    var sum: f64 = 0;
    for (points.items) |pair| {
        sum += referenceHaversine(pair, 6372.8);
    }
    const avg_sum = sum / @as(f64, @floatFromInt(points.items.len));
    compute_zone.endZone();

    try stdout.print("Computed result: \t{d}\n", .{avg_sum});
    if (expected_result) |exp_res| {
        try stdout.print("Expected result: \t{d}\n", .{exp_res});
        if (exp_res == avg_sum) {
            try stdout.print("Result matches\n", .{});
        } else {
            try stdout.print("Result does not match\n", .{});
        }
    }

    haversine_profiler.endProfile();
    try haversine_profiler.printResults(stdout);
}
