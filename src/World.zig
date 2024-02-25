const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const math = @import("math.zig");
const wasm = @import("web/wasm.zig");
const gl = @import("web/webgl.zig");
const models = @import("models.zig");
const Model = @import("Model.zig");
const ShaderInfo = Model.ShaderInfo;
const SkinnedModel = @import("SkinnedModel.zig");
const Camera = @import("Camera.zig");
const Skybox = @import("Skybox.zig");
pub const Actor = @import("actors/Actor.zig");
pub const Solid = @import("actors/Solid.zig");
pub const Player = @import("actors/Player.zig");
const Map = @import("Map.zig");
const logger = std.log.scoped(.world);

const World = @This();

pub var world: World = .{};

pub const FloatingDecoration = struct {
    actor: Actor,
    model: Map.Model,
    rate: f32,
    offset: f32,

    pub fn draw(actor: *Actor, si: ShaderInfo) void {
        const self = @fieldParentPtr(FloatingDecoration, "actor", actor);
        const t: f32 = @floatCast(wasm.performanceNow() / 1000.0);
        const model_mat = Mat4.fromTranslate(Vec3.new(0, 0, @sin(self.rate * t + self.offset) * 60.0));
        gl.glUniformMatrix4fv(si.model_loc, 1, gl.GL_FALSE, &model_mat.data[0]);
        self.model.draw();
    }
};

pub const Strawberry = struct {
    actor: Actor,
    const model = models.findByName("strawberry");

    pub fn draw(actor: *Actor, si: ShaderInfo) void {
        const t: f32 = @floatCast(wasm.performanceNow() / 1000.0);
        const transform = actor.getTransform().mul(
            Mat4.fromScale(Vec3.new(3, 3, 3)),
        ).mul(Mat4.fromTranslate(
            Vec3.new(0, 0, 2 * @sin(t * 2)),
        ).mul(
            Mat4.fromRotation(std.math.radiansToDegrees(f32, 3 * t), Vec3.new(0, 0, 1)),
        ).mul(
            Mat4.fromScale(Vec3.new(5, 5, 5)),
        ));
        model.draw(si, transform);
    }
};

pub const Granny = struct {
    actor: Actor,
    skinned_model: SkinnedModel,

    pub fn init(actor: *Actor) void {
        const granny = @fieldParentPtr(Granny, "actor", actor);
        granny.skinned_model.model = models.findByName("granny");
        granny.skinned_model.play("Idle");
    }

    pub fn draw(actor: *Actor, si: ShaderInfo) void {
        const granny = @fieldParentPtr(Granny, "actor", actor);
        const transform = Mat4.fromScale(Vec3.new(15, 15, 15)).mul(Mat4.fromTranslate(Vec3.new(0, 0, -0.5)));
        const model_mat = actor.getTransform().mul(transform);
        granny.skinned_model.draw(si, model_mat);
    }
};

pub const StaticProp = struct {
    actor: Actor,
    model: *Model,

    pub fn draw(actor: *Actor, si: ShaderInfo) void {
        const static_prop = @fieldParentPtr(StaticProp, "actor", actor);
        static_prop.model.draw(si, actor.getTransform());
    }
};

pub const Checkpoint = struct {
    const model_off = models.findByName("flag_off");

    actor: Actor,
    model_on: SkinnedModel,
    current: bool,

    pub fn draw(actor: *Actor, si: ShaderInfo) void {
        const checkpoint = @fieldParentPtr(Checkpoint, "actor", actor);
        const model_mat = actor.getTransform();
        if (checkpoint.current) {
            checkpoint.model_on.update();
            checkpoint.model_on.draw(si, model_mat);
        } else {
            model_off.draw(si, model_mat);
        }
    }
};

pub const death_plane = -100 * 5;

camera: Camera = .{},

actors: std.ArrayList(*Actor) = undefined,
solids: std.ArrayList(*Solid) = undefined,
player: *Player = undefined,
skybox: Skybox = undefined,

var textured_unlit_shader: gl.GLuint = undefined;
var textured_unlit_mvp_loc: gl.GLint = undefined;

var textured_skinned_shader: gl.GLuint = undefined;
var textured_skinned_viewprojection_loc: gl.GLint = undefined;
var textured_skinned_model_loc: gl.GLint = undefined;
var textured_skinned_joints_loc: gl.GLint = undefined;
var textured_skinned_blend_skin_loc: gl.GLint = undefined;
var textured_skinned_color_loc: gl.GLint = undefined;

