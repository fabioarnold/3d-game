const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const optimize = b.standardOptimizeOption(.{});
    const zalgebra_dep = b.dependency("zalgebra", .{ .target = target, .optimize = optimize });
    const zgltf_dep = b.dependency("zgltf", .{ .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{
        .name = "main",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zalgebra", zalgebra_dep.module("zalgebra"));
    exe.root_module.addImport("zgltf", zgltf_dep.module("zgltf"));
    exe.root_module.addAnonymousImport("assets", .{ .root_source_file = .{ .path = "Content/assets.zig" } });
    exe.rdynamic = true;
    exe.entry = .disabled;
    b.installArtifact(exe);
}
