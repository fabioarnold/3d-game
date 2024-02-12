const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const models = @import("../models.zig");
const Model = @import("../Model.zig");
const SkinnedModel = @import("../SkinnedModel.zig");
const World = @import("../World.zig");
const Actor = World.Actor;
const world = &World.world;

const Player = @This();

actor: Actor,
skinned_model: SkinnedModel,

velocity: Vec3,

const hair_color = [_]f32{ 0.859, 0.173, 0, 1 };

pub fn init(actor: *Actor) void {
    const self = @fieldParentPtr(Player, "actor", actor);
    self.skinned_model.model = models.findByName("player");
    self.skinned_model.play("Idle");
    self.setHairColor(hair_color);
    self.velocity = Vec3.zero();
}

fn setHairColor(self: *Player, color: [4]f32) void {
    for (self.skinned_model.model.gltf.data.materials.items) |*material| {
        if (std.mem.eql(u8, material.name, "Hair")) {
            material.metallic_roughness.base_color_factor = color;
        }
    }
}

pub fn update(actor: *Actor, dt: f32) void {
    const self = @fieldParentPtr(Player, "actor", actor);

    actor.position = actor.position.add(self.velocity.scale(dt));
}

fn groundCheck(self: *Player) bool {
    if (world.solidRayCast(self.actor.position.add(Vec3.new(0, 0, 5)), Vec3.new(0, 0, -5.01))) |hit| {
        _ = hit;
        return true;
    }
    return false;
}

pub fn draw(actor: *Actor, si: Model.ShaderInfo) void {
    const player = @fieldParentPtr(Player, "actor", actor);
    const transform = Mat4.fromScale(Vec3.new(15, 15, 15));
    const model_mat = actor.getTransform().mul(transform);
    player.skinned_model.draw(si, model_mat);
}
