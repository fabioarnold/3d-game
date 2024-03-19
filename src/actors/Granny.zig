const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const wasm = @import("../web/wasm.zig");
const gl = @import("../web/webgl.zig");
const Actor = @import("Actor.zig");
const Map = @import("../Map.zig");
const models = @import("../models.zig");
const SkinnedModel = @import("../SkinnedModel.zig");
const ShaderInfo = @import("../Model.zig").ShaderInfo;

const Granny = @This();

actor: Actor,
skinned_model: SkinnedModel,

pub fn init(actor: *Actor) void {
    const granny = @fieldParentPtr(Granny, "actor", actor);
    actor.cast_point_shadow = .{};
    granny.skinned_model = .{ .model = models.findByName("granny") };
    granny.skinned_model.play("Idle");
}

pub fn draw(actor: *Actor, si: ShaderInfo) void {
    const granny = @fieldParentPtr(Granny, "actor", actor);
    const transform = Mat4.fromScale(Vec3.new(15, 15, 15)).mul(Mat4.fromTranslate(Vec3.new(0, 0, -0.5)));
    const model_mat = actor.getTransform().mul(transform);
    granny.skinned_model.update();
    granny.skinned_model.draw(si, model_mat);
}
