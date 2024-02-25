const std = @import("std");
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const Quat = za.Quat;
const Mat4 = za.Mat4;
const zgltf = @import("zgltf");
const math = @import("../math.zig");
const time = @import("../time.zig");
const controls = @import("../controls.zig");
const gl = @import("../web/webgl.zig");
const primitives = @import("../primitives.zig");
const textures = @import("../textures.zig");
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
const jump_xy_boost = 10 * 5;
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

        fn setState(self: *Self, s: S) void {
            self.function_table[@intFromEnum(self.state)].exitFn(self.instance);
            self.state = s;
            self.function_table[@intFromEnum(self.state)].enterFn(self.instance);
        }

        fn update(self: *Self) void {
            self.function_table[@intFromEnum(self.state)].updateFn(self.instance);
        }
    };
}

const Hair = struct {
    wave: f32 = 0,
    nodes: [10]Vec3 = undefined,

    fn update(self: *Hair, transform: Mat4) void {
        self.wave += time.delta;
        const origin = transform.mulByVec4(Vec4.new(0, 1, -0.4, 1));
        // logger.info("origin {d:.2} {d:.2} {d:.2}", .{origin.x(), origin.y(), origin.z()});
        self.nodes[0] = Vec3.new(origin.x(), origin.y(), origin.z());
        for (1..self.nodes.len) |i| {
            self.nodes[i] = self.nodes[i - 1].add(Vec3.new(0, 0.5, -1).scale(1.0 / 15.0));
        }
    }

    fn draw(self: Hair, si: Model.ShaderInfo, transform: Mat4) void {
        gl.glBindTexture(gl.GL_TEXTURE_2D, textures.findByName("white").id);
        gl.glUniform4f(si.color_loc, hair_color[0], hair_color[1], hair_color[2], hair_color[3]);
        for (self.nodes) |node| {
            const sphere_mat = transform.mul(Mat4.fromTranslate(node));
            gl.glUniformMatrix4fv(si.model_loc, 1, gl.GL_FALSE, &sphere_mat.data[0]);
            primitives.drawSphere();
        }
    }
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
t_platform_velocity_storage: f32 = 0,
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

// dashing state
dashes: u32 = 1,
t_dash: f32 = 0,
t_dash_cooldown: f32 = 0,
t_dash_reset_cooldown: f32 = 0,
t_dash_reset_flash: f32 = 0,
t_no_dash_jump: f32 = 0,
dashed_on_ground: bool = false,
dash_trails_created: u32 = 0,

// skidding state
t_no_skid_jump: f32 = 0,

// climbing state
climb_corner_ease: f32 = 0,
climb_corner_from: Vec3 = Vec3.zero(),
climb_corner_to: Vec3 = Vec3.zero(),
climb_corner_facing_from: Vec2 = Vec2.zero(),
climb_corner_facing_to: Vec2 = Vec2.zero(),
climb_corner_camera_from: ?Vec2 = null,
climb_corner_camera_to: ?Vec2 = null,
climb_input_sign: u32 = 1,
t_climb_cooldown: f32 = 0,

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
    self.state_machine.initState(.skidding, stSkiddingUpdate, stSkiddingEnter, stSkiddingExit);
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
        if (self.t_dash_cooldown > 0) self.t_dash_cooldown -= time.delta;
        if (self.t_dash_reset_flash > 0) self.t_dash_reset_flash -= time.delta;
        if (self.t_no_move > 0) self.t_no_move -= time.delta;
        if (self.t_platform_velocity_storage > 0) self.t_platform_velocity_storage -= time.delta;
        if (self.t_ground_snap_cooldown > 0) self.t_ground_snap_cooldown -= time.delta;
        if (self.t_climb_cooldown > 0) self.t_climb_cooldown -= time.delta;
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
    // ground checks
    {
        const prev_on_ground = self.on_ground;
        if (self.groundCheck()) |result| {
            self.on_ground = true;
            self.actor.position = self.actor.position.add(result.pushout);

            // on ground
            self.auto_jump = false;
            self.ground_normal = result.normal;
            self.t_coyote = coyote_time;
            self.coyote_z = self.actor.position.z();
            // if (tDashResetCooldown <= 0)
            //     RefillDash();
        } else {
            self.on_ground = false;
            self.ground_normal = Vec3.new(0, 0, 1);
        }

        // TODO: ground snap

        if (!prev_on_ground and self.on_ground) {
            const t = math.clampedMap(self.prev_velocity.z(), 0, max_fall, 0, 1);
            self.model_scale = Vec3.lerp(Vec3.one(), Vec3.new(1.4, 1.4, 0.6), t);
            // TODO: landing
        }
    }

    // TODO: update model
    {
        self.model_scale.xMut().* = math.approach(self.model_scale.x(), 1, time.delta / 0.8);
        self.model_scale.yMut().* = math.approach(self.model_scale.y(), 1, time.delta / 0.8);
        self.model_scale.zMut().* = math.approach(self.model_scale.z(), 1, time.delta / 0.8);

        self.actor.angle = math.approachAngle(
            self.actor.angle,
            math.angleFromDir(self.target_facing),
            2 * 360 * time.delta,
        );

        self.skinned_model.update();
    }

    // hair
    {
        const z_up = Mat4.fromRotation(90, Vec3.new(1, 0, 0));
        var hair_matrix = Mat4.identity();
        const gltf_data = &self.skinned_model.model.gltf.data;
        for (gltf_data.nodes.items) |node| {
            if (std.mem.eql(u8, node.name, "Head")) {
                hair_matrix = .{ .data = zgltf.getGlobalTransform(gltf_data, node) };
                hair_matrix = z_up.mul(hair_matrix);
                break;
            }
        }
        self.hair.update(hair_matrix);
    }
}

