const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const math = @import("../math.zig");
const time = @import("../time.zig");
const textures = @import("../textures.zig");
const Model = @import("../Model.zig");
const Sprite = @import("../Sprite.zig");
const Actor = @import("Actor.zig");
const World = @import("../World.zig");
const logger = std.log.scoped(.snow);

const Snow = @This();

actor: Actor,
amount: f32,
direction: Vec3,

pub fn create(world: *World, amount: f32, direction: Vec3) !*Actor {
    const dust = try Actor.create(Snow, world);
    dust.amount = amount;
    dust.direction = direction;
    return &dust.actor;
}

pub fn draw(actor: *Actor, si: Model.ShaderInfo) void {
    _ = si;
    const self = @fieldParentPtr(Snow, "actor", actor);

    const texture = textures.findByName("circle");

    const camera_position = actor.world.camera.position;
    const camera_normal = actor.world.camera.forward();

    // TODO: compute bounds of camera frustum
    const box_center = camera_position.add(camera_normal.scale(300 * 5));
    const min = box_center.sub(Vec3.one().scale(300 * 5));
    const max = box_center.add(Vec3.one().scale(300 * 5));
    const area = 100 * 5;
    const t = time.now;

    const x0 = @floor(min.x() / area) * area;
    const y0 = @floor(min.y() / area) * area;
    const z0 = @floor(min.z() / area) * area;
    const x1 = @floor(max.x() / area) * area;
    const y1 = @floor(max.y() / area) * area;
    const z1 = @floor(max.z() / area) * area;

    var x = x0;
    while (x < x1) : (x += area) {
        var y = y0;
        while (y < y1) : (y += area) {
            var z = z0;
            while (z < z1) : (z += area) {
                const center = Vec3.new(x, y, z).add(Vec3.one().scale(area * 0.5));
                if (camera_normal.dot(center.sub(camera_position)) <= 0) {
                    continue;
                }

                const dist = camera_position.sub(center);
                const dist_z = math.clampedMap(dist.z(), 0, 200 * 5, 1, 0);
                if (dist_z <= 0) {
                    continue;
                }

                const input_dist_xy_sqrd = dist.x() * dist.x() + dist.y() * dist.y();
                if (input_dist_xy_sqrd > 300 * 300 * 5 * 5) {
                    continue;
                }

                const dist_xy = math.clampedMap(@sqrt(input_dist_xy_sqrd), 100 * 5, 300 * 5, 1, 0);
                if (dist_xy <= 0) {
                    continue;
                }

                const alpha = dist_xy * dist_z;
                if (alpha < 0.1) {
                    continue;
                }

                // TODO
                // if (!cameraFrustum.Contains(BoundingBox(center, area)))
                //     continue;

                var prng = std.rand.DefaultPrng.init(0);
                const rng = prng.random();
                const count: usize = @intFromFloat(math.lerp(0, 50, dist_xy) * self.amount);
                const color: [4]f32 = .{ 1, 1, 1, alpha };
                for (0..count) |_| {
                    const pos = Vec3.new(
                        x + @mod(rng.float(f32) * area + (5 + rng.float(f32) * 20) * t * self.direction.x() * 5, area),
                        y + @mod(rng.float(f32) * area + (5 + rng.float(f32) * 20) * t * self.direction.y() * 5, area),
                        z + @mod(rng.float(f32) * area + (5 + rng.float(f32) * 20) * t * self.direction.z() * 5, area),
                    );
                    const sprite = Sprite.createBillboard(actor.world, pos, texture, 0.5 * 5, color, false);
                    actor.world.drawSprite(sprite);
                }
            }
        }
    }
}
