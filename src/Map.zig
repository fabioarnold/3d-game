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
const Skybox = @import("Skybox.zig");
const textures = @import("textures.zig");
const logger = std.log.scoped(.map);

const Map = @This();

const BoundingBox = struct {
    min: Vec3,
    max: Vec3,
};

pub fn load(allocator: Allocator, world: *World, name: []const u8) !void {
    // maps.findByName(name) // TODO
    const map = assets.maps.@"1";

    var error_info: QuakeMap.ErrorInfo = undefined;
    const quake_map = QuakeMap.read(allocator, map, &error_info) catch |err| {
        logger.err("\"{s}.map\" {} in line {}", .{ name, err, error_info.line_number });
        return error.QuakeMapRead;
    };

    const skybox_name = try quake_map.worldspawn.getStringProperty("skybox");
    world.skybox = Skybox.load(try std.mem.concat(allocator, u8, &.{ "skybox_", skybox_name }));

    const solid = try World.Solid.create(allocator);
    solid.model = try Model.fromSolids(allocator, quake_map.worldspawn.solids.items);
    try world.actors.append(&solid.actor);

    var decoration_solids = std.ArrayList(QuakeMap.Solid).init(allocator);
    for (quake_map.entities.items) |entity| {
        if (std.mem.eql(u8, entity.classname, "Decoration")) {
            try decoration_solids.appendSlice(entity.solids.items);
        } else if (std.mem.eql(u8, entity.classname, "FloatingDecoration")) {
            // TODO: move those up and down
            try decoration_solids.appendSlice(entity.solids.items);
        } else if (std.mem.eql(u8, entity.classname, "Strawberry")) {
            const strawberry = try World.Strawberry.create(allocator);
            strawberry.actor.position = try entity.getVec3Property("origin");
            try world.actors.append(&strawberry.actor);
        } else if (std.mem.eql(u8, entity.classname, "StaticProp")) {
            const static_prop = try World.StaticProp.create(allocator);
            static_prop.actor.position = try entity.getVec3Property("origin");
            const model_path = try entity.getStringProperty("model");
            const i = std.mem.lastIndexOfScalar(u8, model_path, '/').? + 1;
            const j = std.mem.lastIndexOfScalar(u8, model_path, '.').?;
            const model_name = model_path[i..j];
            logger.info("searching model {s}", .{model_name});
            static_prop.model = models.findByName(model_name);
            try world.actors.append(&static_prop.actor);
        }
    }
    const decoration_solid = try World.Solid.create(allocator);
    decoration_solid.model = try Model.fromSolids(allocator, decoration_solids.items);
    try world.actors.append(&decoration_solid.actor);
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
    materials: std.ArrayList(Material),
    vertex_buffer: gl.GLuint,
    index_buffer: gl.GLuint,

    fn fromSolids(allocator: Allocator, solids: []const QuakeMap.Solid) !Model {
        var self = Model{
            .materials = std.ArrayList(Material).init(allocator),
            .vertex_buffer = undefined,
            .index_buffer = undefined,
        };
        var vertices = std.ArrayList(f32).init(allocator);
        var indices = std.ArrayList(u32).init(allocator);

        {
            var used = std.StringHashMap(void).init(allocator);
            // find all used materials
            for (solids) |solid| {
                for (solid.faces.items) |face| {
                    if (!used.contains(face.texture_name)) {
                        try used.put(face.texture_name, {});
                        var material: Material = undefined;
                        material.texture_name = face.texture_name;
                        material.texture = textures.findByName(face.texture_name);
                        try self.materials.append(material);
                    }
                }
            }

            for (self.materials.items) |*material| {
                material.index_start = indices.items.len;
                defer material.index_count = indices.items.len - material.index_start;

                const texture_size = Vec2.new(@floatFromInt(material.texture.width), @floatFromInt(material.texture.height));

                for (solids) |solid| {
                    for (solid.faces.items) |face| {
                        if (!std.mem.eql(u8, material.texture_name, face.texture_name)) continue;

                        const vertex_index = vertices.items.len / 8;
                        var u_axis: Vec3 = undefined;
                        var v_axis: Vec3 = undefined;
                        calculateRotatedUV(face, &u_axis, &v_axis);

                        // add face vertices
                        const n = face.plane.normal.cast(f32);
                        for (face.vertices.items) |vertex| {
                            const pos = vertex.cast(f32);
                            const uv = Vec2.new(
                                (u_axis.dot(pos) + face.shift_x) / texture_size.x(),
                                (v_axis.dot(pos) + face.shift_y) / texture_size.y(),
                            );
                            try vertices.append(pos.x());
                            try vertices.append(pos.y());
                            try vertices.append(pos.z());
                            try vertices.append(uv.x());
                            try vertices.append(uv.y());
                            try vertices.append(n.x());
                            try vertices.append(n.y());
                            try vertices.append(n.z());
                        }

                        // add indices
                        for (0..face.vertices.items.len - 2) |i| {
                            try indices.append(vertex_index + 0);
                            try indices.append(vertex_index + i + 1);
                            try indices.append(vertex_index + i + 2);
                        }
                    }
                }
            }

            logger.info("generateModel: {} vertices {} indices", .{ vertices.items.len / 8, indices.items.len });
        }

        gl.glGenBuffers(1, &self.vertex_buffer);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vertex_buffer);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(vertices.items.len * @sizeOf(f32)), @ptrCast(vertices.items.ptr), gl.GL_STATIC_DRAW);
        gl.glGenBuffers(1, &self.index_buffer);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.index_buffer);
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices.items.len * @sizeOf(u32)), @ptrCast(indices.items.ptr), gl.GL_STATIC_DRAW);

        return self;
    }

    pub fn draw(self: Model) void {
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vertex_buffer);
        gl.glEnableVertexAttribArray(0);
        gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(gl.GLfloat), null);
        gl.glEnableVertexAttribArray(1);
        gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(gl.GLfloat), @ptrFromInt(3 * @sizeOf(gl.GLfloat)));
        gl.glEnableVertexAttribArray(2);
        gl.glVertexAttribPointer(2, 3, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(gl.GLfloat), @ptrFromInt(5 * @sizeOf(gl.GLfloat)));

        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.index_buffer);
        for (self.materials.items) |material| {
            gl.glBindTexture(gl.GL_TEXTURE_2D, material.texture.id);
            gl.glDrawElements(gl.GL_TRIANGLES, @intCast(material.index_count), gl.GL_UNSIGNED_INT, material.index_start * @sizeOf(u32));
        }
    }
};
