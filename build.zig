const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.dependency("libadvent", .{}).module("libadvent");

    const step_tests = b.step("test", "Run tests");

    for (1..12) |i| {
        const name = std.fmt.allocPrint(b.allocator, "day{d:02}", .{i}) catch unreachable;
        const file = std.fmt.allocPrint(b.allocator, "src/day/{d:02}.zig", .{i}) catch unreachable;
        const desc = std.fmt.allocPrint(b.allocator, "Run solution for Day {d}", .{i}) catch unreachable;

        const mod = b.createModule(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "libadvent", .module = lib },
            },
        });

        const exe = b.addExecutable(.{
            .name = name,
            .root_module = mod,
        });

        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        run.step.dependOn(b.getInstallStep());

        const step = b.step(name, desc);
        step.dependOn(&run.step);

        const tests = b.addTest(.{
            .root_module = mod,
        });

        const run_tests = b.addRunArtifact(tests);
        step_tests.dependOn(&run_tests.step);

        if (b.args) |args| {
            run.addArgs(args);
        }
    }
}