fn loadShader(vert_src: []const u8, frag_src: []const u8, attribs: []const []const u8) gl.GLuint {
    const vert_shader = gl.glInitShader(vert_src.ptr, vert_src.len, gl.GL_VERTEX_SHADER);
    const frag_shader = gl.glInitShader(frag_src.ptr, frag_src.len, gl.GL_FRAGMENT_SHADER);
    const program = gl.glCreateProgram();
    gl.glAttachShader(program, vert_shader);
    gl.glAttachShader(program, frag_shader);
    for (attribs, 0..) |attrib, i| {
        gl.glBindAttribLocation(program, i, @ptrCast(attrib));
    }
    gl.glLinkProgram(program);
    return program;
}

pub fn loadShaders() void {
    textured_unlit_shader = loadShader(
        @embedFile("shaders/transform_pt.vert"),
        @embedFile("shaders/textured_unlit.frag"),
        &.{ "a_position", "a_texcoord" },
    );
    gl.glUseProgram(textured_unlit_shader);
    textured_unlit_mvp_loc = gl.glGetUniformLocation(textured_unlit_shader, "u_mvp");
    gl.glUniform1i(gl.glGetUniformLocation(textured_unlit_shader, "u_texture"), 0);

    textured_skinned_shader = loadShader(
        @embedFile("shaders/transform_skinned.vert"),
        @embedFile("shaders/textured.frag"),
        &.{ "a_position", "a_normal", "a_texcoord", "a_joint", "a_weight" },
    );
    gl.glUseProgram(textured_skinned_shader);
    textured_skinned_viewprojection_loc = gl.glGetUniformLocation(textured_skinned_shader, "u_viewprojection");
    textured_skinned_model_loc = gl.glGetUniformLocation(textured_skinned_shader, "u_model");
    textured_skinned_joints_loc = gl.glGetUniformLocation(textured_skinned_shader, "u_joints");
    textured_skinned_blend_skin_loc = gl.glGetUniformLocation(textured_skinned_shader, "u_blend_skin");
    const textured_skinned_texture_loc = gl.glGetUniformLocation(textured_skinned_shader, "u_texture");
    textured_skinned_color_loc = gl.glGetUniformLocation(textured_skinned_shader, "u_color");
    gl.glUniform1f(textured_skinned_blend_skin_loc, 0);
    gl.glUniform1i(textured_skinned_texture_loc, 0);
    gl.glUniform4f(textured_skinned_color_loc, 1, 1, 1, 1);
}

pub fn load(self: *World, allocator: Allocator, map_name: []const u8) !void {
    self.actors = std.ArrayList(*Actor).init(allocator);
    self.solids = std.ArrayList(*Solid).init(allocator);
    // self.clear()
    try Map.load(allocator, self, map_name);
}

const RayHit = struct {
    point: Vec3,
    normal: Vec3,
    distance: f32,
    actor: ?*Actor = null,
    intersections: u32 = 0,
};
const RayCastOptions = struct {
    ignore_backfaces: bool = true,
};
pub fn solidRayCast(self: World, point: Vec3, direction: Vec3, distance: f32, options: RayCastOptions) ?RayHit {
    var hit: RayHit = undefined;
    var has_closest: ?f32 = null;

    // TODO: compute bounding box
    // const p0 = point;
    // const p1 = point.add(direction.scale(distance));

    // TODO: solid grid query
    // var solids = std.ArrayList(*Solid).init(allocator);
    // defer solids.deinit();
    for (self.solids.items) |solid| {
        // TODO: flags

        // TODO: bounds intersect

        const verts = solid.vertices.items;

        for (solid.faces.items) |face| {
            if (options.ignore_backfaces and face.plane.normal.dot(direction) >= 0) continue;
            if (face.plane.distance(point) > distance) continue;

            for (0..face.vertex_count - 2) |i| {
                if (math.rayIntersectsTriangle(
                    point,
                    direction,
                    verts[face.vertex_start + 0],
                    verts[face.vertex_start + i + 1],
                    verts[face.vertex_start + i + 2],
                )) |dist| {
                    if (dist > distance) continue;

                    hit.intersections += 1;

                    if (has_closest) |closest| {
                        if (dist > closest) continue;
                    }

                    has_closest = dist;
                    hit.point = point.add(direction.scale(dist));
                    hit.normal = face.plane.normal;
                    hit.distance = dist;
                    hit.actor = &solid.actor;
                    break;
                }
            }
        }
    }

    if (has_closest) |_| return hit;
    return null;
}

