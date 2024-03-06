const std = @import("std");
const math = @import("../math.zig");
const time = @import("../time.zig");
const models = @import("../models.zig");
const Model = @import("../Model.zig");
const SkinnedModel = @import("../SkinnedModel.zig");
const World = @import("../World.zig");
const Actor = @import("Actor.zig");

const world = &World.world;

const Checkpoint = @This();

const model_off = models.findByName("flag_off");

actor: Actor,
name: []const u8,
model_on: SkinnedModel,
t_wiggle: f32 = 0,

pub fn isCurrent(self: Checkpoint) bool {
    return std.mem.eql(u8, world.entry.checkpoint, self.name);
}

pub fn init(actor: *Actor) void {
    const self = @fieldParentPtr(Checkpoint, "actor", actor);
    self.* = .{
        .actor = actor.*,
        .name = undefined, // set by create
        .model_on = .{
            .model = models.findByName("flag_on"),
        },
    };
    self.model_on.play("Idle");
    self.actor.pickup = .{.radius = 16 * 5};
}

pub fn create(allocator: std.mem.Allocator, name: []const u8) !*Checkpoint {
    const self = try Actor.create(Checkpoint, allocator);
    self.name = name;
    // if we're the spawn checkpoint, shift us so the player isn't on top
    if (self.isCurrent()) {
        self.actor.position.yMut().* -= 8 * 5;
    }
    return self;
}

pub fn update(actor: *Actor) void {
    const self = @fieldParentPtr(Checkpoint, "actor", actor);
    if (self.isCurrent()) {
        self.t_wiggle = math.approach(self.t_wiggle, 0, time.delta / 0.7);
        self.model_on.update();
    }
}

pub fn onPickup(actor: *Actor) void {
    const self = @fieldParentPtr(Checkpoint, "actor", actor);
    if (!self.isCurrent()) {
        // audio.play(.sfx_checkpoint, actor.position);

        world.entry.checkpoint = self.name;
        if (world.entry.submap) {
            // TODO
            // save.current.checkpoint = name;
        }

        self.t_wiggle = 1;
    }
}

pub fn draw(actor: *Actor, si: Model.ShaderInfo) void {
    const self = @fieldParentPtr(Checkpoint, "actor", actor);
    const model_mat = actor.getTransform();
    if (self.isCurrent()) {
        self.model_on.draw(si, model_mat);
    } else {
        model_off.draw(si, model_mat);
    }

    // TODO sprites
}
