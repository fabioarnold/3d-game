const std = @import("std");
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;

pub const Plane = struct {
    normal: Vec3,
    d: f32,

    pub fn distance(self: Plane, v: Vec3) f32 {
        return self.normal.dot(v) + self.d;
    }
};

pub fn planeIntersectsLine(plane: Plane, line0: Vec3, line1: Vec3) ?Vec3 {
    const edge = line1.sub(line0);
    const rel = line0.sub(plane.normal.scale(plane.d));
    const t = -plane.normal.dot(rel) / plane.normal.dot(edge);
    if (t >= 0 and t <= 1) return line0.add(edge.scale(t));
    return null;
}

pub const Line = struct {
    line0: Vec3,
    line1: Vec3,
};
pub fn planeIntersectsTriangle(plane: Plane, v0: Vec3, v1: Vec3, v2: Vec3) ?Line {
    var line0 = Vec3.zero();
    var line1 = Vec3.zero();
    var index: usize = 0;
    if (planeIntersectsLine(plane, v0, v1)) |p0| {
        line0 = p0;
        index += 1;
    }
    if (planeIntersectsLine(plane, v1, v2)) |p1| {
        if (index == 0) line0 = p1 else line1 = p1;
        index += 1;
    }
    if (planeIntersectsLine(plane, v2, v0)) |p2| {
        if (index == 0) line0 = p2 else line1 = p2;
        index += 1;
    }
    if (index >= 2) {
        return .{
            .line0 = line0,
            .line1 = line1,
        };
    }
    return null;
}

pub fn closestPointOnLine2D(point: Vec2, v0: Vec2, v1: Vec2) Vec2 {
    const vector = v1.sub(v0);
    if (vector.x() == 0 and vector.y() == 0) return v0;

    const t = point.sub(v0).dot(vector) / vector.dot(vector);
    if (t < 0) return v0;
    if (t > 1) return v1;
    return v0.add(vector.scale(t));
}

pub fn rayIntersectsTriangle(
    origin: Vec3,
    direction: Vec3,
    v0: Vec3,
    v1: Vec3,
    v2: Vec3,
) ?f32 {
    // Calculate the normal of the triangle
    const edge1 = v1.sub(v0);
    const edge2 = v2.sub(v0);
    const normal = Vec3.cross(edge1, edge2);

    // Check if the ray and triangle are parallel
    const dot = normal.dot(direction);
    if (@abs(dot) < std.math.floatEps(f32)) return null;

    // Calculate the intersection point
    const ray_to_vertex = v0.sub(origin);
    const t = normal.dot(ray_to_vertex) / dot;

    // Check if the intersection point is behind the ray's origin
    if (t < 0) return null;

    // Calculate the barycentric coordinates
    const intersection_point = origin.add(direction.scale(t));
    var u: f32 = undefined;
    var v: f32 = undefined;
    var w: f32 = undefined;
    calculateBarycentricCoordinates(intersection_point, v0, v1, v2, &u, &v, &w);

    // Check if the intersection point is inside the triangle
    return if (u >= 0 and v >= 0 and w >= 0 and (u + v + w) <= 1) t else null;
}

fn calculateBarycentricCoordinates(
    point: Vec3,
    v0: Vec3,
    v1: Vec3,
    v2: Vec3,
    u: *f32,
    v: *f32,
    w: *f32,
) void {
    const edge1 = v1.sub(v0);
    const edge2 = v2.sub(v0);
    const to_point = point.sub(v0);

    const dot11 = Vec3.dot(edge1, edge1);
    const dot12 = Vec3.dot(edge1, edge2);
    const dot22 = Vec3.dot(edge2, edge2);
    const dot1p = Vec3.dot(edge1, to_point);
    const dot2p = Vec3.dot(edge2, to_point);

    const denominator = dot11 * dot22 - dot12 * dot12;

    u.* = (dot22 * dot1p - dot12 * dot2p) / denominator;
    v.* = (dot11 * dot2p - dot12 * dot1p) / denominator;
    w.* = 1 - u.* - v.*;
}

pub fn clampedMap(val: f32, min: f32, max: f32, new_min: f32, new_max: f32) f32 {
    return std.math.clamp((val - min) / (max - min), 0, 1) * (new_max - new_min) + new_min;
}

pub fn approach(from: f32, target: f32, amount: f32) f32 {
    if (target < from) {
        return @max(from - amount, target);
    } else {
        return @min(from + amount, target);
    }
}

pub fn approachVec2(from: Vec2, target: Vec2, amount: f32) Vec2 {
    const vector = target.sub(from);
    if (vector.dot(vector) <= amount * amount) return target;
    return from.add(vector.norm().scale(amount));
}

pub fn approachAngle(from: f32, to: f32, amount: f32) f32 {
    const diff = @mod(to - from + 180.0, 360.0) - 180.0;
    if (@abs(diff) < amount) return to;
    return from + std.math.clamp(diff, -amount, amount);
}

pub fn angleFromDir(dir: Vec2) f32 {
    const radians = std.math.atan2(dir.x(), -dir.y());
    return std.math.radiansToDegrees(f32, radians);
}

pub fn dirFromAngle(angle: f32) Vec2 {
    const radians = std.math.degreesToRadians(f32, angle);
    return Vec2.new(@sin(radians), -@cos(radians));
}

test "angle dir conversion" {
    for ([_]f32{ 0.0, 90.0, 180, 270.0 }) |angle| {
        const dir = dirFromAngle(angle);
        const converted = @mod(angleFromDir(dir) + 360.0, 360.0);
        try std.testing.expectApproxEqAbs(angle, converted, 0.001);
    }
}
