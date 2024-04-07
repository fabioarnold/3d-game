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

const Dust = @This();

const images = [5][]const u8{ "dust_0", "dust_1", "dust_2", "dust_3", "dust_4" };

actor: Actor,
velocity: Vec3 = Vec3.zero(),
image: textures.Texture,
color: [4]f32,
percent: f32 = 0,
duration: f32,

const CreateOptions = struct {
    color: [4]f32 = [4]f32{ 0.7, 0.75, 0.8, 1 },
};

pub const vtable = Actor.Interface.VTable{
    .update = update,
    .draw = draw,
};

pub fn create(world: *World, position: Vec3, velocity: Vec3, options: CreateOptions) !*Dust {
    const self = try world.allocator.create(Dust);
    self.* = .{
        .actor = .{ .world = world, .position = position, },
        .velocity = velocity,
        .image = textures.findByName(images[world.rng.uintLessThan(usize, images.len)]),
        .color = options.color,
        .duration = 0.5 + 0.5 * world.rng.float(f32),
    };
    // UpdateOffScreen = true;
    return self;
}

pub fn update(ptr: *anyopaque) void {
    const self: *Dust = @alignCast(@ptrCast(ptr));
    self.actor.position = self.actor.position.add(self.velocity.scale(time.delta));
    self.velocity.zMut().* += 5 * 10 * time.delta;

    var v_xy = self.velocity.toVec2();
    v_xy = math.approachVec2(v_xy, Vec2.zero(), 5 * 200 * time.delta);
    self.velocity = v_xy.toVec3(self.velocity.z());

    self.percent += time.delta / self.duration;
    if (self.percent >= 1) {
        self.percent = 1;
        self.actor.world.destroy(Actor.Interface.make(Dust, self));
    }
}

pub fn draw(ptr: *anyopaque, si: Model.ShaderInfo) void {
    _ = si;
    const self: *Dust = @alignCast(@ptrCast(ptr));
    self.actor.world.drawSprite(Sprite.createBillboard(self.actor.world, self.actor.position, self.image, 5 * 4 * (1.0 - self.percent), self.color, false));
}
