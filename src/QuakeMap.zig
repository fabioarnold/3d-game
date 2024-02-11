const std = @import("std");
const Allocator = std.mem.Allocator;
const TokenIterator = std.mem.TokenIterator;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Vec3d = za.Vec3_f64;
const logger = std.log.scoped(.quakemap);

const QuakeMap = @This();

worldspawn: Entity,
entities: std.ArrayList(Entity),

pub const ErrorInfo = struct {
    line_number: usize,
};

pub fn read(allocator: Allocator, data: []const u8, error_info: *ErrorInfo) !QuakeMap {
    var worldspawn: ?Entity = null;
    var entities = std.ArrayList(Entity).init(allocator);
    var iter = std.mem.tokenize(u8, data, "\r\n");
    error_info.line_number = 0;
    while (iter.next()) |line| {
        error_info.line_number += 1;
        switch (line[0]) {
            '/' => continue,
            '{' => {
                const entity = try readEntity(allocator, &iter, error_info);
                if (std.mem.eql(u8, entity.classname, "worldspawn")) {
                    worldspawn = entity;
                } else {
                    try entities.append(entity);
                }
            },
            else => return error.UnexpectedToken,
        }
    }
    return .{
        .worldspawn = worldspawn orelse return error.WorldSpawnNotFound,
        .entities = entities,
    };
}

const Property = struct {
    key: []const u8,
    value: []const u8,
};

pub const Entity = struct {
    classname: []const u8,
    spawnflags: u32,
    properties: std.ArrayList(Property),
    solids: std.ArrayList(Solid),

    fn init(allocator: Allocator) Entity {
        return .{
            .classname = &.{},
            .spawnflags = 0,
            .properties = std.ArrayList(Property).init(allocator),
            .solids = std.ArrayList(Solid).init(allocator),
        };
    }

    fn indexOfProperty(self: Entity, key: []const u8) ?usize {
        for (self.properties.items, 0..) |property, i| {
            if (std.mem.eql(u8, property.key, key)) {
                return i;
            }
        }
        return null;
    }

    pub fn hasProperty(self: Entity, key: []const u8) bool {
        return self.indexOfProperty(key) != null;
    }

    pub fn getStringProperty(self: Entity, key: []const u8) ![]const u8 {
        const i = self.indexOfProperty(key) orelse return error.NotFound;
        return self.properties.items[i].value;
    }

    pub fn getFloatProperty(self: Entity, key: []const u8) !f32 {
        const string = try self.getStringProperty(key);
        return try parseFloat(string);
    }

    pub fn getVec3Property(self: Entity, key: []const u8) !Vec3 {
        const string = try self.getStringProperty(key);
        var it = std.mem.tokenizeScalar(u8, string, ' ');
        var vec3: Vec3 = undefined;
        for (0..3) |i| {
            vec3.data[i] = try parseFloat(it.next() orelse return error.ExpectedFloat);
        }
        return vec3;
    }
};

