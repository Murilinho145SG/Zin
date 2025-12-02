const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zin_mod = b.addModule("zin", .{
        .root_source_file = b.path("lib/zin.zig"),
    });
    
    const exe = b.addExecutable(.{
        .name = "zouter-app",
        .root_module = b.createModule(
            .{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize
            }
        )
    });
    
    exe.root_module.addImport("zin", zin_mod);
        
    b.installArtifact(exe);
    
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step("run", "Run this code");
    run_step.dependOn(&run_cmd.step);
}
