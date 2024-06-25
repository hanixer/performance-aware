const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const maxInt = std.math.maxInt;

const PointPair = struct {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
};

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

fn generateUniform(rand: std.Random) PointPair {
    return PointPair{
        .x0 = rand.float(f64) * 360.0 - 180.0,
        .y0 = rand.float(f64) * 180.0 - 90.0,
        .x1 = rand.float(f64) * 360.0 - 180.0,
        .y1 = rand.float(f64) * 180.0 - 90.0,
    };
}

pub fn main() !void {
    const ms_start = std.time.milliTimestamp();
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const args = try std.process.argsAlloc(gpa.backing_allocator);
    const stdout = std.io.getStdOut().writer();

    if (args.len != 4 or (std.mem.eql(u8, args[1], "uniform") and std.mem.eql(u8, args[1], "cluster"))) {
        try stdout.print("Usage:\n{s} [uniform/cluster] [random seed] [number of points]\n", .{args[0]});
        return;
    }

    const is_uniform = std.mem.eql(u8, args[1], "uniform");
    _ = is_uniform;

    const seed = try fmt.parseInt(u64, args[2], 10);
    const points_count = try fmt.parseInt(usize, args[3], 10);

    var buf: [256]u8 = undefined;
    const json_name = try fmt.bufPrint(&buf, "data_{d}_{s}.json", .{ points_count, args[1] });
    const json_file = try std.fs.cwd().createFile(json_name, .{});
    defer json_file.close();
    var json_writer = std.io.bufferedWriter(json_file.writer());

    const answer_name = try fmt.bufPrint(&buf, "data_{d}_{s}_answer.f64", .{ points_count, args[1] });
    const answer_file = try std.fs.cwd().createFile(answer_name, .{});
    defer answer_file.close();

    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();

    _ = try json_writer.write("{\"pairs\":[\n");
    var sum: f64 = 0;
    for (0..points_count) |i| {
        const pair = generateUniform(rand);
        sum += referenceHaversine(pair, 6372.8);
        const maybe_comma = if (i == points_count - 1) "" else ",";
        const line = try fmt.bufPrint(&buf, "\t{{\"x0\":{d}, \"y0\":{d}, \"x1\":{d}, \"y1\":{d}}}{s}\n", .{ pair.x0, pair.y0, pair.x1, pair.y1, maybe_comma });
        _ = try json_writer.write(line);
    }
    _ = try json_writer.write("]}");
    try json_writer.flush();

    const avg_sum = sum / @as(f64, @floatFromInt(points_count));
    const answer = try fmt.bufPrint(&buf, "{d}", .{avg_sum});
    _ = try answer_file.writer().write(answer);
    try stdout.print("{d}\n", .{avg_sum});
    const ms_end = std.time.milliTimestamp();

    const diff = ms_end - ms_start;
    try stdout.print("Seconds: {d}\n", .{@divTrunc(diff, std.time.ms_per_s)});
    try stdout.print("Milliseconds: {d}\n", .{@rem(diff, std.time.ms_per_s)});
}
