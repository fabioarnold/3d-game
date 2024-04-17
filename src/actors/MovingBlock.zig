const std = @import("std");
const za = @import("zalgebra");
const gl = @import("../web/webgl.zig");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const Plane = @import("../math.zig").Plane;
const ShaderInfo = @import("../Model.zig").ShaderInfo;
const time = @import("../time.zig");
const math = @import("../math.zig");
const easings = @import("../easings.zig");
const Map = @import("../Map.zig");
const World = @import("../World.zig");
const Solid = @import("Solid.zig");
const Actor = @import("Actor.zig");

pub const MovingBlock = @This();

solid: Solid,
start: Vec3,
end: Vec3,
lerp: f32 = 0,
target: f32 = 1,
go_slow: bool,

pub const vtable = Actor.Interface.VTable{
    // .deinit = Solid.deinit, // frees wrong size
    .added = added,
    .update = update,
    .draw = Solid.draw,
};

pub fn create(world: *World, go_slow: bool, end: Vec3) !*MovingBlock {
    const self = try world.allocator.create(MovingBlock);
    self.* = .{
        .solid = .{
            .actor = .{
                .world = world,
                .local_bounds = undefined, // calculated by Map
            },
            .model = undefined,
            .vertices = undefined,
            .faces = undefined,
        },
        .start = undefined,
        .go_slow = go_slow,
        .end = end,
    };
    return self;
}

pub fn added(ptr: *anyopaque) void {
    const self: *MovingBlock = @alignCast(@ptrCast(ptr));
    self.start = self.solid.actor.position;
    // base.added();
}

pub fn update(ptr: *anyopaque) void {
    const self: *MovingBlock = @alignCast(@ptrCast(ptr));
    // base.update();

    self.lerp = math.approach(self.lerp, self.target, time.delta / @as(f32, if (self.go_slow) 2 else 1));
    if (self.lerp == self.target) {
        self.target = 1 - self.target;
    }

    self.solid.moveTo(Vec3.lerp(self.start, self.end, easings.inOutSine(self.lerp)));
}
