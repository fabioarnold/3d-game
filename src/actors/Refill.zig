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

const Refill = @This();

const model = models.findByName("refill_gem");
const model_double = models.findByName("refill_gem_double");

actor: Actor,
is_double: bool,
t_cooldown: f32 = 0,
t_collect: f32 = 0,

pub fn init(actor: *Actor) void {
    const self = @fieldParentPtr(Refill, "actor", actor);
    self.* = .{
        .actor = actor.*,
        .is_double = undefined, // set by create
    };
    self.actor.pickup = .{ .radius = 20 * 5 };
    self.actor.cast_point_shadow = .{};
}

pub fn create(world: *World, is_double: bool) !*Refill {
    const self = try Actor.create(Refill, world);
    self.is_double = is_double;
    return self;
}

pub fn update(actor: *Actor) void {
    const self = @fieldParentPtr(Refill, "actor", actor);

    if (self.t_cooldown > 0) {
        self.t_cooldown -= time.delta;
        if (self.t_cooldown <= 0) {
            // UpdateOffScreen = false;
            // Audio.Play(IsDouble ? Sfx.sfx_dashcrystal_double_return : Sfx.sfx_dashcrystal_return, Position);
        }
    }

    if (self.t_collect > 0) {
        self.t_collect -= time.delta * 3;
    }
    actor.cast_point_shadow.?.alpha = if (self.t_collect <= 0) 1 else 0;

    // Particles.SpawnParticle(
    // 	Position + new Vec3(6 - World.Rng.Float() * 12, 6 - World.Rng.Float() * 12, 6 - World.Rng.Float() * 12),
    // 	new Vec3(0, 0, 0), 1);
    // Particles.Update(Time.Delta);
}

pub fn onPickup(actor: *Actor) void {
    const self = @fieldParentPtr(Refill, "actor", actor);
    const count: u32 = if (self.is_double) 2 else 1;
    if (self.t_cooldown <= 0 and actor.world.player.dashes < count) {
        // actor.update_offscreen = true;
        actor.world.player.refillDash(count);
        self.t_cooldown = 4;
        self.t_collect = 1;
        // actor.world.hit_stun = 0.05;
        // Audio.Play(IsDouble ? Sfx.sfx_dashcrystal_double : Sfx.sfx_dashcrystal, Position);
    }
}

pub fn draw(actor: *Actor, si: Model.ShaderInfo) void {
    const self = @fieldParentPtr(Refill, "actor", actor);

    if (self.t_cooldown <= 0) {
        const world = actor.world;
        const model_mat = actor.getTransform()
            .mul(Mat4.fromRotation(std.math.radiansToDegrees(f32, world.general_timer * 3), Vec3.new(0, 0, 1)))
            .mul(Mat4.fromTranslate(Vec3.new(0, 0, @sin(world.general_timer * 2) * 2)))
            .mul(Mat4.fromScale(Vec3.one().scale(2 * 5)));
        if (self.is_double) {
            model_double.draw(si, model_mat);
        } else {
            model.draw(si, model_mat);
        }
    }

    if (self.t_collect > 0) {
        const size = (1 - easings.inCubic(self.t_collect)) * 50 * 5;
        const alpha = self.t_collect;
        const pos = actor.position.add(Vec3.new(0, 0, 3 * 5));
        const ring_tex = textures.findByName("ring");
        var color = [4]f32{ 1, 1, 1, alpha * alpha };
        actor.world.drawSprite(Sprite.createBillboard(actor.world, pos, ring_tex, size * 0.75, color, true));
        color[3] = alpha;
        actor.world.drawSprite(Sprite.createBillboard(actor.world, pos, ring_tex, size, color, true));
    }
}
