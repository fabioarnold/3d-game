const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const BoundingBox = @import("../spatial/BoundingBox.zig");
const ShaderInfo = @import("../Model.zig").ShaderInfo;
const World = @import("../World.zig");

const Actor = @This();

const CastPointShadow = struct {
    alpha: f32 = 1,
};
const Pickup = struct {
    radius: f32,
};

pub const Interface = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (*anyopaque, Allocator) void = deinitNoop,
        added: *const fn (*anyopaque) void = noop,
        update: *const fn (*anyopaque) void = noop,
        lateUpdate: *const fn (*anyopaque) void = noop,
        pickup: *const fn (*anyopaque) void = noop,
        draw: *const fn (*anyopaque, ShaderInfo) void = drawNoop,
    };

    pub fn make(comptime Class: type, instance: *Class) Interface {
        return .{
            .ptr = instance,
            .vtable = &Class.vtable,
        };
    }

    // Actor has to be the first member of the derived class for this to work
    pub fn actor(self: Interface) *Actor {
        return @alignCast(@ptrCast(self.ptr));
    }

    pub fn deinit(interface: *Interface, allocator: Allocator) void {
        interface.vtable.deinit(interface.ptr, allocator);
    }

    pub fn added(interface: *const Interface) void {
        interface.vtable.added(interface.ptr);
    }

    pub fn update(interface: *const Interface) void {
        interface.vtable.update(interface.ptr);
    }

    pub fn lateUpdate(interface: *const Interface) void {
        interface.vtable.lateUpdate(interface.ptr);
    }

    pub fn pickup(interface: *const Interface) void {
        interface.vtable.pickup(interface.ptr);
    }

    pub fn draw(interface: *const Interface, shader_info: ShaderInfo) void {
        interface.vtable.draw(interface.ptr, shader_info);
    }
};

world: *World,
position: Vec3 = Vec3.zero(),
angle: f32 = 0,
local_bounds: BoundingBox,
destroying: bool = false,

cast_point_shadow: ?CastPointShadow = null,
pickup: ?Pickup = null,

pub fn getTransform(self: Actor) Mat4 {
    const r = Mat4.fromRotation(self.angle, Vec3.new(0, 0, 1));
    const t = Mat4.fromTranslate(self.position);
    return t.mul(r);
}

pub fn deinitNoop(_: *anyopaque, _: Allocator) void {}
pub fn noop(_: *anyopaque) void {}
pub fn drawNoop(_: *anyopaque, _: ShaderInfo) void {}
