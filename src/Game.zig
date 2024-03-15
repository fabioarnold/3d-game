const std = @import("std");
const Target = @import("Target.zig");
const Titlescreen = @import("scenes/Titlescreen.zig");
const World = @import("World.zig");
const Game = @This();

const SceneType = enum {
    titlescreen,
    world,
};

const Scene = union(SceneType) {
    titlescreen: *Titlescreen,
    world: *World,

    fn deinit(self: Scene) void {
        switch(self) {
            inline else => |scene| scene.deinit(),
        }
    }

    fn update(self: Scene) void {
        switch(self) {
            inline else => |scene| scene.update(),
        }
    }

    fn draw(self: Scene, target: Target) void {
        switch(self) {
            inline else => |scene| scene.draw(target),
        }
    }
};

const TransitionStep = enum {
    none,
    fade_out,
    hold,
    perform,
    fade_in,
};
const Mode = enum {
    replace,
};
const Transition = struct {
    mode: Mode,
    scene: Scene,
};
pub var game = Game{ .scene = undefined };

transition_step: TransitionStep = .none,
transition: ?Transition = null,
scene: Scene,

pub fn startup(self: *Game, allocator: std.mem.Allocator) void {
    const titlescreen = Titlescreen.create(allocator) catch unreachable;
    self.scene = .{.titlescreen = titlescreen};
}

pub fn isMidTransition(self: *Game) bool {
    return self.transition_step != .none;
}

pub fn goto(self: *Game, transition: Transition) void {
    self.transition = transition;
}

pub fn update(self: *Game) void {
    if (self.transition) |t| {
        switch (t.mode) {
            .replace => {
                self.scene.deinit();
                self.scene = t.scene;
            },
        }
        self.transition = null;
    }
    self.scene.update();
}

pub fn draw(self: *Game, target: Target) void {
    self.scene.draw(target);
}
