const std = @import("std");
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Quat = za.Quat;
const Mat4 = za.Mat4;
const math = @import("../math.zig");
const time = @import("../time.zig");
const controls = @import("../controls.zig");
const World = @import("../World.zig");
const Actor = World.Actor;
const models = @import("../models.zig");
const Model = @import("../Model.zig");
const SkinnedModel = @import("../SkinnedModel.zig");
const logger = std.log.scoped(.player);

const world = &World.world;

const Player = @This();

const acceleration = 500 * 5;
const past_max_decel = 60 * 5;
const air_accel_mult_min = 0.5;
const air_accel_mult_max = 1.0;
const max_speed = 64 * 5;
const rotate_threshold = max_speed * 0.2;
const rotate_speed = 360 * 1.5;
const rotate_speed_above_max = 360 * 1.5;
const friction = 800 * 5;
const air_friction_mult = 0.1;
const gravity = 600 * 5;
const max_fall = -120 * 5;
const jump_hold_time = 0.1;
const jump_speed = 90 * 5;
const coyote_time = 0.12;
const wall_jump_xy_speed = max_speed * 1.3;

const dash_speed = 140 * 5;
const dash_end_speed_mult = 0.75;
const dash_time = 0.2;
const dash_reset_cooldown = 0.2;
const dash_cooldown = 0.1;
const dash_rotate_speed = 360 * 0.3;

const dash_jump_speed = 40 * 5;
const dash_jump_hold_speed = 20 * 5;
const dash_jump_hold_time = 0.3;
const dash_jump_xy_boost = 16 * 5;

const skid_dot_threshold = -0.7;
const skidding_start_accel = 300 * 5;
const skidding_accel = 500 * 5;
const end_skid_speed = max_speed * 0.8;
const skid_jump_speed = 120 * 5;
const skid_jump_hold_time = 0.16;
const skid_jump_xy_speed = max_speed * 1.4;

const wall_pushout_dist = 3 * 5;
const climb_check_dist = 4 * 5;
const climb_speed = 40 * 5;
const climb_hop_up_speed = 80 * 5;
const climb_hop_forward_speed = 40 * 5;
const climb_hop_no_move_time = 0.25;

const footstep_interval = 0.3;

const State = enum {
    normal,
    dashing,
    skidding,
    climbing,
    strawberry_get,
    feather_start,
    feather,
    respawn,
    dead,
    strawberry_reveal,
    cutscene,
    bubble,
    cassette,
};

fn StateMachine(comptime I: type, S: type) type {
    return struct {
        const Self = @This();

        const F = fn (*I) void;
        const Entry = struct {
            updateFn: *const F,
            enterFn: *const F,
            exitFn: *const F,
        };

        instance: *I,
        state: S,
        function_table: [@typeInfo(S).Enum.fields.len]Entry = undefined,

        fn initState(self: *Self, s: S, updateFn: *const F, enterFn: *const F, exitFn: *const F) void {
            self.function_table[@intFromEnum(s)] = .{
                .updateFn = updateFn,
                .enterFn = enterFn,
                .exitFn = exitFn,
            };
        }

        fn update(self: *Self) void {
            self.function_table[@intFromEnum(self.state)].updateFn(self.instance);
        }
    };
}

const Hair = struct {
    something: i32 = 0,
};
const hair_color = [_]f32{ 0.859, 0.173, 0, 1 };

actor: Actor,

dead: bool = false,

model_scale: Vec3 = Vec3.one(),
skinned_model: SkinnedModel,
hair: Hair = Hair{},
point_shadow_alpha: f32 = 1,

velocity: Vec3 = Vec3.zero(),
prev_velocity: Vec3 = Vec3.zero(),
ground_normal: Vec3 = Vec3.new(0, 0, 1),
platform_velocity: Vec3 = Vec3.zero(),
t_plaform_velocity_storage: f32 = 0,
t_ground_snap_cooldown: f32 = 0,
climbing_wall_actor: ?*Actor = null,
climbing_wall_normal: Vec3 = Vec3.zero(),

on_ground: bool = false,
target_facing: Vec2 = Vec2.new(0, 1),
state_machine: StateMachine(Player, State),

t_coyote: f32 = 0,
coyote_z: f32 = 0,

// normal state

t_hold_jump: f32 = 0,
hold_jump_speed: f32 = 0,
auto_jump: bool = false,
t_no_move: f32 = 0,
t_footstep: f32 = 0,

fn solidWaistTestPos(self: Player) Vec3 {
    return self.actor.position.add(Vec3.new(0, 0, 3 * 5));
}
fn solidHeadTestPos(self: Player) Vec3 {
    return self.actor.position.add(Vec3.new(0, 0, 3 * 5));
}
fn inBubble(self: Player) bool {
    return self.state_machine.state == .bubble;
}

