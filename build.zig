const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{}); // Add optimize options to CLI
    const target = b.standardTargetOptions(.{}); // Add target options to CLI

    var libzstd_mod = b.createModule(.{
        .root_source_file = b.path("libzstd/libzstd.zig"),
        .target = target,
        .optimize = optimize,
    });

    libzstd_mod.addLibraryPath(b.path("zstd/lib"));
    libzstd_mod.linkSystemLibrary("zstd", .{ .preferred_link_mode = .static });
    libzstd_mod.link_libc = true;

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/zstd_bench.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "libzstd", .module = libzstd_mod },
        },
    });

    // Create executable (compilation) step
    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = root_mod,
    });

    b.installArtifact(exe); // Actually install compiled unit

    const single_exe = b.addExecutable(.{
        .name = "zstd_single",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zstd_single.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "libzstd", .module = libzstd_mod },
            },
        }),
    });
    b.installArtifact(single_exe);

    const run_exe = b.addRunArtifact(exe); // Create run step
    const run_step = b.step("run", "Run the application"); // Create new step in CLI called "run"
    run_step.dependOn(&run_exe.step); // Add actual run step into CLI's step

    // Same thing for tests
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/zstd_bench.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "libzstd", .module = libzstd_mod },
        },
    }) });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&run_tests.step);
}
