const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const math = @import("../math.zig");
const time = @import("../time.zig");
const textures = @import("../textures.zig");
const models = @import("../models.zig");
const Sprite = @import("../Sprite.zig");
const Model = @import("../Model.zig");
const World = @import("../World.zig");
const Game = @import("../Game.zig");
const Actor = @import("Actor.zig");
const game = &Game.game;

const Cassette = @This();

const model = models.findByName("tape_1");
const model_collected = models.findByName("tape_2");

actor: Actor,
map: []const u8,
t_cooldown: f32 = 0,
t_wiggle: f32 = 0,

fn isCollected(self: *Cassette) bool {
    _ = self;
    // TODO
    return false;
}

pub fn init(actor: *Actor) void {
    const self = @fieldParentPtr(Cassette, "actor", actor);
    self.* = .{
        .actor = actor.*,
        .map = undefined, // set by create
    };
    self.actor.pickup = .{ .radius = 16 * 5 };
    self.actor.cast_point_shadow = .{};
}

pub fn create(world: *World, map: []const u8) !*Cassette {
    const self = try Actor.create(Cassette, world);
    self.map = map;
    return self;
}

pub fn setCooldown(self: *Cassette) void {
    self.t_cooldown = 1;
}

pub fn update(actor: *Actor) void {
    const self = @fieldParentPtr(Cassette, "actor", actor);
    actor.cast_point_shadow.?.alpha = if (self.isCollected()) 0.5 else 1;
    self.t_cooldown = math.approach(self.t_cooldown, 0, time.delta);
    self.t_wiggle = math.approach(self.t_wiggle, 0, time.delta / 0.7);
}

pub fn onPickup(actor: *Actor) void {
    const self = @fieldParentPtr(Cassette, "actor", actor);
    if (!self.isCollected() and self.t_cooldown <= 0 and !game.isMidTransition()) {
        self.actor.world.player.stop();
        self.actor.world.player.enterCassette(self);
        self.t_wiggle = 1;
    }
}

pub fn playerExit(self: *Cassette) void {
    self.t_wiggle = 1;
}

pub fn draw(actor: *Actor, si: Model.ShaderInfo) void {
    const self = @fieldParentPtr(Cassette, "actor", actor);
    const world = actor.world;
    const wiggle = 1 + @sin(self.t_wiggle * std.math.tau * 2) * 0.8 * self.t_wiggle;
    const model_mat = actor.getTransform()
        .mul(Mat4.fromRotation(std.math.radiansToDegrees(f32, world.general_timer * 3), Vec3.new(0, 0, 1)))
        .mul(Mat4.fromTranslate(Vec3.new(0, 0, @sin(world.general_timer * 2) * 2)))
        .mul(Mat4.fromScale(Vec3.one().scale(2.5 * wiggle * 5)));
    if (self.isCollected()) {
        model_collected.draw(si, model_mat);
    } else {
        model.draw(si, model_mat);
    }

    if (self.t_wiggle > 0) {
        const ring_tex = textures.findByName("ring");
        const color = [4]f32{ 1, 1, 1, 0.4 };
        actor.world.drawSprite(Sprite.createBillboard(actor.world, actor.position, ring_tex, self.t_wiggle * self.t_wiggle * 40 * 5, color, true));
        actor.world.drawSprite(Sprite.createBillboard(actor.world, actor.position, ring_tex, self.t_wiggle * 50 * 5, color, true));
    }
}
