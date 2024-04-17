const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Mat3 = za.Mat3;
const Mat4 = za.Mat4;
const gl = @import("web/webgl.zig");
const math = @import("math.zig");
const BoundingBox = @import("spatial/BoundingBox.zig");
const assets = @import("assets");
const models = @import("models.zig");
const QuakeMap = @import("QuakeMap.zig");
const World = @import("World.zig");
const Actor = @import("actors/Actor.zig");
const Cassette = @import("actors/Cassette.zig");
const Checkpoint = @import("actors/Checkpoint.zig");
const Granny = @import("actors/Granny.zig");
const FloatingDecoration = @import("actors/FloatingDecoration.zig");
const Player = @import("actors/Player.zig");
const Solid = @import("actors/Solid.zig");
const StaticProp = @import("actors/StaticProp.zig");
const Strawberry = @import("actors/Strawberry.zig");
const Refill = @import("actors/Refill.zig");
const Coin = @import("actors/Coin.zig");
const MovingBlock = @import("actors/MovingBlock.zig");
const textures = @import("textures.zig");
const logger = std.log.scoped(.map);

const Map = @This();

quake_map: QuakeMap,
skybox: []const u8,
snow_amount: f32,
snow_wind: Vec3,
music: []const u8,
ambience: []const u8,

pub fn init(allocator: std.mem.Allocator, name: []const u8, data: []const u8) !Map {
    var error_info: QuakeMap.ErrorInfo = undefined;
    const quake_map = QuakeMap.read(allocator, data, &error_info) catch |err| {
        logger.err("\"{s}.map\" {} in line {}", .{ name, err, error_info.line_number });
        return error.QuakeMapReadFailed;
    };

    const skybox = quake_map.worldspawn.getStringProperty("skybox") catch "city";
    const snow_amount = quake_map.worldspawn.getFloatProperty("snowAmount") catch 1;
    const snow_wind = quake_map.worldspawn.getVec3Property("snowDirection") catch Vec3.new(0, 0, -1);
    const music = quake_map.worldspawn.getStringProperty("music") catch "";
    const ambience = quake_map.worldspawn.getStringProperty("ambience") catch "";

    return .{
        .quake_map = quake_map,
        .skybox = skybox,
        .snow_amount = snow_amount,
        .snow_wind = snow_wind,
        .music = music,
        .ambience = ambience,
    };
}

pub fn load(self: *const Map, allocator: Allocator, world: *World) !void {
    const solid = try Solid.create(world);
    try generateSolid(allocator, solid, self.quake_map.worldspawn.solids.items);
    try world.solids.append(solid);
    world.add(Actor.Interface.make(Solid, solid));

    var decoration_solids = std.ArrayList(QuakeMap.Solid).init(allocator);
    for (self.quake_map.entities.items) |entity| {
        if (std.mem.eql(u8, entity.classname, "Decoration")) {
            try decoration_solids.appendSlice(entity.solids.items);
        } else if (std.mem.eql(u8, entity.classname, "FloatingDecoration")) {
            const floating_decoration = try FloatingDecoration.create(world);
            floating_decoration.actor.local_bounds = calculateSolidsBounds(entity.solids.items);
            floating_decoration.model = try Model.fromSolids(allocator, entity.solids.items, Vec3.zero());
            world.add(Actor.Interface.make(FloatingDecoration, floating_decoration));
        } else {
            try loadActor(&self.quake_map, world, entity);
        }
    }
    const decoration_solid = try Solid.create(world);
    decoration_solid.model = try Model.fromSolids(allocator, decoration_solids.items, Vec3.zero());
    world.add(Actor.Interface.make(Solid, decoration_solid));
}

const start_checkpoint = "Start";

