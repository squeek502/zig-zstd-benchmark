const std = @import("std");
const zstd = std.compress.zstd;
const Decompress = zstd.Decompress;
const Reader = std.io.Reader;
const time = std.time;
const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;

const KiB = 1024;
const MiB = KiB * 1024;
const FILE_LIMITS = 1024 * MiB; // FIXME: do it somehow else

const MIN_LEVEL = -7;
const MAX_LEVEL = 19;  // TODO: should be 22, but Zig does not support ultra compression

fn readerCompare(self: *Reader, other: *Reader, buffer: []u8) Reader.ShortError!bool {
    const buffer1 = buffer[0..@divFloor(buffer.len, 2)];
    const buffer2 = buffer[@divFloor(buffer.len, 2)..];

    while (true) {
        const offset1 = try self.readSliceShort(buffer1);
        const offset2 = try other.readSliceShort(buffer2);

        if (offset1 != offset2 or !std.mem.eql(u8, buffer1[0..offset1], buffer2[0..offset2]))
            return false;

        if (offset1 < buffer1.len)
            return true;
    }
}

test "Cmp readers" {
    const text1 = "111111111";
    const text2 = "111111111";

    var reader1 = Reader.fixed(text1);
    var reader2 = Reader.fixed(text2);

    var cmp_buffer: [4 * KiB]u8 = undefined;

    try std.testing.expect(try readerCompare(&reader1, &reader2, &cmp_buffer));
}

test "Cmp zstd" {
    const path_comp = "/home/ultragreed/Work/ZigProjects/zig-hash/data/10/xml.zst";
    const path_orig = "/home/ultragreed/Work/ZigProjects/zig-hash/data/raw/xml";

    const file_comp = try std.fs.cwd().openFile(path_comp, .{});
    defer file_comp.close();
    var read_buffer1: [8 * KiB]u8 = undefined;
    var f_reader1 = file_comp.reader(&read_buffer1);

    const file_orig = try std.fs.cwd().openFile(path_orig, .{});
    defer file_orig.close();
    var read_buffer2: [8 * KiB]u8 = undefined;
    var f_reader2 = file_comp.reader(&read_buffer2);

    var cmp_buffer: [8 * KiB]u8 = undefined;
    try std.testing.expect(try readerCompare(&f_reader1.interface, &f_reader2.interface, &cmp_buffer));
}

fn benchmark(compressed: []const u8) !f64 {
    var reader: std.io.Reader = .fixed(compressed);
    var zstd_buffer: [32 * MiB]u8 = undefined;
    var zstd_stream: Decompress = .init(&reader, &zstd_buffer, .{});

    var timer = try Timer.start();

    _ = try zstd_stream.reader.defaultDiscard(.unlimited);

    const elapsed_ns = timer.read();
    return @as(f64, @floatFromInt(elapsed_ns)) / time.ns_per_s;
}

fn levelLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {  // FIXME: eto pozorishe
    const left = std.fmt.parseInt(i8, lhs, 10) catch return false;
    const right = std.fmt.parseInt(i8, rhs, 10) catch return false;
    return left < right;
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const path_in = "data_compressed";

    var comp_dir = try std.fs.cwd().openDir(path_in, .{.iterate = true});
    defer comp_dir.close();

    std.debug.print("Decompression started for {s}:\n", .{path_in});

    var levels: std.ArrayList([]const u8) = .{};
    var iter_level = comp_dir.iterate();
    while (try iter_level.next()) |level| {
        if (level.kind == .directory)
            (try levels.addOne(allocator)).* = level.name;
    }

    std.mem.sort([]const u8, levels.items, {}, levelLessThan);  // TODO: DO BETTER

    for (levels.items) |level_name| {
        var level_dir = try comp_dir.openDir(level_name, .{.iterate = true});

        var iter_file = level_dir.iterate();
        while (try iter_file.next()) |file| {
            if (file.kind != .file or !std.mem.eql(u8, std.fs.path.extension(file.name), ".zst"))
                continue;

            const full_path = try std.fs.path.join(allocator, &.{path_in, level_name, file.name});
            std.debug.print("Decompressing {s}: ", .{full_path});

            const compressed = try level_dir.readFileAlloc(allocator, file.name, FILE_LIMITS);
            defer allocator.free(compressed);

            const elapsed = try benchmark(compressed);
            
            std.debug.print("done in {}s!\n", .{elapsed});
        }
        std.debug.print("\n", .{});
    }
}
