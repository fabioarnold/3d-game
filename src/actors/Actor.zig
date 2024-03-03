const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const ShaderInfo = @import("../Model.zig").ShaderInfo;

const Actor = @This();

const CastPointShadow = struct {
    alpha: f32 = 1,
};

position: Vec3 = Vec3.zero(),
angle: f32 = 0,
destroying: bool = false,

derived: *anyopaque,
deinitFn: *const fn (*Actor, Allocator) void,
updateFn: *const fn (*Actor) void,
drawFn: *const fn (*Actor, ShaderInfo) void,

cast_point_shadow: ?CastPointShadow = null,

pub fn create(comptime Derived: type, allocator: Allocator) !*Derived {
    var derived = try allocator.create(Derived);
    derived.actor = .{
        .derived = derived,
        .updateFn = if (@hasDecl(Derived, "update")) &@field(Derived, "update") else &updateNoOp,
        .drawFn = &Derived.draw,
        .deinitFn = &struct {
            fn deinit(self: *Actor, ally: Allocator) void {
                ally.destroy(@as(*Derived, @alignCast(@ptrCast(self.derived))));
            }
        }.deinit,
    };
    if (@hasDecl(Derived, "init")) {
        const initFn = &@field(Derived, "init");
        initFn(&derived.actor);
    }
    return derived;
}

pub fn deinit(self: *Actor, allocator: Allocator) void {
    self.deinitFn(self, allocator);
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
