const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core_dep = b.dependency("wayland-client", .{
        .target = target,
        .optimize = optimize,
    });
    const core_mod = core_dep.module("wayland-client");

    const xdg_shell_dep = b.dependency("wayland-xdg_shell-client", .{
        .target = target,
        .optimize = optimize,
    });
    const xdg_shell_mod = xdg_shell_dep.module("wayland-xdg_shell-client");

    const xdg_decor_dep = b.dependency("wayland-xdg_decoration-client", .{
        .target = target,
        .optimize = optimize,
    });
    const xdg_decor_mod = xdg_decor_dep.module("wayland-xdg_decoration-client");

    const exe = b.addExecutable(.{
        .name = "window_app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("wayland_core", core_mod);
    exe.root_module.addImport("xdg_shell", xdg_shell_mod);
    exe.root_module.addImport("xdg_decor", xdg_decor_mod);
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
