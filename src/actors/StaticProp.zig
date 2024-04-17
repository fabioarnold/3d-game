const za = @import("zalgebra");
const Vec3 = za.Vec3;
const BoundingBox = @import("../spatial/BoundingBox.zig");
const Actor = @import("Actor.zig");
const World = @import("../World.zig");
const models = @import("../models.zig");
const Model = @import("../Model.zig");
const ShaderInfo = Model.ShaderInfo;

const StaticProp = @This();

actor: Actor,
model: *Model,

pub const vtable = Actor.Interface.VTable{
    .draw = draw,
};

pub fn create(world: *World, model_name: []const u8) !*StaticProp {
    const self = try world.allocator.create(StaticProp);
    self.* = .{
        .actor = .{
            .world = world,
            .local_bounds = .{
                .min = Vec3.new(-10, -10, 0).scale(5),
                .max = Vec3.new(10, 10, 80).scale(5),
            },
        },
        .model = models.findByName(model_name),
    };
    return self;
}

pub fn draw(ptr: *anyopaque, si: ShaderInfo) void {
    const self: *StaticProp = @alignCast(@ptrCast(ptr));
    self.model.draw(si, self.actor.getTransform());
}
