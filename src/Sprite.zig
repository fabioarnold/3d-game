const za = @import("zalgebra");
const Vec3 = za.Vec3;
const math = @import("math.zig");
const textures = @import("textures.zig");
const Texture = textures.Texture;
const World = @import("World.zig");
const Camera = @import("Camera.zig");

const Sprite = @This();

texture: Texture,
v0: Vec3,
v1: Vec3,
v2: Vec3,
v3: Vec3,
color: [4]f32,

pub fn createShadowSprite(world: *World, position: Vec3, alpha: f32) ?Sprite {
    if (world.solidRayCast(position, Vec3.new(0, 0, -1), 1000 * 5, .{})) |hit| {
        const size = math.clampedMap(hit.distance, 0, 50 * 5, 3 * 5, 2 * 5);
        const a = Vec3.cross(hit.normal, Vec3.new(0, 1, 0)).scale(size);
        const b = Vec3.cross(hit.normal, Vec3.new(1, 0, 0)).scale(size);
        const at = hit.point.add(Vec3.new(0, 0, 0.1 * 5));
        return .{
            .texture = textures.findByName("circle"),
            .v0 = at.sub(a).sub(b),
            .v1 = at.add(a).sub(b),
            .v2 = at.add(a).add(b),
            .v3 = at.sub(a).add(b),
            .color = [4]f32{
                @as(comptime_float, 0x1d) / 255.0 * 0.5 * alpha,
                @as(comptime_float, 0x0b) / 255.0 * 0.5 * alpha,
                @as(comptime_float, 0x44) / 255.0 * 0.5 * alpha,
                0.5 * alpha,
            },
        };
    }
    return null;
}

pub fn createBillboard(camera: *Camera, at: Vec3, texture: Texture, size: f32, color: [4]f32) Sprite {
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
