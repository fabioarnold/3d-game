const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const BoundingBox = @import("../spatial/BoundingBox.zig");
const Actor = @import("Actor.zig");
const World = @import("../World.zig");
const models = @import("../models.zig");
const SkinnedModel = @import("../SkinnedModel.zig");
const ShaderInfo = @import("../Model.zig").ShaderInfo;

const Granny = @This();

actor: Actor,
skinned_model: SkinnedModel,

// TODO: inherit from NPC
pub const vtable = Actor.Interface.VTable{
    .draw = draw,
};

pub fn create(world: *World) !*Granny {
    const self = try world.allocator.create(Granny);
    self.* = .{
        .actor = .{
            .world = world,
            .local_bounds = BoundingBox.initCenterSize(Vec3.new(0, 0, 4 * 5), 8 * 5),
            .cast_point_shadow = .{},
        },
        .skinned_model = .{ .model = models.findByName("granny") },
    };
    self.skinned_model.play("Idle");
    return self;
}

pub fn draw(ptr: *anyopaque, si: ShaderInfo) void {
    const self: *Granny = @alignCast(@ptrCast(ptr));
    const transform = Mat4.fromScale(Vec3.new(15, 15, 15)).mul(Mat4.fromTranslate(Vec3.new(0, 0, -0.5)));
    const model_mat = self.actor.getTransform().mul(transform);
    self.skinned_model.update();
    self.skinned_model.draw(si, model_mat);
}
