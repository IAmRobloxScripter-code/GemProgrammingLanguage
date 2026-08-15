const std = @import("std");

pub fn build(builder: *std.Build) void {
    const exe = builder.addExecutable(.{
        .name = "gem",
        .root_module = builder.createModule(.{
            .root_source_file = builder.path("src/main.zig"),
            .target = builder.standardTargetOptions(.{}),
            .optimize = .ReleaseFast,
        }),
    });

    builder.installArtifact(exe);

    const run = builder.addRunArtifact(exe);
    if (builder.args) |args| {
        run.addArgs(args);
    }

    const run_step = builder.step("run", "Run the application");
    run_step.dependOn(&run.step);
}
