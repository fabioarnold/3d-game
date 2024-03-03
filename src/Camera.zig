const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat3 = za.Mat3;
const Mat4 = za.Mat4;
const Quat = za.Quat;
const wasm = @import("web/wasm.zig");
const keys = @import("web/keys.zig");
const inspector = @import("inspector.zig");

const Camera = @This();

position: Vec3 = Vec3.zero(),
angles: Vec3 = Vec3.zero(), // yaw, pitch, roll
field_of_view: f32 = 60,
aspect_ratio: f32 = 16.0 / 9.0,
near_plane: f32 = 1,
far_plane: f32 = 10000,

pub fn projection(self: Camera) Mat4 {
    return za.perspective(self.field_of_view, self.aspect_ratio, self.near_plane, self.far_plane);
}

pub fn orientation(self: Camera) Quat {
    const x = Quat.fromAxis(self.angles.x(), Vec3.new(1, 0, 0)); // yaw
    const y = Quat.fromAxis(self.angles.y(), Vec3.new(0, -1, 0)); // pitch
    const z = Quat.fromAxis(self.angles.z(), Vec3.new(0, 0, 1)); // roll
    return y.mul(z.mul(x));
}

pub fn view(self: Camera) Mat4 {
    const z_up = Quat.fromAxis(90, Vec3.new(1, 0, 0));
    const v = z_up.mul(self.orientation()).toMat4().translate(self.position);
    return v.inv();
}

pub fn left(self: Camera) Vec3 {
    return Quat.fromAxis(self.angles.y(), Vec3.new(0, 0, -1)).rotateVec(Vec3.new(-1, 0, 0));
}

pub fn up(self: Camera) Vec3 {
    const x = Quat.fromAxis(self.angles.x(), Vec3.new(1, 0, 0));
    const y = Quat.fromAxis(self.angles.y(), Vec3.new(0, 0, -1));
    return y.mul(x).rotateVec(Vec3.new(0, 0, 1));
}

pub fn handleKeys(self: *Camera) void {
    const speed: f32 = if (wasm.isKeyDown(keys.KEY_SHIFT)) 100 else 20;
    var move = Vec3.zero();
    if (wasm.isKeyDown(keys.KEY_W)) move.data[1] += speed;
    if (wasm.isKeyDown(keys.KEY_A)) move.data[0] -= speed;
    if (wasm.isKeyDown(keys.KEY_S)) move.data[1] -= speed;
    if (wasm.isKeyDown(keys.KEY_D)) move.data[0] += speed;
    const x = Quat.fromAxis(self.angles.x(), Vec3.new(1, 0, 0));
    const y = Quat.fromAxis(self.angles.y(), Vec3.new(0, 0, -1));
    move = y.mul(x).rotateVec(move);
    if (wasm.isKeyDown(keys.KEY_Q)) move.data[2] -= speed;
    if (wasm.isKeyDown(keys.KEY_E)) move.data[2] += speed;
    self.position = self.position.add(move);
}

pub fn rotateView(self: *Camera, dx: f32, dy: f32) void {
    self.angles.data[0] = std.math.clamp(self.angles.x() + dx, -90, 90);
    self.angles.data[1] = std.math.wrap(self.angles.y() + dy, 360);
}

pub fn inspect(self: *Camera) void {
    inspector.vec3("pos", &self.position);
    inspector.floatRange("yaw", &self.angles.data[0], -90, 90);
    inspector.floatRange("pitch", &self.angles.data[1], -360, 360);
    inspector.floatRange("roll", &self.angles.data[2], -360, 360);
    inspector.floatRange("fov", &self.field_of_view, 30, 120);
    inspector.float("near", &self.near_plane);
    inspector.float("far", &self.far_plane);
}