pub const Solid = struct {
    faces: std.ArrayList(Face),

    fn init(allocator: Allocator) Solid {
        return .{ .faces = std.ArrayList(Face).init(allocator) };
    }

    fn computeVertices(self: *Solid) !void {
        const allocator = self.faces.allocator;
        var buffer: [64]Vec3d = undefined;
        var vertices = std.ArrayListUnmanaged(Vec3d).initBuffer(buffer[0..32]);
        var clipped = std.ArrayListUnmanaged(Vec3d).initBuffer(buffer[32..64]);
        for (self.faces.items, 0..) |*face, i| {
            const quad = face.plane.makeQuadWithRadius(1000000.0);
            vertices.clearRetainingCapacity();
            vertices.appendSliceAssumeCapacity(&quad);
            // clip with other planes
            for (self.faces.items, 0..) |clip_face, j| {
                if (j == i) continue;
                clipped.clearRetainingCapacity();
                try clip(vertices, clip_face.plane, &clipped);
                if (clipped.items.len < 3) return error.DegenerateFace;
                std.mem.swap(std.ArrayListUnmanaged(Vec3d), &vertices, &clipped);
            }
            face.vertices = try allocator.dupe(Vec3d, vertices.items);
        }
    }

    fn clip(vertices: std.ArrayListUnmanaged(Vec3d), clip_plane: Plane, clipped: *std.ArrayListUnmanaged(Vec3d)) !void {
        const epsilon = 0.0001;

        var buffer: [32]f64 = undefined;
        var distances = std.ArrayListUnmanaged(f64).initBuffer(&buffer);
        var cb: usize = 0;
        var cf: usize = 0;
        for (vertices.items) |vertex| {
            var distance = clip_plane.normal.dot(vertex) + clip_plane.d;
            if (distance < -epsilon) {
                cb += 1;
            } else if (distance > epsilon) {
                cf += 1;
            } else {
                distance = 0;
            }
            distances.appendAssumeCapacity(distance);
        }

        if (cb == 0 and cf == 0) {
            // co-planar
            return;
        } else if (cb == 0) {
            // all vertices in front
            return;
        } else if (cf == 0) {
            // all vertices in back;
            // keep
            clipped.appendSliceAssumeCapacity(vertices.items);
            return;
        }

        for (vertices.items, 0..) |s, i| {
            const j = (i + 1) % vertices.items.len;

            const e = vertices.items[j];
            const sd = distances.items[i];
            const ed = distances.items[j];
            if (sd <= 0) clipped.appendAssumeCapacity(s); // back

            if ((sd < 0 and ed > 0) or (ed < 0 and sd > 0)) {
                const t = sd / (sd - ed);
                var intersect = Vec3d.lerp(s, e, t);
                // use plane's distance from origin, if plane's normal is a unit vector
                if (clip_plane.normal.x() == 1) intersect.data[0] = -clip_plane.d;
                if (clip_plane.normal.x() == -1) intersect.data[0] = clip_plane.d;
                if (clip_plane.normal.y() == 1) intersect.data[1] = -clip_plane.d;
                if (clip_plane.normal.y() == -1) intersect.data[1] = clip_plane.d;
                if (clip_plane.normal.z() == 1) intersect.data[2] = -clip_plane.d;
                if (clip_plane.normal.z() == -1) intersect.data[2] = clip_plane.d;
                clipped.appendAssumeCapacity(intersect);
            }
        }
    }
};

fn closestAxis(v: Vec3d) Vec3d {
    if (@abs(v.x()) >= @abs(v.y()) and @abs(v.x()) >= @abs(v.z())) return Vec3d.right(); // 1 0 0
    if (@abs(v.y()) >= @abs(v.z())) return Vec3d.up(); // 0 1 0
    return Vec3d.forward(); // 0 0 1
}

pub const Face = struct {
    plane: Plane,
    texture_name: []const u8,
    u_axis: Vec3,
    v_axis: Vec3,
    shift_x: f32,
    shift_y: f32,
    rotation: f32,
    scale_x: f32,
    scale_y: f32,

    vertices: []Vec3d,
};

const Plane = struct {
    normal: Vec3d,
    d: f64,

    fn initFromVertices(v0: Vec3d, v1: Vec3d, v2: Vec3d) Plane {
        const v0v1 = v1.sub(v0);
        const v0v2 = v2.sub(v0);
        const normal = Vec3d.cross(v0v1, v0v2).norm();
        const length = normal.dot(v0);
        return .{ .normal = normal, .d = -length };
    }

    fn makeQuadWithRadius(self: Plane, radius: f32) [4]Vec3d {
        const direction = closestAxis(self.normal);
        var up = if (direction.z() == 1) Vec3d.right() else Vec3d.new(0, 0, -1);
        const upv = up.dot(self.normal);
        up = up.sub(self.normal.scale(upv)).norm();
        var right = up.cross(self.normal);

        up = up.scale(radius);
        right = right.scale(radius);

        const origin = self.normal.scale(-self.d);
        return .{
            origin.sub(right).sub(up),
            origin.add(right).sub(up),
            origin.add(right).add(up),
            origin.sub(right).add(up),
        };
    }
};