pub const WallHit = struct {
    pushout: Vec3,
    point: Vec3,
    normal: Vec3,
    actor: ?*Actor,
};
pub fn solidWallCheck(
    self: World,
    point: Vec3,
    radius: f32,
    hits: *std.ArrayListUnmanaged(WallHit),
) void {
    const flat_plane = math.Plane{ .normal = Vec3.new(0, 0, 1), .d = point.z() };
    const flat_point = Vec2.new(point.x(), point.y());

    for (self.solids.items) |solid| {
        // TODO: flags

        // TODO: bounds intersect

        const verts = solid.vertices.items;

        for (solid.faces.items) |face| {
            // ignore flat planes
            if (face.plane.normal.z() <= -1 or face.plane.normal.z() >= 1)
                continue;

            // igore planes that are definitely too far away
            const distance = face.plane.distance(point);
            if (distance < 0 or distance > radius)
                continue;

            var has_closest: ?WallHit = null;

            for (0..face.vertex_count - 2) |i| {
                if (math.planeIntersectsTriangle(
                    flat_plane,
                    verts[face.vertex_start + 0],
                    verts[face.vertex_start + i + 1],
                    verts[face.vertex_start + i + 2],
                )) |result| {
                    const line0 = Vec2.new(result.line0.x(), result.line0.y());
                    const line1 = Vec2.new(result.line1.x(), result.line1.y());
                    const next = math.closestPointOnLine2D(flat_point, line0, line1);
                    const diff = flat_point.sub(next);
                    if (diff.dot(diff) > radius * radius)
                        continue;

                    const pushout = diff.norm().scale(radius - diff.length());
                    if (has_closest) |closest| {
                        if (pushout.dot(pushout) < closest.pushout.dot(closest.pushout))
                            continue;
                    }

                    has_closest = WallHit{
                        .pushout = Vec3.new(pushout.x(), pushout.y(), 0),
                        .point = Vec3.new(next.x(), next.y(), point.z()),
                        .normal = face.plane.normal,
                        .actor = &solid.actor,
                    };
                }
            }

            if (has_closest) |closest| {
                hits.appendAssumeCapacity(closest);
                if (hits.items.len == hits.capacity) return;
            }
        }
    }
}

pub fn solidWallCheckNearest(self: World, point: Vec3, radius: f32) ?WallHit {
    var buffer: [8]WallHit = undefined;
    var hits = std.ArrayListUnmanaged(WallHit).initBuffer(&buffer);
    self.solidWallCheck(point, radius, &hits);
    if (hits.items.len > 0) {
        var closest = &hits.items[0];
        for (hits.items[1..]) |*hit| {
            if (hit.pushout.dot(hit.pushout) > closest.pushout.dot(closest.pushout)) {
                closest = hit;
            }
        }
        return closest.*;
    }
    return null;
}

pub fn solidWallCheckClosestToNormal(self: World, point: Vec3, radius: f32, normal: Vec3) ?WallHit {
    var buffer: [8]WallHit = undefined;
    var hits = std.ArrayListUnmanaged(WallHit).initBuffer(&buffer);
    self.solidWallCheck(point, radius, &hits);
    if (hits.items.len > 0) {
        var closest = &hits.items[0];
        for (hits.items[1..]) |*hit| {
            if (hit.normal.dot(normal) > closest.normal.dot(normal)) {
                closest = hit;
            }
        }
        return closest.*;
    }
    return null;
}

pub fn update(self: *World) void {
    for (self.actors.items) |actor| {
        actor.update();
    }
}

pub fn draw(self: World, camera: Camera) void {
    const view_projection = camera.projection().mul(camera.view());

    {
        gl.glUseProgram(textured_unlit_shader);
        gl.glDisable(gl.GL_DEPTH_TEST);
        gl.glDepthMask(gl.GL_FALSE);
        gl.glCullFace(gl.GL_FRONT);
        const mvp = view_projection.mul(Mat4.fromTranslate(camera.position));
        self.skybox.draw(textured_unlit_mvp_loc, mvp, 300);
        gl.glCullFace(gl.GL_BACK);
        gl.glDepthMask(gl.GL_TRUE);
        gl.glEnable(gl.GL_DEPTH_TEST);
    }

    gl.glUseProgram(textured_skinned_shader);
    gl.glUniformMatrix4fv(textured_skinned_viewprojection_loc, 1, gl.GL_FALSE, &view_projection.data[0]);
    const si = ShaderInfo{
        .model_loc = textured_skinned_model_loc,
        .joints_loc = textured_skinned_joints_loc,
        .blend_skin_loc = textured_skinned_blend_skin_loc,
        .color_loc = textured_skinned_color_loc,
    };
    for (self.actors.items) |actor| {
        actor.draw(si);
    }
}
