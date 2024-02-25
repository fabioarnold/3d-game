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
const half_grav_threshold = 100 * 5;
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
const color_normal = [_]f32{ @as(comptime_float, 0xdb) / 255.0, @as(comptime_float, 0x2c) / 255.0, 0, 1 };
const color_no_dash = [_]f32{ @as(comptime_float, 0x6e) / 255.0, @as(comptime_float, 0xc0) / 255.0, 1, 1 };
const color_two_dashes = [_]f32{ @as(comptime_float, 0xfa) / 255.0, @as(comptime_float, 0x91) / 255.0, 1, 1 };
const color_refill_flash = [_]f32{ 1, 1, 1, 1 };
const color_feather = [_]f32{ @as(comptime_float, 0xf2) / 255.0, @as(comptime_float, 0xd4) / 255.0, @as(comptime_float, 0x50) / 255.0, 1 };

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
camera_target_forward: Vec3 = Vec3.new(0, 1, 0),
camera_target_distance: f32 = 0.5,
state_machine: StateMachine(Player, State),

t_coyote: f32 = 0,
coyote_z: f32 = 0,

last_dash_hair_color: [4]f32 = undefined,

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
climb_input_sign: f32 = 1,
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
    self.state_machine.initState(.dashing, stDashingUpdate, stDashingEnter, stDashingExit);
    self.state_machine.initState(.skidding, stSkiddingUpdate, stSkiddingEnter, stSkiddingExit);
    self.state_machine.initState(.climbing, stClimbingUpdate, stClimbingEnter, stClimbingExit);
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
        if (self.t_dash_reset_cooldown > 0) self.t_dash_reset_cooldown -= time.delta;
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
            if (self.t_dash_reset_cooldown <= 0) {
                self.refillDash(1);
            }
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

    // update model
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

        if (self.state_machine.state != .feather and self.state_machine.state != .feather_start) {
            var color: [4]f32 = undefined;
            if (self.t_dash_reset_flash > 0) {
                color = color_refill_flash;
            } else if (self.dashes == 1) {
                color = color_normal;
            } else if (self.dashes == 0) {
                color = color_no_dash;
            } else {
                color = color_two_dashes;
            }
            self.setHairColor(color);
        }
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
    self.velocity.zMut().* = jump_speed;
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

    self.addPlatformVelocity(true);
    self.cancelGroundSnap();

    self.model_scale = Vec3.new(0.6, 0.6, 1.4);
    // Audio.Play(Sfx.sfx_jump, Position);
}

fn wallJump(self: *Player) void {
    self.hold_jump_speed = jump_speed;
    self.velocity.zMut().* = jump_speed;
    self.t_hold_jump = jump_hold_time;
    self.auto_jump = false;

    const vel_xy = self.target_facing.scale(wall_jump_xy_speed);
    self.velocity.data[0] = vel_xy.x();
    self.velocity.data[1] = vel_xy.y();

    self.addPlatformVelocity(false);
    self.cancelGroundSnap();

    self.model_scale = Vec3.new(0.6, 0.6, 1.4);
    // Audio.Play(Sfx.sfx_jump, Position);
}

