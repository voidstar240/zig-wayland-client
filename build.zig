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
        if (args.len < 1) @panic("No input file");
        if (args.len > 1) @panic("Too many input args");
        scanner_step.addArg(args[0]); // specify path to protocol xml file
    }
    const output = scanner_step.addOutputFileArg("protcol.zig"); // gen file 
    const wf = b.addWriteFiles();
    wf.addCopyFileToSource(output, "src/protocol.zig");
    scanner_step.addArg("root"); // where to pull types from
    scanner_step.addArg("wl_"); // what prefix to use for this library
    scanner_step.addArg("root.zig root"); // import <1> as <2>

    const update_step = b.step("update", "update protocol using system files");
    update_step.dependOn(&wf.step);

    // Export Root Module
    const zwayland = b.addModule("zwayland", .{
        .root_source_file = b.path("src/root.zig"),
    });

    // Tests
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("zwayland", zwayland);
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
