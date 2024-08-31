const std = @import("std");

pub fn build(b: *std.Build) void {
    // Protocol Generation
    const scanner = b.addExecutable(.{
        .name = "scanner",
        .root_source_file = b.path("src/scanner/main.zig"),
        .target = b.host,
    });

    const scanner_step = b.addRunArtifact(scanner);
    if (b.args) |args| {
        scanner_step.addArgs(args);
    }
    const output = scanner_step.addOutputFileArg("wayland.zig");
    const wf = b.addWriteFiles();
    wf.addCopyFileToSource(output, "src/protocol.zig");

    const update_step = b.step("update", "update protocol using system files");
    update_step.dependOn(&wf.step);

    // Export Root Module
    _ = b.addModule("zwayland", .{
        .root_source_file = b.path("src/root.zig"),
    });

    // Export Scanner Module
    _ = b.addModule("xwayland", .{
        .root_source_file = b.path("src/scanner/main.zig"),
    });

    // Tests
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