fn skidJump(self: *Player) void {
    self.actor.position.zMut().* = self.coyote_z;
    self.hold_jump_speed = skid_jump_speed;
    self.velocity.zMut().* = skid_jump_speed;
    self.t_hold_jump = skid_jump_hold_time;
    self.t_coyote = 0;

    const vel_xy = self.target_facing.scale(skid_jump_xy_speed);
    self.velocity.data[0] = vel_xy.x();
    self.velocity.data[1] = vel_xy.y();

    self.addPlatformVelocity(false);
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

fn dashJump(self: *Player) void {
    self.actor.position.zMut().* = self.coyote_z;
    self.velocity.zMut().* = dash_jump_speed;
    self.hold_jump_speed = dash_jump_hold_speed;
    self.t_hold_jump = dash_jump_hold_time;
    self.t_coyote = 0;
    self.auto_jump = false;
    self.dashes = 1;

    if (dash_jump_xy_boost != 0) {
        var input = relativeMoveInput();
        if (!input.eql(Vec2.zero())) {
            input = input.norm();
            self.target_facing = input;
            self.velocity = self.velocity.add(Vec3.new(input.x(), input.y(), 0).scale(dash_jump_xy_boost));
        }
    }

    self.addPlatformVelocity(false);
    self.cancelGroundSnap();

    self.model_scale = Vec3.new(0.6, 0.6, 1.4);
    // Audio.Play(Sfx.sfx_jump, Position);
    // Audio.Play(Sfx.sfx_jump_superslide, Position);
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
            self.velocity.zMut().* = @max(0, self.velocity.z());
        }
    } else if (self.ceilingCheck()) |pushout| {
        self.actor.position = self.actor.position.add(pushout);
        if (resolve_impact) {
            self.velocity.zMut().* = @min(0, self.velocity.z());
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

fn addPlatformVelocity(self: *Player, play_sound: bool) void {
    if (self.t_platform_velocity_storage > 0) {
        var add = self.platform_velocity;
        const add_xy = Vec2.new(add.x(), add.y());

        add.zMut().* = std.math.clamp(add.z(), 0, 180 * 5);
        const add_xy_length = add_xy.length();
        if (add_xy_length > 300 * 5) {
            add.xMut().* *= 300 + 5 / add_xy_length;
            add.yMut().* *= 300 + 5 / add_xy_length;
        }

        self.velocity = self.velocity.add(add);
        self.platform_velocity = Vec3.zero();
        self.t_platform_velocity_storage = 0;

        if (play_sound and (add.z() >= 10 * 5 or add_xy_length > 10 * 5)) {
            //audio.play(sfx.sfx_jump_assisted, position);
        }
    }
}

fn kill(self: *Player) void {
    self.state_machine.setState(.dead);
    // storedCameraForward = cameraTargetForward;
    // storedCameraDistance = cameraTargetDistance;
    // Save.CurrentRecord.Deaths += 1;
    self.dead = true;
}

fn climbCheckAt(self: Player, offset: Vec3) ?World.WallHit {
    const dir = Vec3.new(-self.target_facing.x(), -self.target_facing.y(), 0);
    if (world.solidWallCheckClosestToNormal(self.solidWaistTestPos().add(offset), climb_check_dist, dir)) |hit| {
        const rel_input = relativeMoveInput();
        const hit_normal_xy = Vec2.new(hit.normal.x(), hit.normal.y());
        if (rel_input.eql(Vec2.zero()) or hit_normal_xy.dot(rel_input) <= -0.5 and climbNormalCheck(hit.normal)) {
            return hit;
        }
    }
    return null;
}

fn tryClimb(self: *Player) bool {
    var result = self.climbCheckAt(Vec3.zero());

    // let us snap up to walls if we're jumping for them
    // note: if vel.z is allowed to be downwards then we awkwardly re-grab when sliding off
    // the bottoms of walls, which is really bad feeling
    if (result == null and self.velocity.z() > 0 and !self.on_ground and self.state_machine.state != .climbing) {
        result = self.climbCheckAt(Vec3.new(0, 0, 4 * 5));
    }

    if (result) |wall| {
        self.climbing_wall_normal = wall.normal;
        self.climbing_wall_actor = wall.actor;
        var move_to = wall.point.add(self.actor.position.sub(self.solidWaistTestPos())).add(wall.normal.scale(wall_pushout_dist));
        self.sweepTestMove(move_to.sub(self.actor.position), false);
        const climbing_wall_normal_xy = Vec2.new(self.climbing_wall_normal.x(), self.climbing_wall_normal.y());
        self.target_facing = climbing_wall_normal_xy.norm().scale(-1);
        return true;
    } else {
        self.climbing_wall_actor = null;
        self.climbing_wall_normal = Vec3.zero();
        return false;
    }
}

fn climbNormalCheck(normal: Vec3) bool {
    return @abs(normal.z()) < 0.35;
}

fn floorNormalCheck(normal: Vec3) bool {
    return !climbNormalCheck(normal) and normal.z() > 0;
}

fn wallJumpCheck(self: *Player) bool {
    if (controls.jump.pressed) {
        if (world.solidWallCheckClosestToNormal(
            self.solidWaistTestPos(),
            climb_check_dist,
            Vec3.new(-self.target_facing.x(), -self.target_facing.y(), 0),
        )) |hit| {
            controls.jump.pressed = false; // consume
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

    // start climbing
    if (controls.climb.down and self.t_climb_cooldown <= 0 and self.tryClimb()) {
        self.state_machine.setState(.climbing);
        return;
    }

    // dashing
    if (self.tryDash()) return;

    // jump & gavity
    if (self.t_coyote > 0 and controls.jump.consumePress()) {
        self.jump();
    } else if (self.wallJumpCheck()) {
        self.wallJump();
    } else {
        if (self.t_hold_jump > 0 and (self.auto_jump or controls.jump.down)) {
            if (self.velocity.z() < self.hold_jump_speed)
                self.velocity.zMut().* = self.hold_jump_speed;
        } else {
            var mult: f32 = 1;
            if ((controls.jump.down or self.auto_jump) and @abs(self.velocity.z()) < half_grav_threshold) {
                mult = 0.5;
            } else {
                mult = 1;
                self.auto_jump = false;
            }

            // apply gravity
            self.velocity.zMut().* = math.approach(self.velocity.z(), max_fall, gravity * mult * time.delta);
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
    if (self.dashes > 0 and self.t_dash_cooldown <= 0 and controls.dash.consumePress()) {
        self.dashes -= 1;
        self.state_machine.setState(.dashing);
        return true;
    }
    return false;
}

fn stDashingEnter(self: *Player) void {
    if (!relativeMoveInput().eql(Vec2.zero()))
        self.target_facing = relativeMoveInput();
    self.actor.angle = math.angleFromDir(self.target_facing);

    self.last_dash_hair_color = if (self.dashes <= 0) color_no_dash else color_normal;
    self.dashed_on_ground = self.on_ground;
    self.setDashSpeed(self.target_facing);
    self.auto_jump = true;

    self.t_dash = dash_time;
    self.t_dash_reset_cooldown = dash_reset_cooldown;
    self.t_no_dash_jump = 0.1;
    self.dash_trails_created = 0;

    // World.HitStun = .02f;

    // if (dashes <= 1)
    // 	Audio.Play(Sfx.sfx_dash_red, Position);
    // else
    // 	Audio.Play(Sfx.sfx_dash_pink, Position);

    //CancelGroundSnap();
}

fn stDashingExit(self: *Player) void {
    self.t_dash_cooldown = dash_cooldown;
    // TODO
    // self.createDashtTrail();
}

fn stDashingUpdate(self: *Player) void {
    self.skinned_model.play("Dash");

    self.t_dash -= time.delta;
    if (self.t_dash <= 0) {
        if (!self.on_ground) {
            self.velocity = self.velocity.scale(dash_end_speed_mult);
        }
        self.state_machine.setState(.normal);
        return;
    }

    if (self.dash_trails_created <= 0 or (self.dash_trails_created == 1 and self.t_dash <= dash_time * 0.5)) {
        self.dash_trails_created += 1;
        //self.create_dasht_trail();
    }

    if (!controls.move.eql(Vec2.zero()) and controls.move.dot(self.target_facing) >= -0.2) {
        const angle = math.approachAngle(math.angleFromDir(self.target_facing), math.angleFromDir(relativeMoveInput()), dash_rotate_speed * time.delta);
        self.target_facing = math.dirFromAngle(angle);
        self.setDashSpeed(self.target_facing);
    }

    if (self.t_no_dash_jump > 0)
        self.t_no_dash_jump -= time.delta;

    // dash jump
    if (self.dashed_on_ground and self.t_coyote > 0 and self.t_no_dash_jump <= 0 and controls.jump.consumePress()) {
        self.state_machine.setState(.normal);
        self.dashJump();
        return;
    }
}

fn refillDash(self: *Player, amount: u32) void {
    if (self.dashes < amount) {
        self.dashes = amount;
        self.t_dash_reset_flash = 0.05;
    }
}

fn setDashSpeed(self: *Player, dir: Vec2) void {
    var boost = Vec3.new(dir.x(), dir.y(), 0);
    if (!self.dashed_on_ground) {
        boost.zMut().* = 0.4;
        boost = boost.norm();
    }
    self.velocity = boost.scale(dash_speed);
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
        if (self.t_no_skid_jump <= 0 and controls.jump.consumePress()) {
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

fn stClimbingEnter(self: *Player) void {
    self.skinned_model.play("Climb.Idle"); // true
    self.skinned_model.rate = 1.8;
    self.velocity = Vec3.zero();
    self.climb_corner_ease = 0;
    self.climb_input_sign = 1;
    // Audio.Play(Sfx.sfx_grab, Position);
}

fn stClimbingExit(self: *Player) void {
    self.skinned_model.play("Idle");
    self.skinned_model.rate = 1;
    self.climbing_wall_actor = null;
    // sfxWallSlide?.Stop();
}

fn stClimbingUpdate(self: *Player) void {
    if (!controls.climb.down) {
        // audio.play(sfx.sfx_let_go, position);
        self.state_machine.setState(.normal);
        return;
    }

    if (controls.jump.consumePress()) {
        self.state_machine.setState(.normal);
        self.target_facing = self.target_facing.scale(-1);
        self.wallJump();
        return;
    }

    if (self.dashes > 0 and self.t_dash_cooldown <= 0 and controls.dash.consumePress()) {
        self.state_machine.setState(.dashing);
        self.dashes -= 1;
        return;
    }

    self.cancelGroundSnap();

    const forward = Vec3.new(self.target_facing.x(), self.target_facing.y(), 0);
    var wall_up = math.upwardPerpendicularNormal(self.climbing_wall_normal);
    var wall_right = Quat.fromAxis(-90, self.climbing_wall_normal).rotateVec(wall_up);
    var force_corner: bool = false;
    var wall_slide_sound_enabled = false;

    // only change the input direction based on the camera when we stop moving
    // so if we keep holding a direction, we keep moving the same way (even if it's flipped in the perspective)
    if (@abs(controls.move.x()) < 0.5) {
        const camera_target_forward_xy = Vec2.new(self.camera_target_forward.x(), self.camera_target_forward.y());
        self.climb_input_sign = if (self.target_facing.dot(camera_target_forward_xy.norm()) < -0.4) -1 else 1;
    }

    var input_translated = controls.move;
    input_translated.xMut().* *= self.climb_input_sign;
    input_translated.yMut().* *= -1; // Celeste64 uses flipped y input

    // move around
    if (self.climb_corner_ease <= 0) {
        const side = wall_right.scale(input_translated.x());
        const up = wall_up.scale(-input_translated.y());
        var move = side.add(up);

        // cancel down vector if we're on the ground
        if (move.z() < 0 and self.groundCheck() != null) {
            move.zMut().* = 0;
        }

        // TODO: don't climb over ledges into spikes
        // (you can still climb up into spikes if they're on the same wall as you)
        // if (move.z > 0 and world.overlaps<spike_block>(position + vec3.unit_z * climb_check_dist + forward * (climb_check_dist + 1)))
        // 	move.z = 0;

        // TODO: don't move left/right around into a spikes
        // (you can still climb up into spikes if they're on the same wall as you)
        // if (world.overlaps<spike_block>(self.solidWaistTestPos() + side + forward * (climb_check_dist + 1)))
        // 	move -= side;

        if (@abs(move.x()) < 0.1) move.xMut().* = 0;
        if (@abs(move.y()) < 0.1) move.yMut().* = 0;
        if (@abs(move.z()) < 0.1) move.zMut().* = 0;

        if (!move.eql(Vec3.zero()))
            self.sweepTestMove(move.scale(climb_speed * time.delta), false);

        if (@abs(input_translated.x()) < 0.25 and input_translated.y() >= 0) {
            if (input_translated.y() > 0 and !self.on_ground) {
                // TODO
                // if (time.on_interval(0.05f))
                // {
                // 	var at = position + wall_up * 5 + new vec3(facing, 0) * 2;
                // 	var vel = t_platform_velocity_storage > 0 ? platform_velocity : vec3.zero;
                // 	world.request<dust>().init(at, vel);
                // }
                wall_slide_sound_enabled = true;
            }

            self.skinned_model.play("Climb.Idle");
        } else {
            self.skinned_model.play("Climb.Up");

            // TODO
            // if (time.on_interval(0.3f))
            // 	audio.play(sfx.sfx_handhold, position);
        }
    } else { // perform corner lerp
        const ease = 1.0 - self.climb_corner_ease;

        self.velocity = Vec3.zero();
        self.actor.position = Vec3.lerp(self.climb_corner_from, self.climb_corner_to, ease);
        const angle = math.angleLerp(
            math.angleFromDir(self.climb_corner_facing_from),
            math.angleFromDir(self.climb_corner_facing_to),
            ease,
        );
        self.target_facing = math.dirFromAngle(angle);

        if (self.climb_corner_camera_from) |climb_corner_camera_from| {
            if (self.climb_corner_camera_to) |climb_corner_camera_to| {
                const cam_angle = math.angleLerp(
                    math.angleFromDir(climb_corner_camera_from),
                    math.angleFromDir(climb_corner_camera_to),
                    ease * 0.5,
                );
                const dir = math.dirFromAngle(cam_angle);
                self.camera_target_forward = Vec3.new(dir.x(), dir.y(), self.camera_target_forward.z());
            }
        }

        self.climb_corner_ease = math.approach(self.climb_corner_ease, 0, time.delta / 0.2);
        return;
    }

    // reset corner lerp data in case we use it
    self.climb_corner_from = self.actor.position;
    self.climb_corner_facing_from = self.target_facing;
    self.climb_corner_camera_from = null;
    self.climb_corner_camera_to = null;

    // move around inner corners
    var handled = false;
    if (input_translated.x() != 0) {
        if (world.solidRayCast(self.solidWaistTestPos(), wall_right.scale(input_translated.x()), climb_check_dist, .{})) |hit| {
            self.actor.position = hit.point.add(self.actor.position.sub(self.solidWaistTestPos())).add(hit.normal.scale(wall_pushout_dist));
            self.target_facing = Vec2.new(-hit.normal.x(), -hit.normal.y());
            self.climbing_wall_normal = hit.normal;
            self.climbing_wall_actor = hit.actor;
            handled = true;
        }
    }
    // snap to walls that slope away from us
    if (!handled) {
        if (world.solidRayCast(self.solidWaistTestPos(), self.climbing_wall_normal.scale(-1), climb_check_dist + 2, .{})) |hit| {
            if (climbNormalCheck(hit.normal)) {
                self.actor.position = hit.point.add(self.actor.position.sub(self.solidWaistTestPos())).add(hit.normal.scale(wall_pushout_dist));
                self.target_facing = Vec2.new(-hit.normal.x(), -hit.normal.y());
                self.climbing_wall_normal = hit.normal;
                self.climbing_wall_actor = hit.actor;
                handled = true;
            }
        }
    }
    // rotate around corners due to input
    if (!handled and input_translated.x() != 0) {
        const point = self.solidWaistTestPos().add(forward.scale(climb_check_dist + 1)).add(wall_right.scale(input_translated.x()));
        if (world.solidRayCast(point, wall_right.scale(-input_translated.x()), climb_check_dist * 2, .{})) |hit| {
            if (climbNormalCheck(hit.normal)) {
                self.actor.position = hit.point.add(self.actor.position.sub(self.solidWaistTestPos())).add(hit.normal.scale(wall_pushout_dist));
                self.target_facing = Vec2.new(-hit.normal.x(), -hit.normal.y());
                self.climbing_wall_normal = hit.normal;
                self.climbing_wall_actor = hit.actor;

                //if (vec2.dot(target_facing, camera_forward.xy().normalized()) < -.3f)
                {
                    self.climb_corner_camera_from = Vec2.new(self.camera_target_forward.x(), self.camera_target_forward.y());
                    self.climb_corner_camera_to = self.target_facing;
                }

                self.skinned_model.play("Climb.Idle");
                force_corner = true;
                handled = true;
            }
        }
    }
    // hops over tops
    if (!handled and input_translated.y() < 0 and self.climbCheckAt(Vec3.new(0, 0, 1)) == null) {
        // audio.play(sfx.sfx_climb_ledge, self.actor.position);
        self.state_machine.setState(.normal);
        const facing_xy = self.target_facing.scale(climb_hop_forward_speed);
        self.velocity = Vec3.new(facing_xy.x(), facing_xy.y(), climb_hop_up_speed);
        self.t_no_move = climb_hop_no_move_time;
        self.t_climb_cooldown = 0.3;
        self.auto_jump = false;
        self.addPlatformVelocity(false);
        return;
    }
    // fall off
    if (!handled and !self.tryClimb()) {
        self.state_machine.setState(.normal);
        return;
    }

    // TODO: update wall slide sfx
    // if (wall_slide_sound_enabled)
    // 	sfx_wall_slide?.resume();
    // else
    // 	sfx_wall_slide?.stop();

    // rotate around corners nicely
    if (force_corner or self.actor.position.sub(self.climb_corner_from).length() > 2 * 5) {
        self.climb_corner_ease = 1.0;
        self.climb_corner_to = self.actor.position;
        self.climb_corner_facing_to = self.target_facing;
        self.actor.position = self.climb_corner_from;
        self.target_facing = self.climb_corner_facing_from;
    }
}
