const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Mat3 = za.Mat3;
const Mat4 = za.Mat4;
const gl = @import("web/webgl.zig");
const assets = @import("assets");
const models = @import("models.zig");
const QuakeMap = @import("QuakeMap.zig");
const World = @import("World.zig");
const Actor = @import("actors/Actor.zig");
const Solid = @import("actors/Solid.zig");
const Player = @import("actors/Player.zig");
const Checkpoint = @import("actors/Checkpoint.zig");
const textures = @import("textures.zig");
const logger = std.log.scoped(.map);

const Map = @This();

const BoundingBox = struct {
    min: Vec3,
    max: Vec3,
};

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
    const solid = try Actor.create(Solid, world);
    try generateSolid(allocator, solid, self.quake_map.worldspawn.solids.items);
    try world.solids.append(solid);
    world.add(&solid.actor);

    var decoration_solids = std.ArrayList(QuakeMap.Solid).init(allocator);
    for (self.quake_map.entities.items) |entity| {
        if (std.mem.eql(u8, entity.classname, "Decoration")) {
            try decoration_solids.appendSlice(entity.solids.items);
        } else if (std.mem.eql(u8, entity.classname, "FloatingDecoration")) {
            const floating_decoration = try Actor.create(World.FloatingDecoration, world);
            floating_decoration.model = try Model.fromSolids(allocator, entity.solids.items);
            floating_decoration.rate = 0.25 * (1.0 + 2.0 * world.rng.float(f32));
            floating_decoration.offset = world.rng.float(f32) * std.math.tau;
            world.add(&floating_decoration.actor);
        } else {
            try loadActor(world, entity);
        }
    }
    const decoration_solid = try Actor.create(Solid, world);
    decoration_solid.model = try Model.fromSolids(allocator, decoration_solids.items);
    world.add(&decoration_solid.actor);
}

const start_checkpoint = "Start";

fn loadActor(world: *World, entity: QuakeMap.Entity) !void {
    if (std.mem.eql(u8, entity.classname, "PlayerSpawn")) {
        const name = entity.getStringProperty("name") catch start_checkpoint;

        const spawns_player = std.mem.eql(u8, world.entry.checkpoint, name) or
            (std.mem.eql(u8, world.entry.checkpoint, "") and std.mem.eql(u8, name, start_checkpoint));
        // TODO: check if world.entry.checkpoint doesn't exist

        if (spawns_player) {
            var player = try Actor.create(Player, world);
            try handleActorCreation(world, entity, &player.actor);
            world.player = player;
        }

        if (!std.mem.eql(u8, name, start_checkpoint)) {
            var checkpoint = try Checkpoint.create(world, name);
            try handleActorCreation(world, entity, &checkpoint.actor);
        }
    } else if (try createActor(world, entity)) |actor| {
        try handleActorCreation(world, entity, actor);
    }
}

fn handleActorCreation(world: *World, entity: QuakeMap.Entity, actor: *Actor) !void {
    if (entity.hasProperty("origin")) actor.position = try entity.getVec3Property("origin");
    if (entity.hasProperty("angle")) actor.angle = try entity.getFloatProperty("angle");
    world.add(actor);
}

fn createActor(world: *World, entity: QuakeMap.Entity) !?*Actor {
    if (std.mem.eql(u8, entity.classname, "Strawberry")) {
        const strawberry = try Actor.create(World.Strawberry, world);
        return &strawberry.actor;
    } else if (std.mem.eql(u8, entity.classname, "Granny")) {
        var granny = try Actor.create(World.Granny, world);
        return &granny.actor;
    } else if (std.mem.eql(u8, entity.classname, "StaticProp")) {
        const static_prop = try Actor.create(World.StaticProp, world);
        const model_path = try entity.getStringProperty("model");
        static_prop.model = models.findByName(modelNameFromPath(model_path));
        return &static_prop.actor;
    } else {
        return null;
    }
}

fn generateSolid(allocator: Allocator, into: *Solid, solids: []const QuakeMap.Solid) !void {
    into.model = try Model.fromSolids(allocator, solids);
    into.vertices = std.ArrayList(Vec3).init(allocator);
    into.faces = std.ArrayList(Solid.Face).init(allocator);

    for (solids) |solid| {
        for (solid.faces.items) |face| {
            if (std.mem.eql(u8, face.texture_name, "__TB_empty")) continue;
            const vertex_index = into.vertices.items.len;
            // TODO: skip too small faces
            for (face.vertices) |vertex| {
                try into.vertices.append(vertex.cast(f32));
            }
            try into.faces.append(.{
                .plane = .{
                    .normal = face.plane.normal.cast(f32),
                    .d = @floatCast(face.plane.d),
                },
                .vertex_start = vertex_index,
                .vertex_count = into.vertices.items.len - vertex_index,
            });
        }
    }
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

    fn fromSolids(allocator: Allocator, solids: []const QuakeMap.Solid) !Model {
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
                        const pos = vertex.cast(f32);
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
