const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const wasm = @import("../web/wasm.zig");
const gl = @import("../web/webgl.zig");
const Actor = @import("Actor.zig");
const Map = @import("../Map.zig");
const models = @import("../models.zig");
const ShaderInfo = @import("../Model.zig").ShaderInfo;

const model = models.findByName("strawberry");

actor: Actor,

pub fn draw(actor: *Actor, si: ShaderInfo) void {
    const t: f32 = @floatCast(wasm.performanceNow() / 1000.0);
    const transform = actor.getTransform()
        .mul(Mat4.fromScale(Vec3.new(3, 3, 3)))
        .mul(Mat4.fromTranslate(Vec3.new(0, 0, 2 * @sin(t * 2)))
        .mul(Mat4.fromRotation(std.math.radiansToDegrees(f32, 3 * t), Vec3.new(0, 0, 1)))
        .mul(Mat4.fromScale(Vec3.new(5, 5, 5))));
    model.draw(si, transform);
}
