const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const wasm = @import("../web/wasm.zig");
const gl = @import("../web/webgl.zig");
const Actor = @import("Actor.zig");
const World = @import("../World.zig");
const Map = @import("../Map.zig");
const ShaderInfo = @import("../Model.zig").ShaderInfo;

const FloatingDecoration = @This();

actor: Actor,
model: Map.Model,
rate: f32,
offset: f32,

pub const vtable = Actor.Interface.VTable{
    .added = added,
    .draw = draw,
};

pub fn create(world: *World) !*FloatingDecoration {
    const floating_decoration = try world.allocator.create(FloatingDecoration);
    floating_decoration.* = .{
        .actor = .{.world = world},
        .model = undefined,
        .rate = undefined,
        .offset = undefined,
    };
    return floating_decoration;
}

pub fn added(ptr: *anyopaque) void {
    const self: *FloatingDecoration = @alignCast(@ptrCast(ptr));
    self.rate = self.actor.world.rng.float(f32) * 2 + 1;
    self.offset = self.actor.world.rng.float(f32) * std.math.tau;
    // updateoffscreen
}

pub fn draw(ptr: *anyopaque, si: ShaderInfo) void {
    const self: *FloatingDecoration = @alignCast(@ptrCast(ptr));
    const time = self.actor.world.general_timer * self.rate * 0.25 + self.offset;
    const model_mat = Mat4.fromTranslate(Vec3.new(0, 0, @sin(time) * 12 * 5));
    gl.glUniformMatrix4fv(si.model_loc, 1, gl.GL_FALSE, &model_mat.data[0]);
    self.model.draw();
}