fn cancelGroundSnap(self: *Player) void {
    self.t_ground_snap_cooldown = 0.1;
}

fn jump(self: *Player) void {
    self.actor.position.data[2] = self.coyote_z;
    self.velocity.data[2] = jump_speed;
    self.hold_jump_speed = jump_speed;
    self.t_hold_jump = jump_hold_time;
    self.t_coyote = 0;
    self.auto_jump = false;

    var input = relativeMoveInput();
    if (!input.eql(Vec2.zero())) {
        input = input.norm();
        self.target_facing = input;
        self.velocity.data[0] += input.x() * jump_xy_boost;
        self.velocity.data[1] += input.y() * jump_xy_boost;
    }

    self.cancelGroundSnap();

    // AddPlatformVelocity(true);
    self.cancelGroundSnap();

    self.model_scale = Vec3.new(0.6, 0.6, 1.4);
    // Audio.Play(Sfx.sfx_jump, Position);
}

fn wallJump(self: *Player) void {
    self.hold_jump_speed = jump_speed;
    self.velocity.data[2] = jump_speed;
    self.t_hold_jump = jump_hold_time;
    self.auto_jump = false;

    const vel_xy = self.target_facing.scale(wall_jump_xy_speed);
    self.velocity.data[0] = vel_xy.x();
    self.velocity.data[1] = vel_xy.y();

    // AddPlatformVelocity(false);
    self.cancelGroundSnap();

    self.model_scale = Vec3.new(0.6, 0.6, 1.4);
    // Audio.Play(Sfx.sfx_jump, Position);
}

