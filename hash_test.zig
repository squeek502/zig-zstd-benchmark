const std = @import("std");

const Timer = std.time.Timer;
const DefaultPrng = std.Random.DefaultPrng;

fn measureKey(func: HashFunc, seed: usize, key: []const u8, repeats: usize) !f64 {
    var timer = try Timer.start();
    for (0..repeats) |_|
        // _ = func(seed, key);
        // _ = func(key, seed);
        _ = std.mem.doNotOptimizeAway(func(key, seed));
    return @as(f64, @floatFromInt(timer.read())) / 1_000_000_000;
}

const HashFunc = fn ([]const u8, u64) usize;

fn arithm_sum1(first: usize, n: usize) usize {
    // Pretty bad formula in terms of overflow I think
    return @divExact((2 * first + n - 1) * n, 2);
}

pub fn main() !void {
    const seed = 34;
    var prng = DefaultPrng.init(seed);
    var rng = prng.random();

    const min_len = 3;
    const max_len = 100;
    const n_per_len = 1000;
    const repeats = 1000;

    const n_keys = comptime arithm_sum1(min_len, max_len - min_len + 1) * n_per_len;

    const allocator = std.heap.smp_allocator;

    var keys = try allocator.alloc(u8, n_keys);
    defer allocator.free(keys);

    rng.bytes(keys);

    const hash_funcs = [_]HashFunc{
        // std.hash.Wyhash.hash,
        // Another argument type
        // std.hash.XxHash64.hash,
        // std.hash.XxHash32.hash,
        // std.hash.XxHash3.hash,
        // Arguments in reverse order...
        std.hash.CityHash64.hashWithSeed,
        // std.hash.Murmur2_32.hashWithSeed,
        std.hash.Murmur2_64.hashWithSeed,
        // std.hash.Murmur3_32.hashWithSeed,
        // Some strange generic I don't understand
        // std.hash.Crc32(...).hash,
        // Implementations without seed
        // std.hash.Adler32.hash,
        // std.hash.Fnv1a_128.hash,
        // std.hash.Fnv1a_32.hash,
        // std.hash.Fnv1a_64.hash,
        // std.hash.CityHash32.hash,
        // Strange hash-functions
        // std.hash.SipHash64(2, 4), std.hash.SipHash128(2, 4),
    };

    inline for (hash_funcs, 0..) |hashFunc, hash_i| {
        var sum_time: f64 = 0;
        for (min_len..max_len + 1) |len| {
            for (0..n_per_len) |repeat_i| {
                const off = arithm_sum1(min_len, len - min_len) * n_per_len + repeat_i;
                const key = keys[off..off + len];
                sum_time += try measureKey(hashFunc, seed, key, repeats);
            }
        }
        std.debug.print("Hasher {d}: {d:.3}s\n", .{ hash_i, sum_time });
    }
}

test "Hash sequential usage" {
    const seed = 34;
    var hasher = std.hash.XxHash64.init(seed);

    hasher.update("VSEM");
    hasher.update("ZIGA");

    const result = hasher.final();

    try std.testing.expectEqual(result, 8607384121065435259);
}

test "Hash single usage" {
    const seed = 34;

    const result = std.hash.xHash64.hash(seed, "VSEMZIGA");

    try std.testing.expectEqual(result, 8607384121065435259);
}
