const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const wasm = @import("../web/wasm.zig");
const gl = @import("../web/webgl.zig");
const Actor = @import("Actor.zig");
const Map = @import("../Map.zig");
const ShaderInfo = @import("../Model.zig").ShaderInfo;

const FloatingDecoration = @This();

actor: Actor,
model: Map.Model,
rate: f32,
offset: f32,

pub fn added(actor: *Actor) void {
    const self = @fieldParentPtr(FloatingDecoration, "actor", actor);
    self.rate = actor.world.rng.float(f32) * 2 + 1;
    self.offset = actor.world.rng.float(f32) * std.math.tau;
    // updateoffscreen
}

pub fn draw(actor: *Actor, si: ShaderInfo) void {
    const self = @fieldParentPtr(FloatingDecoration, "actor", actor);
    const time = actor.world.general_timer * self.rate * 0.25 + self.offset;
    const model_mat = Mat4.fromTranslate(Vec3.new(0, 0, @sin(time) * 12 * 5));
    gl.glUniformMatrix4fv(si.model_loc, 1, gl.GL_FALSE, &model_mat.data[0]);
    self.model.draw();
}
