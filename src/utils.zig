const za = @import("zalgebra");
const Vec3 = za.Vec3;

pub fn rayIntersectsTriangle(origin: Vec3, direction: Vec3, v0: Vec3, v1: Vec3, v2: Vec3) ?f32 {
    // Calculate the normal of the triangle
    const edge1 = v1.sub(v0);
    const edge2 = v2.sub(v0);
    const normal = Vec3.cross(edge1, edge2);

    // Check if the ray and triangle are parallel
    const dot = normal.dot(direction);
    if (@abs(dot) < f32.epsilon) return null;

    // Calculate the intersection point
    const ray_to_vertex = v0.sub(origin);
    const t = normal.dot(ray_to_vertex) / dot;

    // Check if the intersection point is behind the ray's origin
    if (t < 0) return null;

    // Calculate the barycentric coordinates
    const intersection_point = origin + t * direction;
    var u: f32 = undefined;
    var v: f32 = undefined;
    var w: f32 = undefined;
    calculateBarycentricCoordinates(intersection_point, v0, v1, v2, &u, &v, &w);

    // Check if the intersection point is inside the triangle
    return u >= 0 and v >= 0 and w >= 0 and (u + v + w) <= 1;
}

fn calculateBarycentricCoordinates(point: Vec3, v0: Vec3, v1: Vec3, v2: Vec3, u: *f32, v: *f32, w: *f32) void {
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