fn loadActor(map: *const QuakeMap, world: *World, entity: QuakeMap.Entity) !void {
    if (std.mem.eql(u8, entity.classname, "PlayerSpawn")) {
        const name = entity.getStringProperty("name") catch start_checkpoint;

        const spawns_player = std.mem.eql(u8, world.entry.checkpoint, name) or
            (std.mem.eql(u8, world.entry.checkpoint, "") and std.mem.eql(u8, name, start_checkpoint));
        // TODO: check if world.entry.checkpoint doesn't exist

        if (spawns_player) {
            const player = try Player.create(world);
            try handleActorCreation(world, entity, Actor.Interface.make(Player, player));
            world.player = player;
        }

        if (!std.mem.eql(u8, name, start_checkpoint)) {
            const checkpoint = try Checkpoint.create(world, name);
            try handleActorCreation(world, entity, Actor.Interface.make(Checkpoint, checkpoint));
        }
    } else if (try createActor(map, world, entity)) |interface| {
        try handleActorCreation(world, entity, interface);
    }
}

fn handleActorCreation(world: *World, entity: QuakeMap.Entity, interface: Actor.Interface) !void {
    const actor = interface.actor();
    if (entity.hasProperty("origin")) actor.position = try entity.getVec3Property("origin");
    if (entity.hasProperty("angle")) actor.angle = try entity.getFloatProperty("angle");
    world.add(interface);
}

fn findTargetEntity(map: *const QuakeMap, target_name: []const u8) ?QuakeMap.Entity {
    if (target_name.len == 0) return null;

    for (map.entities.items) |entity| {
        const target_name_property = entity.getStringProperty("targetname") catch "";
        if (std.mem.eql(u8, target_name_property, target_name)) return entity;
    }

    logger.err("target {s} not found", .{target_name});

    return null;
}

fn createActor(map: *const QuakeMap, world: *World, entity: QuakeMap.Entity) !?Actor.Interface {
    if (std.mem.eql(u8, entity.classname, "Strawberry")) {
        const strawberry = try Strawberry.create(world);
        world.strawberry = strawberry;
        return Actor.Interface.make(Strawberry, strawberry);
    } else if (std.mem.eql(u8, entity.classname, "Refill")) {
        const refill = try Refill.create(world, entity.getIntProperty("double") catch 0 > 0);
        return Actor.Interface.make(Refill, refill);
    } else if (std.mem.eql(u8, entity.classname, "Cassette")) {
        const cassette = try Cassette.create(world, entity.getStringProperty("map") catch "");
        return Actor.Interface.make(Cassette, cassette);
    } else if (std.mem.eql(u8, entity.classname, "Coin")) {
        const coin = try Coin.create(world);
        return Actor.Interface.make(Coin, coin);
    } else if (std.mem.eql(u8, entity.classname, "MovingBlock")) {
        const target_name = entity.getStringProperty("target") catch "worldspawn";
        var target_pos = Vec3.zero();
        if (findTargetEntity(map, target_name)) |target| {
            target_pos = target.getVec3Property("origin") catch Vec3.zero();
        }
        const moving_block = try MovingBlock.create(world, entity.getIntProperty("slow") catch 0 > 0, target_pos);
        try generateSolid(world.allocator, &moving_block.solid, entity.solids.items);
        try world.solids.append(&moving_block.solid);
        return Actor.Interface.make(MovingBlock, moving_block);
    } else if (std.mem.eql(u8, entity.classname, "Granny")) {
        const granny = try Granny.create(world);
        return Actor.Interface.make(Granny, granny);
    } else if (std.mem.eql(u8, entity.classname, "StaticProp")) {
        const model_path = try entity.getStringProperty("model");
        const static_prop = try StaticProp.create(world, modelNameFromPath(model_path));
        return Actor.Interface.make(StaticProp, static_prop);
    } else {
        return null;
    }
}

fn calculateSolidBounds(solid: *const QuakeMap.Solid) BoundingBox {
    const v = solid.faces.items[0].vertices[0].cast(f32);
    var bounds: BoundingBox = .{ .min = v, .max = v };
    for (solid.faces.items) |face| {
        for (face.vertices) |vertex| {
            bounds.min = bounds.min.min(vertex.cast(f32));
            bounds.max = bounds.max.max(vertex.cast(f32));
        }
    }
    return bounds;
}