pub fn init(actor: *Actor) void {
    const self = @fieldParentPtr(Player, "actor", actor);
    self.* = Player{
        .actor = actor.*,
        .skinned_model = .{ .model = models.findByName("player") },
        .state_machine = undefined,
    };
    self.skinned_model.play("Idle");
    self.setHairColor(hair_color);

    self.state_machine = StateMachine(Player, State){ .instance = self, .state = .normal };
    self.state_machine.initState(.normal, stNormalUpdate, stNormalEnter, stNormalExit);
}

fn relativeMoveInput() Vec2 {
    const rot_y = Quat.fromAxis(world.camera.angles.y(), Vec3.new(0, 0, -1));
    const cam_move = rot_y.rotateVec(Vec3.new(controls.move.x(), controls.move.y(), 0));
    return Vec2.new(cam_move.x(), cam_move.y());
}

fn setHairColor(self: *Player, color: [4]f32) void {
    for (self.skinned_model.model.gltf.data.materials.items) |*material| {
        if (std.mem.eql(u8, material.name, "Hair")) {
            material.metallic_roughness.base_color_factor = color;
        }
    }
}

pub fn update(actor: *Actor) void {
    const self = @fieldParentPtr(Player, "actor", actor);

    // only update camera if not dead
    if (self.state_machine.state != .dead) {
        // rotate camera

        // move camera in / out
    }

    // don't do anything if dead
    if (self.state_machine.state == .dead) {
        self.state_machine.update();
        return;
    }

    // death plane
    if (!self.inBubble()) {
        // TODO: deathblock + spikeblock
        if (self.actor.position.z() < World.death_plane) {
            self.kill();
            return;
        }
    }

    // enter cutscene
    // TODO: if world has active cutscene -> state = .cutscene

    // run timers
    {
        if (self.t_coyote > 0) self.t_coyote -= time.delta;
        if (self.t_hold_jump > 0) self.t_hold_jump -= time.delta;
        if (self.t_ground_snap_cooldown > 0) self.t_ground_snap_cooldown -= time.delta;
    }

    self.prev_velocity = self.velocity;
    self.state_machine.update();

    // move and pop out
    if (!self.inBubble()) {
        // push out of NPCs
        // for (world.actors) if (actor.flags.pushout)

        // handle actual movement
        {
            const amount = self.velocity.scale(time.delta);
            self.sweepTestMove(amount, self.t_no_move <= 0);
        }

        // do an idle popout for good measure
        _ = self.popout(false);
    }

    // TODO: pickups

    // TODO: move to world
    self.lateUpdate();
}

fn lateUpdate(self: *Player) void {
    // TODO: ground checks
    {
        self.on_ground = self.groundCheck() != null;
        if (self.on_ground) {
            self.t_coyote = coyote_time;
        }
    }

    // TODO: update model
    {
        // TODO: approach
        self.actor.angle = math.angleFromXY(self.target_facing);
    }
}

fn jump(self: *Player) void {
    self.velocity.data[2] = jump_speed;
    self.hold_jump_speed = jump_speed;
    self.t_hold_jump = jump_hold_time;
    self.t_coyote = 0;
    self.t_ground_snap_cooldown = 0.1;
}

