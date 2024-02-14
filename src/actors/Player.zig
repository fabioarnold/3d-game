const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const wasm = @import("../web/wasm.zig");
const keys = @import("../web/keys.zig");
const World = @import("../World.zig");
const Actor = World.Actor;
const models = @import("../models.zig");
const Model = @import("../Model.zig");
const SkinnedModel = @import("../SkinnedModel.zig");

const world = &World.world;

const Player = @This();

const gravity = 600 * 5;
const max_fall = -120 * 5;
const jump_hold_time = 0.1;
const jump_speed = 90 * 5;
const coyote_time = 0.12;

const wall_pushout_dist = 3 * 5;

actor: Actor,
skinned_model: SkinnedModel,

velocity: Vec3,
t_ground_snap_cooldown: f32,

t_hold_jump: f32,
hold_jump_speed: f32,
t_coyote: f32,

const hair_color = [_]f32{ 0.859, 0.173, 0, 1 };

pub fn init(actor: *Actor) void {
    const self = @fieldParentPtr(Player, "actor", actor);
    self.skinned_model.model = models.findByName("player");
    self.skinned_model.play("Idle");
    self.setHairColor(hair_color);
    self.velocity = Vec3.zero();
    self.t_ground_snap_cooldown = 0;
    self.t_hold_jump = 0;
    self.hold_jump_speed = 0;
    self.t_coyote = 0;
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

    const jump_pressed = wasm.isKeyDown(keys.KEY_SPACE) or wasm.isButtonDown(0);

    // TODO: state machine
    if (self.t_coyote > 0 and jump_pressed) { // TODO: consume press
        self.jump();
    } else {
        if (self.t_hold_jump > 0 and jump_pressed) {
            if (self.velocity.z() < self.hold_jump_speed)
                self.velocity.data[2] = self.hold_jump_speed;
        } else {
            // apply gravity
            self.velocity.data[2] = @max(max_fall, self.velocity.z() - gravity * dt);
            self.t_hold_jump = 0;
        }
    }

    // run timers
    {
        if (self.t_coyote > 0) self.t_coyote -= dt;
        if (self.t_hold_jump > 0) self.t_hold_jump -= dt;
        if (self.t_ground_snap_cooldown > 0) self.t_ground_snap_cooldown -= dt;
    }

    // Handle movement
    const amount = self.velocity.scale(dt);
    self.sweepTestMove(amount, true); // tNoMove <= 0

    self.lateUpdate();
}

// TODO: call this from world
fn lateUpdate(self: *Player) void {
    const on_ground = self.groundCheck() != null;
    if (on_ground) {
        self.t_coyote = coyote_time;
    }
}

fn jump(self: *Player) void {
    self.velocity.data[2] = jump_speed;
    self.hold_jump_speed = jump_speed;
    self.t_hold_jump = jump_hold_time;
    self.t_coyote = 0;
    self.t_ground_snap_cooldown = 0.1;
}

fn sweepTestMove(self: *Player, delta: Vec3, resolve_impact: bool) void {
    var resolve_wall_impact = true;

    const length_squared = delta.dot(delta);
    if (length_squared < std.math.floatEps(f32)) return;

    var remaining = @sqrt(length_squared);
    const step_size = 2.0 * 5;
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

    if (self.ceilingCheck()) |pushout| {
        self.actor.position = self.actor.position.add(pushout);
        if (resolve_impact) {
            self.velocity.data[2] = @min(0, self.velocity.data[2]);
        }
    }

    const solid_waist_test_pos = self.actor.position.add(Vec3.new(0, 0, 3 * 5));
    const solid_head_test_pos = self.actor.position.add(Vec3.new(0, 0, 10 * 5));
    for ([_]Vec3{ solid_waist_test_pos, solid_head_test_pos }) |test_pos| {
        if (world.solidWallCheckNearest(test_pos, wall_pushout_dist)) |hit| {
            self.actor.position = self.actor.position.add(hit.pushout);
            if (resolve_impact) {
                const dot = @min(0, self.velocity.norm().dot(hit.normal));
                self.velocity = self.velocity.sub(hit.normal.scale(self.velocity.length() * dot));
            }
            return true;
        }
    }

    return false;
}

const GroundCheckResult = struct {
    pushout: Vec3,
    normal: Vec3,
    floor: ?*Actor,
};
fn groundCheck(self: *Player) ?GroundCheckResult {
    const distance = 5 * 5;
    const point = self.actor.position.add(Vec3.new(0, 0, distance));
    if (world.solidRayCast(point, Vec3.new(0, 0, -1), distance + 0.01, .{})) |hit| {
        return .{
            .pushout = hit.point.sub(self.actor.position),
            .normal = hit.normal,
            .floor = hit.actor,
        };
    }
    return null;
}

fn ceilingCheck(self: *Player) ?Vec3 {
    const height = 12 * 5;

    const point = self.actor.position.add(Vec3.new(0, 0, 1));
    if (world.solidRayCast(point, Vec3.new(0, 0, 1), height - 1, .{})) |hit| {
        return hit.point.sub(self.actor.position.add(Vec3.new(0, 0, height)));
    }
    return null;
}

pub fn draw(actor: *Actor, si: Model.ShaderInfo) void {
    const player = @fieldParentPtr(Player, "actor", actor);
    const transform = Mat4.fromScale(Vec3.new(15, 15, 15));
    const model_mat = actor.getTransform().mul(transform);
    player.skinned_model.draw(si, model_mat);
}
