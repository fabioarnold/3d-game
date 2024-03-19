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

pub fn draw(actor: *Actor, si: ShaderInfo) void {
    const self = @fieldParentPtr(FloatingDecoration, "actor", actor);
    const t: f32 = @floatCast(wasm.performanceNow() / 1000.0);
    const model_mat = Mat4.fromTranslate(Vec3.new(0, 0, @sin(self.rate * t + self.offset) * 60.0));
    gl.glUniformMatrix4fv(si.model_loc, 1, gl.GL_FALSE, &model_mat.data[0]);
    self.model.draw();
}