fn skidJump(self: *Player) void {
    self.actor.position.data[2] = self.coyote_z;
    self.hold_jump_speed = skid_jump_speed;
    self.velocity.data[2] = skid_jump_speed;
    self.t_hold_jump = skid_jump_hold_time;
    self.t_coyote = 0;

    const vel_xy = self.target_facing.scale(skid_jump_xy_speed);
    self.velocity.data[0] = vel_xy.x();
    self.velocity.data[1] = vel_xy.y();

    // AddPlatformVelocity(false);
    self.cancelGroundSnap();

    // for (int i = 0; i < 16; i ++)
    // {
    // 	var dir = new Vec3(Calc.AngleToVector((i / 16f) * MathF.Tau), 0);
    // 	World.Request<Dust>().Init(Position + dir * 8, new Vec3(velocity.XY() * 0.5f, 10) - dir * 50, 0x666666);
    // }

    self.model_scale = Vec3.new(0.6, 0.6, 1.4);
    // Audio.Play(Sfx.sfx_jump, Position);
    // Audio.Play(Sfx.sfx_jump_skid, Position);
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
    self.state_machine.setState(.dead);
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
    const self = @fieldParentPtr(Player, "actor", actor);
    const scale = Mat4.fromScale(self.model_scale.scale(15));
    const transform = actor.getTransform();
    self.skinned_model.draw(si, transform.mul(scale));

    self.hair.draw(si, transform.mul(scale));
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
                    self.actor.angle = math.angleFromDir(input);
                    self.target_facing = input;
                    self.state_machine.setState(.skidding);
                    return;
                } else {
                    // Rotate speed is less when travelling above our "true max" speed
                    // this gives high speeds less fine control
                    var rotate: f32 = rotate_speed;
                    if (vel_xy.dot(vel_xy) > true_max * true_max) {
                        rotate = rotate_speed_above_max;
                    }

                    var facing_angle = math.angleFromDir(self.target_facing);
                    facing_angle = math.approachAngle(facing_angle, math.angleFromDir(input), rotate * time.delta);
                    self.target_facing = math.dirFromAngle(facing_angle);
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
            self.skinned_model.rate = math.clampedMap(vel_xy.length(), 0, max_speed * 2, 0.1, 3);
        } else {
            self.skinned_model.play("Idle");
            self.skinned_model.rate = 1;
        }
    } else {
        // use first frame of running animation
        self.skinned_model.t = 0;
        self.skinned_model.play("Run");
    }
}

fn tryDash(self: *Player) bool {
    if (self.dashes > 0 and self.t_dash_cooldown <= 0 and controls.dash) {
        controls.dash = false; // consume
        self.dashes -= 1;
        self.state_machine.setState(.dashing);
        return true;
    }
    return false;
}

fn stSkiddingEnter(self: *Player) void {
    self.t_no_skid_jump = 0.1;
    self.skinned_model.play("Skid");
    // Audio.Play(Sfx.sfx_skid, Position);

    // for (int i = 0; i < 5; i ++)
    //  World.Request<Dust>().Init(Position + new Vec3(targetFacing, 0) * i, new Vec3(-targetFacing, 0.0f).Normalized() * 50, 0x666666);
}

fn stSkiddingExit(self: *Player) void {
    self.skinned_model.play("Idle");
}

fn stSkiddingUpdate(self: *Player) void {
    if (self.t_no_skid_jump > 0)
        self.t_no_skid_jump -= time.delta;

    if (self.tryDash())
        return;

    if (relativeMoveInput().length() < 0.2 or relativeMoveInput().dot(self.target_facing) < 0.7 or !self.on_ground) {
        //cancelling
        self.state_machine.setState(.normal);
        return;
    } else {
        var vel_xy = Vec2.new(self.velocity.x(), self.velocity.y());

        // skid jump
        if (self.t_no_skid_jump <= 0 and controls.jump) {
            controls.jump = false; // consume
            self.state_machine.setState(.normal);
            self.skidJump();
            return;
        }

        const dot_matches = vel_xy.norm().dot(self.target_facing) >= 0.7;

        // acceleration
        const accel: f32 = if (dot_matches) skidding_accel else skidding_start_accel;
        vel_xy = math.approachVec2(vel_xy, relativeMoveInput().scale(max_speed), accel * time.delta);
        self.velocity = Vec3.new(vel_xy.x(), vel_xy.y(), self.velocity.z());

        // reached target
        if (dot_matches and vel_xy.length() >= end_skid_speed) {
            self.state_machine.setState(.normal);
            return;
        }
    }
}
