const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const math = @import("math.zig");
const time = @import("time.zig");
const wasm = @import("web/wasm.zig");
const gl = @import("web/webgl.zig");
const shaders = @import("shaders.zig");
const Sprite = @import("Sprite.zig");
const SpriteRenderer = @import("SpriteRenderer.zig");
const models = @import("models.zig");
const Model = @import("Model.zig");
const ShaderInfo = Model.ShaderInfo;
const SkinnedModel = @import("SkinnedModel.zig");
const Target = @import("Target.zig");
const Camera = @import("Camera.zig");
const Skybox = @import("Skybox.zig");
const Actor = @import("actors/Actor.zig");
const Snow = @import("actors/Snow.zig");
const Solid = @import("actors/Solid.zig");
const Checkpoint = @import("actors/Checkpoint.zig");
const Player = @import("actors/Player.zig");
const Strawberry = @import("actors/Strawberry.zig");
const maps = @import("maps.zig");
const Map = @import("Map.zig");
const logger = std.log.scoped(.world);

const World = @This();

const EntryReason = enum { entered, returned, respawned };
const EntryInfo = struct {
    map: []const u8,
    checkpoint: []const u8,
    submap: bool,
    reason: EntryReason,
};

pub const death_plane = -100 * 5;

allocator: std.mem.Allocator,

camera: Camera = .{},
rng: std.rand.Random,
entry: EntryInfo,
general_timer: f32 = 0,

actors: std.ArrayList(Actor.Interface),
adding: std.ArrayList(Actor.Interface),
destroying: std.ArrayList(Actor.Interface),
solids: std.ArrayList(*Solid),
sprites: std.ArrayList(Sprite),
player: *Player,
strawberry: *Strawberry,
skybox: Skybox,

var prng: std.rand.DefaultPrng = std.rand.DefaultPrng.init(0);

pub fn create(allocator: Allocator, entry: EntryInfo) !*World {
    var world = try allocator.create(World);
    world.* = .{
        .allocator = allocator,
        .rng = prng.random(),
        .entry = undefined,
        .actors = std.ArrayList(Actor.Interface).init(allocator),
        .adding = std.ArrayList(Actor.Interface).init(allocator),
        .destroying = std.ArrayList(Actor.Interface).init(allocator),
        .solids = std.ArrayList(*Solid).init(allocator),
        .sprites = std.ArrayList(Sprite).init(allocator),
        .player = undefined,
        .strawberry = undefined,
        .skybox = undefined,
    };
    try world.load(entry);
    return world;
}

fn load(self: *World, entry: EntryInfo) !void {
    self.entry = entry;

    const map = maps.findByName(entry.map);

    self.camera.near_plane = 20 * 5;
    self.camera.far_plane = 800 * 5;

    // TODO: pause menu

    // environment
    {
        if (map.snow_amount > 0) {
            const snow = try Snow.create(self, map.snow_amount, map.snow_wind);
            self.add(Actor.Interface.make(Snow, snow));
        }

        if (map.skybox.len > 0) {
            // single skybox
            const suffix = if (std.mem.eql(u8, map.skybox, "bsides")) "_0" else "";
            const skybox_name = try std.mem.concat(self.allocator, u8, &.{ "skybox_", map.skybox, suffix });
            defer self.allocator.free(skybox_name);
            self.skybox = Skybox.load(skybox_name);
            // TODO: group
        }

        // Music = $"event:/music/{map.Music}";
        // Ambience = $"event:/sfx/ambience/{map.Ambience}";
    }

    try map.load(self.allocator, self);
}

pub fn deinit(self: *World) void {
    for (self.actors.items) |*actor| {
        actor.deinit(self.allocator);
    }
    self.actors.deinit();
    self.adding.deinit();
    self.destroying.deinit();
    self.solids.deinit();
    self.sprites.deinit();
}

pub fn add(self: *World, actor: Actor.Interface) void {
    self.adding.append(actor) catch unreachable;
}

pub fn destroy(self: *World, interface: Actor.Interface) void {
    interface.actor().destroying = true;
    self.destroying.append(interface) catch unreachable;
}

