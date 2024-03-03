const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Texture = @import("textures.zig").Texture;
const Camera = @import("Camera.zig");

const Sprite = @This();

texture: Texture,
v0: Vec3,
v1: Vec3,
v2: Vec3,
v3: Vec3,
color: [4]f32,

pub fn createBillboard(camera: Camera, at: Vec3, texture: Texture, size: f32, color: [4]f32) Sprite {
    const left = camera.left().scale(size);
    const up = camera.up().scale(size);
    return .{
        .texture = texture,
        .v0 = at.add(left).add(up),
        .v1 = at.sub(left).add(up),
        .v2 = at.sub(left).sub(up),
        .v3 = at.add(left).sub(up),
        .color = color,
    };
}
