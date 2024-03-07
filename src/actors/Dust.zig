const std = @import("std");
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const math = @import("../math.zig");
const time = @import("../time.zig");
const textures = @import("../textures.zig");
const Sprite = @import("../Sprite.zig");
const Model = @import("../Model.zig");
const World = @import("../World.zig");
const Actor = @import("Actor.zig");

const world = &World.world;

const Dust = @This();

const images = [5][]const u8{ "dust_0", "dust_1", "dust_2", "dust_3", "dust_4" };

actor: Actor,
velocity: Vec3 = Vec3.zero(),
image: textures.Texture,
color: [4]f32,
percent: f32 = 0,
duration: f32,

pub fn init(actor: *Actor) void {
    const self = @fieldParentPtr(Dust, "actor", actor);
    self.* = .{
        .actor = actor.*,
        .image = textures.findByName(images[world.rng.uintLessThan(usize, images.len)]),
        .color = undefined,
        .duration = 0.5 + 0.5 * world.rng.float(f32),
    };
}

const CreateOptions = struct {
    color: [4]f32 = [4]f32{ 0.7, 0.75, 0.8, 1 },
};

pub fn create(allocator: std.mem.Allocator, position: Vec3, velocity: Vec3, options: CreateOptions) !*Actor {
    const dust = try Actor.create(Dust, allocator);
    dust.actor.position = position;
    dust.velocity = velocity;
    dust.color = options.color;
    // UpdateOffScreen = true;
    return &dust.actor;
}

pub fn update(actor: *Actor) void {
    const self = @fieldParentPtr(Dust, "actor", actor);
    actor.position = actor.position.add(self.velocity.scale(time.delta));
    self.velocity.zMut().* += 5 * 10 * time.delta;

    var v_xy = self.velocity.toVec2();
    v_xy = math.approachVec2(v_xy, Vec2.zero(), 5 * 200 * time.delta);
    self.velocity = v_xy.toVec3(self.velocity.z());

    self.percent += time.delta / self.duration;
    if (self.percent >= 1) {
        self.percent = 1;
        world.destroy(actor);
    }
}

pub fn draw(actor: *Actor, si: Model.ShaderInfo) void {
    _ = si;
    const self = @fieldParentPtr(Dust, "actor", actor);
    world.drawSprite(Sprite.createBillboard(world, actor.position, self.image, 5 * 4 * (1.0 - self.percent), self.color, false));
}