fn readEntity(allocator: Allocator, iter: *TokenIterator(u8, .any), error_info: *ErrorInfo) !Entity {
    var entity = Entity.init(allocator);
    while (iter.next()) |line| {
        error_info.line_number += 1;
        switch (line[0]) {
            '/' => continue,
            '"' => {
                const property = try readProperty(line);
                if (std.mem.eql(u8, property.key, "classname")) {
                    entity.classname = property.value;
                } else if (std.mem.eql(u8, property.key, "spawnflags")) {
                    entity.spawnflags = try std.fmt.parseInt(u32, property.value, 10);
                } else {
                    try entity.properties.append(property);
                }
            },
            '{' => try entity.solids.append(try readSolid(allocator, iter, error_info)),
            '}' => break,
            else => return error.UnexpectedToken,
        }
    }
    return entity;
}

fn readProperty(line: []const u8) !Property {
    var property: Property = undefined;
    var iter = std.mem.tokenizeScalar(u8, line, '"');
    property.key = try readSymbol(&iter);
    if (!std.mem.eql(u8, iter.next() orelse return error.UnexpectedEof, " ")) return error.ExpectedSpace;
    property.value = try readSymbol(&iter);
    return property;
}

fn readSolid(allocator: Allocator, iter: *TokenIterator(u8, .any), error_info: *ErrorInfo) !Solid {
    var solid = Solid.init(allocator);
    while (iter.next()) |line| {
        error_info.line_number += 1;
        switch (line[0]) {
            '/' => continue,
            '(' => try solid.faces.append(try readFace(line)),
            '}' => break,
            else => return error.UnexpectedToken,
        }
    }
    try solid.computeVertices();
    return solid;
}

fn readFace(line: []const u8) !Face {
    var face: Face = undefined;
    var iter = std.mem.tokenizeScalar(u8, line, ' ');
    const v0 = try readPoint(&iter);
    const v1 = try readPoint(&iter);
    const v2 = try readPoint(&iter);
    // map planes are clockwise, flip them around when computing the plane to get a counter-clockwise plane
    face.plane = Plane.initFromVertices(v2, v1, v0);
    const direction = closestAxis(face.plane.normal);
    face.u_axis = if (direction.x() == 1) Vec3.new(0, 1, 0) else Vec3.new(1, 0, 0);
    face.v_axis = if (direction.z() == 1) Vec3.new(0, -1, 0) else Vec3.new(0, 0, -1);
    face.texture_name = try readSymbol(&iter);
    face.shift_x = try readDecimal(&iter);
    face.shift_y = try readDecimal(&iter);
    face.rotation = try readDecimal(&iter);
    face.scale_x = try readDecimal(&iter);
    face.scale_y = try readDecimal(&iter);
    return face;
}

fn readPoint(iter: *TokenIterator(u8, .scalar)) !Vec3d {
    var point: Vec3d = undefined;
    if (!std.mem.eql(u8, iter.next() orelse return error.UnexpectedEof, "(")) return error.ExpectedOpenParanthesis;
    point.data[0] = try readDecimal(iter);
    point.data[1] = try readDecimal(iter);
    point.data[2] = try readDecimal(iter);
    if (!std.mem.eql(u8, iter.next() orelse return error.UnexpectedEof, ")")) return error.ExpectedCloseParanthesis;
    return point;
}

fn readDecimal(iter: *TokenIterator(u8, .scalar)) !f32 {
    const string = iter.next() orelse return error.UnexpectedEof;
    return try parseFloat(string);
}

fn readSymbol(iter: *TokenIterator(u8, .scalar)) ![]const u8 {
    return iter.next() orelse return &.{};
}

// simpler float parsing function that runs quicker in debug
fn parseFloat(string: []const u8) !f32 {
    var signed: bool = false;
    var decimal_point: usize = string.len - 1;
    var decimal: f64 = 0;
    for (string, 0..) |c, i| {
        switch (c) {
            '-' => signed = true,
            '0'...'9' => {
                const digit: f64 = @floatFromInt(c - '0');
                decimal = 10 * decimal + digit;
            },
            '.' => decimal_point = i,
            else => return error.UnexpectedCharacter,
        }
    }
    if (signed) decimal *= -1;
    if (decimal_point < string.len - 1) {
        const denom = std.math.pow(f64, 10, @floatFromInt(string.len - 1 - decimal_point));
        decimal /= denom;
    }
    return @floatCast(decimal);
}
