const std = @import("std");
const zstd = std.compress.zstd;
const io = std.io;

const czstd = @import("libzstd");

const expected_raw = @embedFile("silesia.tar");
const input_compressed = @embedFile("silesia.tar.zst");

/// Decompress ZSTD compressed bytes to out n times with C Zstd and return total time elapsed in seconds
fn benchC(compressed: []const u8, out: []u8) !void {
    _ = try czstd.decompress(out, out.len, compressed, compressed.len);
}

/// Decompress ZSTD compressed bytes to out n times with Zig Zstd and return total time elapsed in seconds
fn benchZig(compressed: []const u8, out: []u8) !void {
    var writer: io.Writer = .fixed(out);
    var comp_reader: io.Reader = .fixed(compressed);
    var zstd_stream: zstd.Decompress = .init(&comp_reader, &.{}, .{});

    _ = try zstd_stream.reader.streamRemaining(&writer);
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const out = try allocator.alloc(u8, expected_raw.len + zstd.block_size_max + zstd.default_window_len);
    defer allocator.free(out);

    if (args.len > 1 and std.mem.eql(u8, args[1], "c")) {
        try benchC(input_compressed, out);
    } else {
        try benchZig(input_compressed, out);
    }
}