fn calculateSolidsBounds(solids: []const QuakeMap.Solid) BoundingBox {
    var bounds = calculateSolidBounds(&solids[0]);
    for (solids[1..]) |*solid| {
        bounds.conflate(calculateSolidBounds(solid));
    }
    return bounds;
}

fn generateSolid(allocator: Allocator, into: *Solid, solids: []const QuakeMap.Solid) !void {
    const bounds = calculateSolidsBounds(solids);
    const center = bounds.center();
    into.actor.position = center;

    into.model = try Model.fromSolids(allocator, solids, center.scale(-1));
    into.vertices = std.ArrayList(Vec3).init(allocator);
    into.faces = std.ArrayList(Solid.Face).init(allocator);

    for (solids) |solid| {
        for (solid.faces.items) |face| {
            if (std.mem.eql(u8, face.texture_name, "__TB_empty")) continue;
            const vertex_index = into.vertices.items.len;
            // TODO: skip too small faces
            for (face.vertices) |vertex| {
                try into.vertices.append(vertex.cast(f32).sub(center));
            }
            var plane: math.Plane = .{
                .normal = face.plane.normal.cast(f32),
                .d = @floatCast(face.plane.d),
            };
            plane.d += plane.normal.dot(center); // transform plane
            try into.faces.append(.{
                .plane = plane,
                .vertex_start = vertex_index,
                .vertex_count = into.vertices.items.len - vertex_index,
            });
        }
    }

    into.actor.local_bounds = .{
        .min = bounds.min.sub(center),
        .max = bounds.max.sub(center),
    };
}

fn modelNameFromPath(model_path: []const u8) []const u8 {
    const i = std.mem.lastIndexOfScalar(u8, model_path, '/').? + 1;
    const j = std.mem.lastIndexOfScalar(u8, model_path, '.').?;
    return model_path[i..j];
}

fn calculateRotatedUV(face: QuakeMap.Face, u_axis: *Vec3, v_axis: *Vec3) void {
    const scaled_u_axis = face.u_axis.scale(1.0 / face.scale_x);
    const scaled_v_axis = face.v_axis.scale(1.0 / face.scale_y);

    const axis = closestAxis(face.plane.normal.cast(f32));
    const rotation = Mat3.fromRotation(face.rotation, axis);
    u_axis.* = rotation.mulByVec3(scaled_u_axis);
    v_axis.* = rotation.mulByVec3(scaled_v_axis);
}

fn closestAxis(v: Vec3) Vec3 {
    if (@abs(v.x()) >= @abs(v.y()) and @abs(v.x()) >= @abs(v.z())) return Vec3.right(); // 1 0 0
    if (@abs(v.y()) >= @abs(v.z())) return Vec3.up(); // 0 1 0
    return Vec3.forward(); // 0 0 1
}

pub const Material = struct {
    texture_name: []const u8,
    texture: textures.Texture,
    index_start: u32,
    index_count: u32,
};

