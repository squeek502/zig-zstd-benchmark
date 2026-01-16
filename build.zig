const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});  // Add optimize options to CLI
    const target = b.standardTargetOptions(.{}); // Add target options to CLI

    // Create executable (compilation) step
    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zstd_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe); // Actually install compiled unit

    const run_exe = b.addRunArtifact(exe);  // Create run step
    const run_step = b.step("run", "Run the application");  // Create new step in CLI called "run"
    run_step.dependOn(&run_exe.step);  // Add actual run step into CLI's step

    // Same thing for tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zstd_test.zig"),
            .target = target,
        })
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&run_tests.step);
}
