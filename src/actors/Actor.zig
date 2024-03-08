const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const ShaderInfo = @import("../Model.zig").ShaderInfo;
const World = @import("../World.zig");

const Actor = @This();

const CastPointShadow = struct {
    alpha: f32 = 1,
};
const Pickup = struct {
    radius: f32,
};

world: *World,
position: Vec3 = Vec3.zero(),
angle: f32 = 0,
destroying: bool = false,

derived: *anyopaque,
deinitFn: *const fn (*Actor, Allocator) void,
updateFn: *const fn (*Actor) void,
onPickupFn: *const fn (*Actor) void,
drawFn: *const fn (*Actor, ShaderInfo) void,

cast_point_shadow: ?CastPointShadow = null,
pickup: ?Pickup = null,

pub fn create(comptime Derived: type, world: *World) !*Derived {
    var derived = try world.allocator.create(Derived);
    derived.actor = .{
        .world = world,
        .derived = derived,
        .updateFn = if (@hasDecl(Derived, "update")) &@field(Derived, "update") else &noOp,
        .onPickupFn = if (@hasDecl(Derived, "onPickup")) &@field(Derived, "onPickup") else &noOp,
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

fn noOp(_: *Actor) void {}

pub fn update(self: *Actor) void {
    self.updateFn(self);
}

pub fn onPickup(self: *Actor) void {
    self.onPickupFn(self);
}

pub fn draw(self: *Actor, si: ShaderInfo) void {
    self.drawFn(self, si);
}
