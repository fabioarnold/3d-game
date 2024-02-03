const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const Mat3 = za.Mat3;
const QuakeMap = @import("QuakeMap.zig");
const textures = @import("textures.zig");
const logger = std.log.scoped(.map);

const Map = @This();

const BoundingBox = struct {
    min: Vec3,
    max: Vec3,
};

pub const Material = struct {
    texture_name: []const u8,
    texture: textures.Texture,
    index_start: u32,
    index_count: u32,
};

name: []const u8,
skybox: []const u8,
static_solids: std.ArrayList(BoundingBox),

materials: std.ArrayList(Material),
vertices: std.ArrayList(f32),
indices: std.ArrayList(u32),

pub fn load(allocator: Allocator, name: []const u8, data: []const u8) !Map {
    var self: Map = .{
        .name = name,
        .skybox = undefined,
        .static_solids = std.ArrayList(BoundingBox).init(allocator),
        .materials = std.ArrayList(Material).init(allocator),
        .vertices = std.ArrayList(f32).init(allocator),
        .indices = std.ArrayList(u32).init(allocator),
    };

    var error_info: QuakeMap.ErrorInfo = undefined;
    const quake_map = QuakeMap.read(allocator, data, &error_info) catch |err| {
        logger.err("\"{s}.map\" {} in line {}", .{ name, err, error_info.line_number });
        return error.QuakeMapRead;
    };

    self.skybox = try quake_map.worldspawn.getStringProperty("skybox");

    try self.generateModel(allocator, quake_map.worldspawn.solids.items);

    return self;
}

fn generateModel(self: *Map, allocator: Allocator, solids: []QuakeMap.Solid) !void {
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
        material.index_start = self.indices.items.len;
        defer material.index_count = self.indices.items.len - material.index_start;

        const texture_size = Vec2.new(@floatFromInt(material.texture.width), @floatFromInt(material.texture.height));

        for (solids) |solid| {
            for (solid.faces.items) |face| {
                if (face.vertices.items.len < 3) continue; // TODO: investigate

                if (!std.mem.eql(u8, material.texture_name, face.texture_name)) continue;

                const vertex_index = self.vertices.items.len / 8;
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
                    try self.vertices.append(pos.x());
                    try self.vertices.append(pos.y());
                    try self.vertices.append(pos.z());
                    try self.vertices.append(uv.x());
                    try self.vertices.append(uv.y());
                    try self.vertices.append(n.x());
                    try self.vertices.append(n.y());
                    try self.vertices.append(n.z());
                }

                // add indices
                for (0..face.vertices.items.len - 2) |i| {
                    try self.indices.append(vertex_index + 0);
                    try self.indices.append(vertex_index + i + 1);
                    try self.indices.append(vertex_index + i + 2);
                }
            }
        }
    }

    logger.info("generateModel: {} vertices {} indices", .{self.vertices.items.len / 8, self.indices.items.len});
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
