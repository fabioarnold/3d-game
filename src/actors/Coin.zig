const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const math = @import("../math.zig");
const time = @import("../time.zig");
const easings = @import("../easings.zig");
const textures = @import("../textures.zig");
const models = @import("../models.zig");
const Sprite = @import("../Sprite.zig");
const Model = @import("../Model.zig");
const World = @import("../World.zig");
const Game = @import("../Game.zig");
const Actor = @import("Actor.zig");
const game = &Game.game;

const Coin = @This();

const model = models.findByName("coin");

actor: Actor,
collected: bool = false,

pub const vtable = Actor.Interface.VTable{
    .pickup = pickup,
    .draw = draw,
};

pub fn create(world: *World) !*Coin {
    const self = try world.allocator.create(Coin);
    self.* = .{
        .actor = .{
            .world = world,
            .pickup = .{ .radius = 20 * 5 },
            .cast_point_shadow = .{},
        },
    };
    return self;
}

pub fn pickup(ptr: *anyopaque) void {
    const self: *Coin = @alignCast(@ptrCast(ptr));
    if (!self.collected) {
        self.collected = true;
        // Audio
    }
}

pub fn draw(ptr: *anyopaque, si: Model.ShaderInfo) void {
    const self: *Coin = @alignCast(@ptrCast(ptr));
    const actor = &self.actor;
    const world = actor.world;

    const inactive_color = [4]f32{ @as(f32, 0x5f) / 255.0, @as(f32, 0xcd) / 255.0, @as(f32, 0xe4) / 255.0, 1 };
    const collected_color = [4]f32{ @as(f32, 0xf1) / 255.0, @as(f32, 0x41) / 255.0, @as(f32, 0xdf) / 255.0, 0.5 };

    for (model.gltf.data.materials.items) |*material| {
        material.metallic_roughness.base_color_factor = if (self.collected) collected_color else inactive_color;
    }

    const model_mat = actor.getTransform()
        .mul(Mat4.fromRotation(std.math.radiansToDegrees(f32, world.general_timer * 3), Vec3.new(0, 0, 1)))
        .mul(Mat4.fromTranslate(Vec3.new(0, 0, @sin(world.general_timer * 2) * 2 * 5)))
        .mul(Mat4.fromScale(Vec3.one().scale(6 * 5)));
    model.draw(si, model_mat);

    if (!self.collected) {
        var halo_color = inactive_color;
        halo_color[3] = 0.5;
        const halo_tex = textures.findByName("gradient");
        const halo_pos = actor.position.add(Vec3.new(0, 0, 2 * 5)); // + Vec3.Transform(Vec3.Zero, Model.Transform);
        actor.world.drawSprite(Sprite.createBillboard(actor.world, halo_pos, halo_tex, 10 * 5, halo_color, false));
    }
}
