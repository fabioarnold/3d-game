const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const BoundingBox = @import("../spatial/BoundingBox.zig");
const math = @import("../math.zig");
const time = @import("../time.zig");
const textures = @import("../textures.zig");
const models = @import("../models.zig");
const Sprite = @import("../Sprite.zig");
const Model = @import("../Model.zig");
const SkinnedModel = @import("../SkinnedModel.zig");
const World = @import("../World.zig");
const Actor = @import("Actor.zig");

const Checkpoint = @This();

const model_off = models.findByName("flag_off");

actor: Actor,
name: []const u8,
model_on: SkinnedModel,
t_wiggle: f32 = 0,

pub const vtable = Actor.Interface.VTable{
    .added = added,
    .update = update,
    .pickup = pickup,
    .draw = draw,
};

pub fn create(world: *World, name: []const u8) !*Checkpoint {
    const self = try world.allocator.create(Checkpoint);
    self.* = .{
        .actor = .{
            .world = world,
            .local_bounds = BoundingBox.initCenterSize(Vec3.zero(), 8 * 5),
            .pickup = .{ .radius = 16 * 5 },
        },
        .name = name,
        .model_on = .{ .model = models.findByName("flag_on") },
    };
    self.model_on.play("Idle");
    return self;
}

pub fn isCurrent(self: Checkpoint) bool {
    return std.mem.eql(u8, self.actor.world.entry.checkpoint, self.name);
}

pub fn added(ptr: *anyopaque) void {
    const self: *Checkpoint = @alignCast(@ptrCast(ptr));
    // if we're the spawn checkpoint, shift us so the player isn't on top
    if (self.isCurrent()) {
        self.actor.position.yMut().* -= 8 * 5;
    }
}

pub fn update(ptr: *anyopaque) void {
    const self: *Checkpoint = @alignCast(@ptrCast(ptr));
    if (self.isCurrent()) {
        self.t_wiggle = math.approach(self.t_wiggle, 0, time.delta / 0.7);
        self.model_on.update();
    }
}

pub fn pickup(ptr: *anyopaque) void {
    const self: *Checkpoint = @alignCast(@ptrCast(ptr));
    if (!self.isCurrent()) {
        // audio.play(.sfx_checkpoint, actor.position);

        self.actor.world.entry.checkpoint = self.name;
        if (self.actor.world.entry.submap) {
            // TODO
            // save.current.checkpoint = name;
        }

        self.t_wiggle = 1;
    }
}

pub fn draw(ptr: *anyopaque, si: Model.ShaderInfo) void {
    const self: *Checkpoint = @alignCast(@ptrCast(ptr));
    const actor = &self.actor;
    const model_mat = actor.getTransform();
    if (self.isCurrent()) {
        self.model_on.draw(si, model_mat);
    } else {
        model_off.draw(si, model_mat);
    }

    const halo_pos = actor.position.add(Vec3.new(0, 0, 16 * 5));
    const halo_color = if (self.isCurrent()) [_]f32{ 0.498, 0.871, 0.275, 0.4 } else [_]f32{ 0.875, 0.353, 0.706, 0.4 };
    const gradient_tex = textures.findByName("gradient");
    var gradient_color = halo_color;
    gradient_color[3] *= 0.4;
    actor.world.drawSprite(Sprite.createBillboard(actor.world, halo_pos, gradient_tex, 12 * 5, gradient_color, false));

    if (self.t_wiggle > 0) {
        const ring_tex = textures.findByName("ring");
        actor.world.drawSprite(Sprite.createBillboard(actor.world, halo_pos, ring_tex, self.t_wiggle * self.t_wiggle * 40 * 5, halo_color, true));
        actor.world.drawSprite(Sprite.createBillboard(actor.world, halo_pos, ring_tex, self.t_wiggle * 50 * 5, halo_color, true));
    }
}
