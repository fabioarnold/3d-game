const za = @import("zalgebra");
const Vec3 = za.Vec3;

const BoundingBox = @This();

min: Vec3,
max: Vec3,

pub fn zero() BoundingBox {
    return .{ .min = Vec3.zero(), .max = Vec3.zero() };
}

pub fn initCenterSize(origin: Vec3, size: f32) BoundingBox {
    return .{
        .min = origin.sub(Vec3.one().scale(size / 2.0)),
        .max = origin.add(Vec3.one().scale(size / 2.0)),
    };
}

pub fn center(self: BoundingBox) Vec3 {
    return self.min.add(self.max).scale(0.5);
}

pub fn conflate(self: *BoundingBox, other: BoundingBox) void {
    self.min = self.min.min(other.min);
    self.max = self.max.max(other.max);
}
