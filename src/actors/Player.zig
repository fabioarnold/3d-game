const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const World = @import("../World.zig");
const Actor = World.Actor;
const models = @import("../models.zig");
const Model = @import("../Model.zig");
const SkinnedModel = @import("../SkinnedModel.zig");

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

    // Handle movement
    const amount = self.velocity.scale(dt);
    self.sweepTestMove(amount, true); // tNoMove <= 0
}

fn sweepTestMove(self: *Player, delta: Vec3, resolve_impact: bool) void {
    if (delta.dot(delta) <= 0) return;

    var resolve_wall_impact = true;

    var remaining = delta.length();
    const step_size = 2.0; // TODO: increase step size?
    const step_normal = delta.scale(1.0 / remaining);

    while (remaining > 0) {
        const step = @min(remaining, step_size);
        remaining -= step;
        self.actor.position = self.actor.position.add(step_normal.scale(step));

        if (self.popout(resolve_impact and resolve_wall_impact)) {
            // don't repeatedly resolve wall impacts
            resolve_wall_impact = false;
        }
    }
}

// returns true if popped out of a wall
fn popout(self: *Player, resolve_impact: bool) bool {
    if (self.groundCheck()) |result| {
        self.actor.position = self.actor.position.add(result.pushout);
        if (resolve_impact) {
            self.velocity.data[2] = @max(0, self.velocity.data[2]);
        }
    }

    // TODO: ceiling, walls

    return false;
}

const GroundCheckResult = struct {
    pushout: Vec3,
    normal: Vec3,
    floor: ?*Actor,
};
fn groundCheck(self: *Player) ?GroundCheckResult {
    const point = self.actor.position.add(Vec3.new(0, 0, 5));
    if (world.solidRayCast(point, Vec3.new(0, 0, -1), 5.01, .{})) |hit| {
        return .{
            .pushout = hit.point.sub(self.actor.position),
            .normal = hit.normal,
            .floor = hit.actor,
        };
    }
    return null;
}

pub fn draw(actor: *Actor, si: Model.ShaderInfo) void {
    const player = @fieldParentPtr(Player, "actor", actor);
    const transform = Mat4.fromScale(Vec3.new(15, 15, 15));
    const model_mat = actor.getTransform().mul(transform);
    player.skinned_model.draw(si, model_mat);
}