fn resolveChanges(self: *World) void {
    for (self.adding.items) |actor| {
        self.actors.append(actor) catch unreachable;
    }
    // notify they're being added
    for (self.adding.items) |*actor| {
        actor.added();
    }
    self.adding.clearRetainingCapacity();

    for (self.destroying.items) |*actor| {
        for (self.actors.items, 0..) |a, i| {
            if (a.ptr == actor.ptr) {
                _ = self.actors.swapRemove(i);
                break;
            }
        }
        actor.deinit(self.allocator);
    }
    self.destroying.clearRetainingCapacity();
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
pub fn solidRayCast(self: World, point_: Vec3, direction: Vec3, distance: f32, options: RayCastOptions) ?RayHit {
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

        // TODO: transform verts and faces to world (remove .sub(solid.actor.position))
        const point = point_.sub(solid.actor.position);

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
                    hit.point = hit.point.add(solid.actor.position); // TODO: remove
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
    point_: Vec3,
    radius: f32,
    hits: *std.ArrayListUnmanaged(WallHit),
) void {
    // const flat_plane = math.Plane{ .normal = Vec3.new(0, 0, 1), .d = point.z() };
    // const flat_point = Vec2.new(point.x(), point.y());

    for (self.solids.items) |solid| {
        // TODO: flags

        // TODO: bounds intersect

        // TODO: transform verts and faces to world (remove .sub(solid.actor.position))
        const point = point_.sub(solid.actor.position);
        const flat_plane = math.Plane{ .normal = Vec3.new(0, 0, 1), .d = point.z() };
        const flat_point = Vec2.new(point.x(), point.y());

        const verts = solid.vertices.items;

        for (solid.faces.items) |face| {
            // ignore flat planes
            if (face.plane.normal.z() <= -1 or face.plane.normal.z() >= 1)
                continue;

            // ignore planes that are definitely too far away
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
                        .point = next.toVec3(point.z()).add(solid.actor.position), // TODO: remove
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
    self.general_timer += time.delta;

    self.resolveChanges();
    for (self.actors.items) |*actor| {
        actor.update();
    }
    for (self.actors.items) |*actor| {
        actor.lateUpdate();
    }
}

pub fn drawSprite(self: *World, sprite: Sprite) void {
    self.sprites.append(sprite) catch unreachable;
}

pub fn drawSprites(self: *World) void {
    SpriteRenderer.draw(self.sprites.items, false) catch unreachable;
    SpriteRenderer.draw(self.sprites.items, true) catch unreachable;
    self.sprites.clearRetainingCapacity();
}

pub fn draw(self: *World, target: Target) void {
    self.camera.aspect_ratio = target.width / target.height;
    const view_projection = self.camera.projection().mul(self.camera.view());

    // skybox
    {
        gl.glUseProgram(shaders.textured_unlit.shader);
        gl.glDisable(gl.GL_DEPTH_TEST);
        gl.glDepthMask(gl.GL_FALSE);
        gl.glCullFace(gl.GL_FRONT);
        const mvp = view_projection
            .mul(Mat4.fromTranslate(self.camera.position))
            .mul(Mat4.fromScale(Vec3.new(1, 1, 0.5)));
        self.skybox.draw(shaders.textured_unlit.mvp_loc, mvp, 300);
        gl.glCullFace(gl.GL_BACK);
        gl.glDepthMask(gl.GL_TRUE);
        gl.glEnable(gl.GL_DEPTH_TEST);
    }

    // actors
    gl.glUseProgram(shaders.textured_skinned.shader);
    gl.glUniformMatrix4fv(shaders.textured_skinned.viewprojection_loc, 1, gl.GL_FALSE, &view_projection.data[0]);
    const si = ShaderInfo{
        .model_loc = shaders.textured_skinned.model_loc,
        .joints_loc = shaders.textured_skinned.joints_loc,
        .blend_skin_loc = shaders.textured_skinned.blend_skin_loc,
        .color_loc = shaders.textured_skinned.color_loc,
        .effects_loc = shaders.textured_skinned.effects_loc,
    };
    for (self.actors.items) |*interface| {
        interface.draw(si);

        const actor = interface.actor();
        if (actor.cast_point_shadow) |point_shadow| {
            if (Sprite.createShadowSprite(self, actor.position.add(Vec3.new(0, 0, 1 * 5)), point_shadow.alpha)) |shadow_sprite| {
                self.drawSprite(shadow_sprite);
            }
        }
    }

    // render 2d sprites
    gl.glUseProgram(shaders.sprite.shader);
    gl.glUniformMatrix4fv(shaders.sprite.viewprojection_loc, 1, gl.GL_FALSE, &view_projection.data[0]);
    self.drawSprites();
}
