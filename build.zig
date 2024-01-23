const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "main",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addAnonymousImport("zalgebra", .{ .root_source_file = .{ .path = "deps/zalgebra/src/main.zig" } });
    exe.rdynamic = true;
    exe.entry = .disabled;
    b.installArtifact(exe);
}