fn wallJump(self: *Player) void {
    _ = self;
    // TODO
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
    } else if (self.ceilingCheck()) |pushout| {
        self.actor.position = self.actor.position.add(pushout);
        if (resolve_impact) {
            self.velocity.data[2] = @min(0, self.velocity.data[2]);
        }
    }

    // wall test
    for ([_]Vec3{ self.solidWaistTestPos(), self.solidHeadTestPos() }) |test_pos| {
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

fn kill(self: *Player) void {
    self.state_machine.state = .dead;
    // storedCameraForward = cameraTargetForward;
    // storedCameraDistance = cameraTargetDistance;
    // Save.CurrentRecord.Deaths += 1;
    self.dead = true;
}

fn wallJumpCheck(self: *Player) bool {
    if (controls.jump) {
        if (world.solidWallCheckClosestToNormal(
            self.solidWaistTestPos(),
            climb_check_dist,
            Vec3.new(-self.target_facing.x(), -self.target_facing.y(), 0),
        )) |hit| {
            controls.jump = false; // consume
            self.actor.position = self.actor.position.add(hit.pushout.scale(wall_pushout_dist / climb_check_dist));
            const n_xy = Vec2.new(hit.normal.x(), hit.normal.y());
            self.target_facing = n_xy.norm();
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

// state machine functions

fn stNormalEnter(self: *Player) void {
    self.t_hold_jump = 0;
    self.t_footstep = footstep_interval;
}

fn stNormalExit(self: *Player) void {
    self.t_hold_jump = 0;
    self.t_no_move = 0;
    self.auto_jump = false;
    self.skinned_model.rate = 1;
}

fn stNormalUpdate(self: *Player) void {
    // check for NPC interaction
    if (self.on_ground) {
        // TODO for (world.actors) etc.
    }

    // movement
    {
        var vel_xy = Vec2.new(self.velocity.x(), self.velocity.y());
        if (controls.move.eql(Vec2.zero()) or self.t_no_move > 0) {
            // if not moving, simply apply friction

            var fric: f32 = friction;
            if (!self.on_ground) fric *= air_friction_mult;

            vel_xy = math.approachVec2(vel_xy, Vec2.zero(), fric * time.delta);
        } else if (self.on_ground) {
            var max: f32 = max_speed;

            // change max speed based on ground slope angle
            if (!self.ground_normal.eql(Vec3.new(0, 0, 1))) {
                var slope_dot = 1 - self.ground_normal.z();
                const ground_normal_xy = Vec2.new(self.ground_normal.x(), self.ground_normal.y());
                slope_dot *= ground_normal_xy.norm().dot(self.target_facing) * 2.0;
                max += max * slope_dot;
            }

            // true_max is the max XY speed before applying analog stick magnitude
            const true_max = max;

            // apply analog stick magnitude
            {
                const mag = math.clampedMap(controls.move.length(), 0.4, 0.92, 0.3, 1);
                max *= mag;
            }

            var input = relativeMoveInput();

            // TODO: slightly move away from ledges

            // if traveling faster than our "true max" (ie. our max not accounting for analog stick magnitude),
            // then we switch into a slower deceleration to help the player preserve high speeds
            var accel: f32 = acceleration;
            if (vel_xy.dot(vel_xy) >= true_max * true_max and controls.move.dot(vel_xy) >= 0.7) {
                accel = past_max_decel;
            }

            // if our XY velocity is above the Rotate Threshold, then our XY velocity begins rotating
            // instead of using a simple approach to accelerate
            if (vel_xy.dot(vel_xy) >= rotate_threshold * rotate_threshold) {
                if (input.dot(vel_xy.norm()) <= skid_dot_threshold) {
                    self.actor.angle = math.angleFromXY(input);
                    self.target_facing = input;
                    // TODO self.state_machine.state = .skidding;
                    logger.info("stNormalUpdate skidding", .{});

                    return;
                } else {
                    // Rotate speed is less when travelling above our "true max" speed
                    // this gives high speeds less fine control
                    var rotate: f32 = rotate_speed;
                    if (vel_xy.dot(vel_xy) > true_max * true_max) {
                        rotate = rotate_speed_above_max;
                    }

                    // TODO: self.target_facing = math.rotateToward(self.target_facing, input, rotate * time.delta, 0);
                    self.target_facing = input;
                    vel_xy = self.target_facing.scale(math.approach(vel_xy.length(), max, accel * time.delta));
                }
            } else {
                // if we're below the Rotate Threshold, acceleration is very simple
                vel_xy = math.approachVec2(vel_xy, input.scale(max), accel * time.delta);

                self.target_facing = input.norm();
            }
        } else {
            var accel: f32 = acceleration;
            if (vel_xy.dot(vel_xy) >= max_speed * max_speed and vel_xy.norm().dot(relativeMoveInput().norm()) >= 0.7) {
                accel = past_max_decel;

                const dot = Vec2.dot(relativeMoveInput().norm(), self.target_facing);
                accel *= math.clampedMap(dot, -1, 1, air_accel_mult_max, air_accel_mult_min);
            } else {
                accel = acceleration;

                const dot = Vec2.dot(relativeMoveInput().norm(), self.target_facing);
                accel *= math.clampedMap(dot, -1, 1, air_accel_mult_min, air_accel_mult_max);
            }

            vel_xy = math.approachVec2(vel_xy, relativeMoveInput().scale(max_speed), accel * time.delta);
        }

        self.velocity = Vec3.new(vel_xy.x(), vel_xy.y(), self.velocity.z());
    }

    // TODO: footsteps

    // TODO: start climbing

    // TODO: dashing

    // jump & gavity
    if (self.t_coyote > 0 and controls.jump) {
        controls.jump = false; // consume
        self.jump();
    } else if (self.wallJumpCheck()) {
        self.wallJump();
    } else {
        if (self.t_hold_jump > 0 and controls.jump) {
            if (self.velocity.z() < self.hold_jump_speed)
                self.velocity.data[2] = self.hold_jump_speed;
        } else {
            // apply gravity
            self.velocity.data[2] = @max(max_fall, self.velocity.z() - gravity * time.delta);
            self.t_hold_jump = 0;
        }
    }

    // update model animations
    if (self.on_ground) {
        const vel_xy = Vec2.new(self.velocity.x(), self.velocity.y());
        if (vel_xy.dot(vel_xy) > 1) {
            self.skinned_model.play("Run");
            // TODO: map
            // self.skinned_model.rate = Calc.ClampedMap(velXY.Length(), 0, MaxSpeed * 2, 0.1, 3);
        } else {
            self.skinned_model.play("Idle");
        }
    } else {
        // use first frame of running animation
    }
}
