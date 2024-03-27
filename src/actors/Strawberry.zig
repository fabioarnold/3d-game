const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const wasm = @import("../web/wasm.zig");
const gl = @import("../web/webgl.zig");
const Actor = @import("Actor.zig");
const Map = @import("../Map.zig");
const Sprite = @import("../Sprite.zig");
const textures = @import("../textures.zig");
const models = @import("../models.zig");
const ShaderInfo = @import("../Model.zig").ShaderInfo;

const Strawberry = @This();

const model = models.findByName("strawberry");

actor: Actor,

is_collected: bool = false,
bubble_to: ?Vec3 = null,
is_locked: bool = false,
is_collecting: bool = false,

pub fn init(actor: *Actor) void {
    const self = @fieldParentPtr(Strawberry, "actor", actor);
    self.* = .{
        .actor = actor.*,
    };
    self.actor.pickup = .{ .radius = 12 * 5 };
    self.actor.cast_point_shadow = .{};
}

pub fn onPickup(actor: *Actor) void {
    const self = @fieldParentPtr(Strawberry, "actor", actor);
    if (!self.is_collected and !self.is_collecting and !self.is_locked) {
        self.is_collecting = true;
        actor.world.player.strawberryGet(self);
    }
}

pub fn draw(actor: *Actor, si: ShaderInfo) void {
    const t: f32 = @floatCast(wasm.performanceNow() / 1000.0);
    const transform = actor.getTransform()
        .mul(Mat4.fromScale(Vec3.new(3, 3, 3)))
        .mul(Mat4.fromTranslate(Vec3.new(0, 0, 2 * @sin(t * 2)))
        .mul(Mat4.fromRotation(std.math.radiansToDegrees(f32, 3 * t), Vec3.new(0, 0, 1)))
        .mul(Mat4.fromScale(Vec3.new(5, 5, 5))));
    gl.glUniform1f(si.effects_loc, 0);
    model.draw(si, transform);
    gl.glUniform1f(si.effects_loc, 1);

    const halo_color = [4]f32{ @as(f32, 0xee) / 255.0, @as(f32, 0xd1) / 255.0, @as(f32, 0x4f) / 255.0, 0.4 };
    const halo_tex = textures.findByName("gradient");
    const halo_pos = actor.position.add(Vec3.new(0, 0, 2 * 5)); // + Vec3.Transform(Vec3.Zero, Model.Transform);
    actor.world.drawSprite(Sprite.createBillboard(actor.world, halo_pos, halo_tex, 12 * 5, halo_color, false));
}
