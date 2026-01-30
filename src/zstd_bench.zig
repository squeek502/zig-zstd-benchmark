const std = @import("std");
const zstd = std.compress.zstd;
const io = std.io;
const time = std.time;
const path = std.fs.path;
const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;
const Decompress = zstd.Decompress;

const czstd = @import("libzstd");

const KiB = 1024;
const MiB = KiB * 1024;
const GiB = MiB * 1024;
const FILE_LIMITS = 5 * GiB;

const MIN_LEVEL = -7;
const MAX_LEVEL = 19; // should be 22, but Zig does not support "ultra" compression

/// Decompress ZSTD compressed bytes to out n times with C Zstd and return total time elapsed in seconds
fn benchC(compressed: []const u8, out: []u8, n: usize) !f64 {
    var timer = try Timer.start();

    for (0..n) |_| {
        _ = try czstd.decompress(out, out.len, compressed, compressed.len);
    }

    const elapsed_ns = timer.read();
    return @as(f64, @floatFromInt(elapsed_ns)) / time.ns_per_s;
}

/// Decompress ZSTD compressed bytes to out n times with Zig Zstd and return total time elapsed in seconds
fn benchZig(compressed: []const u8, out: []u8, n: usize) !f64 {
    var timer = try Timer.start();

    for (0..n) |_| {
        var writer: io.Writer = .fixed(out);
        var comp_reader: io.Reader = .fixed(compressed);
        var zstd_stream: Decompress = .init(&comp_reader, &.{}, .{});

        _ = try zstd_stream.reader.streamRemaining(&writer);
    }

    const elapsed_ns = timer.read();
    return @as(f64, @floatFromInt(elapsed_ns)) / time.ns_per_s;
}

fn intStrLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    // FIXME: I don't think this is the right way to do things
    const left = std.fmt.parseInt(i8, lhs, 10) catch unreachable;
    const right = std.fmt.parseInt(i8, rhs, 10) catch unreachable;
    return left < right;
}

fn listSubdirs(allocator: Allocator, dir: std.fs.Dir) ![][]const u8 {
    var levels: std.ArrayList([]const u8) = .empty;
    var iter_level = dir.iterate();
    while (try iter_level.next()) |level| {
        if (level.kind == .directory)
            try levels.append(allocator, try std.fmt.allocPrint(allocator, "{s}", .{level.name}));
    }

    return levels.toOwnedSlice(allocator);
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const path_comp = "data/compressed";
    const path_raw = "data/raw";
    const path_csv = "out/runs.csv";
    const csv_header = "Language,Compression level,File,N runs,Total time";
    const n_repeat = 10;

    var comp_dir = try std.fs.cwd().openDir(path_comp, .{ .iterate = true });
    defer comp_dir.close();

    var raw_dir = try std.fs.cwd().openDir(path_raw, .{ .iterate = true });
    defer raw_dir.close();

    std.fs.cwd().makeDir(path.dirname(path_csv).?) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    std.debug.print("Decompression started for {s}:\n", .{path_comp});

    const levels = try listSubdirs(allocator, comp_dir);
    defer {
        for (levels) |level| allocator.free(level);
        allocator.free(levels);
    }

    std.mem.sort([]const u8, levels, {}, intStrLessThan);

    const csv_file = try std.fs.cwd().createFile(path_csv, .{ .truncate = true });
    defer csv_file.close();

    var csv_buffer: [1 * KiB]u8 = undefined;
    var csv_writer = csv_file.writer(&csv_buffer);

    try csv_writer.interface.print("{s}\n", .{csv_header});

    var start_time = try Timer.start();
    for (levels) |level| {
        var level_dir = try comp_dir.openDir(level, .{ .iterate = true });

        var iter_file = level_dir.iterate();
        while (try iter_file.next()) |file| {
            if (file.kind != .file or !std.mem.eql(u8, path.extension(file.name), ".zst"))
                continue;

            const orig_file_name = path.stem(file.name);
            const raw = try raw_dir.readFileAlloc(allocator, orig_file_name, FILE_LIMITS);
            defer allocator.free(raw);

            const compressed = try level_dir.readFileAlloc(allocator, file.name, FILE_LIMITS);
            defer allocator.free(compressed);

            const full_path_comp = try path.join(allocator, &.{ path_comp, level, file.name });
            defer allocator.free(full_path_comp);

            std.debug.print("Decompressing {s}:\n", .{full_path_comp});

            // Zig run
            const out_zig = try allocator.alloc(u8, raw.len + zstd.block_size_max + zstd.default_window_len);
            defer allocator.free(out_zig);
            const elapsed_zig = try benchZig(compressed, out_zig, n_repeat);

            if (!std.mem.eql(u8, out_zig[0..raw.len], raw)) {
                std.debug.print("ERROR: Decompression with Zig mismatched original data! Exiting...", .{});
                std.process.exit(1);
            }

            try csv_writer.interface.print("{s},{s},{s},{d},{d}\n",
                                           .{ "Zig", level, orig_file_name, n_repeat, elapsed_zig });

            std.debug.print(" * Done in Zig for average {d:.3}s!\n",
                            .{elapsed_zig / @as(f64, @floatFromInt(n_repeat))});

            // C run
            const out_c = try allocator.alloc(u8, raw.len);
            defer allocator.free(out_c);
            const elapsed_c = try benchC(compressed, out_c, n_repeat); // TODO: bench streaming

            if (!std.mem.eql(u8, out_c, raw)) {
                std.debug.print("ERROR: Decompression with C mismatched original data! Exiting...", .{});
                std.process.exit(1);
            }

            try csv_writer.interface.print("{s},{s},{s},{d},{d}\n",
                                           .{ "C", level, orig_file_name, n_repeat, elapsed_c });

            std.debug.print(" * Done in C for average {d:.3}s!\n",
                            .{elapsed_c / @as(f64, @floatFromInt(n_repeat))});
        }
        std.debug.print("\n", .{});
    }
    try csv_writer.interface.flush();

    std.debug.print("Benchmarking done in {d:.3}s!\n", .{@as(f64, @floatFromInt(start_time.read())) / time.ns_per_s});
}

test "C decompress" {
    const comp_path = "data/compressed/19/silesia.tar.zst";
    const raw_path = "data/raw/silesia.tar";
    const allocator = std.testing.allocator;

    const comp = try std.fs.cwd().readFileAlloc(allocator, comp_path, FILE_LIMITS);
    defer allocator.free(comp);

    const raw_size = czstd.getFrameContentSize(comp, comp.len);

    const decomp = try allocator.alloc(u8, raw_size);
    defer allocator.free(decomp);

    const decomp_bytes = try czstd.decompress(decomp, raw_size, comp, comp.len);

    try std.testing.expect(decomp_bytes == raw_size);

    const raw = try std.fs.cwd().readFileAlloc(allocator, raw_path, FILE_LIMITS);
    defer allocator.free(raw);

    try std.testing.expect(std.mem.eql(u8, raw, decomp));
}
