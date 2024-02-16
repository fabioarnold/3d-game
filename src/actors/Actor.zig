const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const ShaderInfo = @import("../Model.zig").ShaderInfo;

const Actor = @This();

position: Vec3 = Vec3.zero(),
angle: f32 = 0,
updateFn: *const fn (*Actor) void,
drawFn: *const fn (*Actor, ShaderInfo) void,

pub fn create(comptime T: type, allocator: Allocator) !*T {
    var t = try allocator.create(T);
    t.actor = .{
        .updateFn = if (@hasDecl(T, "update")) &@field(T, "update") else &updateNoOp,
        .drawFn = &T.draw,
    };
    if (@hasDecl(T, "init")) {
        const initFn = &@field(T, "init");
        initFn(&t.actor);
    }
    return t;
}

pub fn getTransform(self: Actor) Mat4 {
    const r = Mat4.fromRotation(self.angle, Vec3.new(0, 0, 1));
    const t = Mat4.fromTranslate(self.position);
    return t.mul(r);
}

fn updateNoOp(_: *Actor) void {}

pub fn update(self: *Actor) void {
    self.updateFn(self);
}

pub fn draw(self: *Actor, si: ShaderInfo) void {
    self.drawFn(self, si);
}