pub const Model = struct {
    const Vertex = packed struct { x: f32, y: f32, z: f32, nx: f32, ny: f32, nz: f32, u: f32, v: f32 };

    materials: std.ArrayList(Material),
    vertex_buffer: gl.GLuint,
    index_buffer: gl.GLuint,

    fn fromSolids(allocator: Allocator, solids: []const QuakeMap.Solid, offset: Vec3) !Model {
        var self = Model{
            .materials = std.ArrayList(Material).init(allocator),
            .vertex_buffer = undefined,
            .index_buffer = undefined,
        };
        var vertices = std.ArrayList(Vertex).init(allocator);
        defer vertices.deinit();
        var indices = std.ArrayList(u32).init(allocator);
        defer indices.deinit();
        var vertex_count: usize = 0;
        var index_count: usize = 0;

        {
            var used = std.StringHashMap(void).init(allocator);
            defer used.deinit();
            // find all used materials and count vertices
            for (solids) |solid| {
                for (solid.faces.items) |face| {
                    if (std.mem.eql(u8, face.texture_name, "__TB_empty")) continue;
                    if (!used.contains(face.texture_name)) {
                        try used.put(face.texture_name, {});
                        var material: Material = undefined;
                        material.texture_name = face.texture_name;
                        material.texture = textures.findByName(face.texture_name);
                        try self.materials.append(material);
                    }
                    vertex_count += face.vertices.len;
                    index_count += 3 * (face.vertices.len - 2);
                }
            }
        }

        try vertices.ensureTotalCapacityPrecise(vertex_count);
        try indices.ensureTotalCapacityPrecise(index_count);

        for (self.materials.items) |*material| {
            material.index_start = indices.items.len;
            defer material.index_count = indices.items.len - material.index_start;

            const texture_size = Vec2.new(@floatFromInt(material.texture.width), @floatFromInt(material.texture.height));

            for (solids) |solid| {
                for (solid.faces.items) |face| {
                    if (!std.mem.eql(u8, material.texture_name, face.texture_name)) continue;

                    const vertex_index = vertices.items.len;
                    var u_axis: Vec3 = undefined;
                    var v_axis: Vec3 = undefined;
                    calculateRotatedUV(face, &u_axis, &v_axis);

                    // add face vertices
                    const n = face.plane.normal.cast(f32);
                    for (face.vertices) |vertex| {
                        const pos = vertex.cast(f32).add(offset);
                        const uv = Vec2.new(
                            (u_axis.dot(pos) + face.shift_x) / texture_size.x(),
                            (v_axis.dot(pos) + face.shift_y) / texture_size.y(),
                        );
                        vertices.appendAssumeCapacity(.{
                            .x = pos.x(),
                            .y = pos.y(),
                            .z = pos.z(),
                            .nx = n.x(),
                            .ny = n.y(),
                            .nz = n.z(),
                            .u = uv.x(),
                            .v = uv.y(),
                        });
                    }

                    // add indices
                    for (0..face.vertices.len - 2) |i| {
                        indices.appendAssumeCapacity(vertex_index + 0);
                        indices.appendAssumeCapacity(vertex_index + i + 1);
                        indices.appendAssumeCapacity(vertex_index + i + 2);
                    }
                }
            }
        }

        std.debug.assert(vertices.items.len == vertex_count);
        std.debug.assert(indices.items.len == index_count);
        // logger.info("generateModel: {} vertices {} indices", .{ vertices.items.len, indices.items.len });

        gl.glGenBuffers(1, &self.vertex_buffer);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vertex_buffer);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(vertices.items.len * @sizeOf(Vertex)), @ptrCast(vertices.items.ptr), gl.GL_STATIC_DRAW);
        gl.glGenBuffers(1, &self.index_buffer);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.index_buffer);
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices.items.len * @sizeOf(u32)), @ptrCast(indices.items.ptr), gl.GL_STATIC_DRAW);

        return self;
    }

    pub fn draw(self: Model) void {
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vertex_buffer);
        gl.glEnableVertexAttribArray(0);
        gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), null);
        gl.glEnableVertexAttribArray(1);
        gl.glVertexAttribPointer(1, 3, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(3 * @sizeOf(gl.GLfloat)));
        gl.glEnableVertexAttribArray(2);
        gl.glVertexAttribPointer(2, 2, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(6 * @sizeOf(gl.GLfloat)));

        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.index_buffer);
        for (self.materials.items) |material| {
            gl.glBindTexture(gl.GL_TEXTURE_2D, material.texture.id);
            gl.glDrawElements(gl.GL_TRIANGLES, @intCast(material.index_count), gl.GL_UNSIGNED_INT, material.index_start * @sizeOf(u32));
        }
    }
};
