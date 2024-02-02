const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const QuakeMap = @import("QuakeMap.zig");
const logger = std.log.scoped(.map);

const Map = @This();

const BoundingBox = struct {
    min: Vec3,
    max: Vec3,
};

name: []const u8,
skybox: []const u8,
static_solids: std.ArrayList(BoundingBox),

vertices: std.ArrayList(f32),
indices: std.ArrayList(u16),

pub fn load(allocator: Allocator, name: []const u8, data: []const u8) !Map {
    var self: Map = .{
        .name = name,
        .skybox = undefined,
        .static_solids = std.ArrayList(BoundingBox).init(allocator),
        .vertices = std.ArrayList(f32).init(allocator),
        .indices = std.ArrayList(u16).init(allocator),
    };

    var error_info: QuakeMap.ErrorInfo = undefined;
    const quake_map = QuakeMap.read(allocator, data, &error_info) catch |err| {
        logger.err("\"{s}.map\" {} in line {}", .{ name, err, error_info.line_number });
        return error.QuakeMapRead;
    };

    self.skybox = try quake_map.worldspawn.getStringProperty("skybox");

    try self.generateModel(quake_map.worldspawn.solids.items);

    return self;
}

fn generateModel(self: *Map, solids: []QuakeMap.Solid) !void {
    for (solids) |solid| {
        for (solid.faces.items) |face| {
            if (face.vertices.items.len < 3) continue; // TODO: investigate

            const vertex_index: u16 = @intCast(self.vertices.items.len / 6);

            // add face vertices
            const n = face.plane.normal.cast(f32);
            for (face.vertices.items) |vertex| {
                const v = vertex.cast(f32);
                try self.vertices.append(v.x());
                try self.vertices.append(v.y());
                try self.vertices.append(v.z());
                try self.vertices.append(n.x());
                try self.vertices.append(n.y());
                try self.vertices.append(n.z());
            }

            // add indices
            for (0..face.vertices.items.len - 2) |i| {
                try self.indices.append(vertex_index + 0);
                try self.indices.append(vertex_index + @as(u16, @intCast(i)) + 1);
                try self.indices.append(vertex_index + @as(u16, @intCast(i)) + 2);
            }
        }
    }
}
