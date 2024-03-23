const std = @import("std");
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const gl = @import("web/webgl.zig");
const time = @import("time.zig");
const Batcher = @import("Batcher.zig");
const Target = @import("Target.zig");
const screenwipes = @import("screenwipes.zig");
const ScreenWipe = screenwipes.ScreenWipe;
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
        switch (self) {
            inline else => |scene| scene.deinit(),
        }
    }

    fn update(self: Scene) void {
        switch (self) {
            inline else => |scene| scene.update(),
        }
    }

    fn draw(self: Scene, target: Target) void {
        switch (self) {
            inline else => |scene| scene.draw(target),
        }
    }
};

const Transition = struct {
    const Step = enum {
        none,
        fade_out,
        hold,
        perform,
        fade_in,
    };

    const Mode = enum {
        replace,
    };

    mode: Mode,
    scene: Scene,
    to_black: ?ScreenWipe = null,
    from_black: ?ScreenWipe = null,
    hold_on_black_for: f32 = 0,
};
pub var game = Game{
    .scenes = undefined,
    .batcher = undefined,
};

scenes: std.ArrayList(Scene),
batcher: Batcher,
transition_step: Transition.Step = .none,
transition: ?Transition = null,

pub fn startup(self: *Game, allocator: std.mem.Allocator) void {
    self.scenes = std.ArrayList(Scene).init(allocator);
    self.batcher = Batcher.init(allocator);
    const titlescreen = Titlescreen.create(allocator) catch unreachable;
    self.scenes.append(.{ .titlescreen = titlescreen }) catch unreachable; // TODO: startup
}

pub fn isMidTransition(self: *Game) bool {
    return self.transition_step != .none;
}

pub fn goto(self: *Game, transition: Transition) void {
    self.transition = transition;
    self.transition_step = if (self.scenes.items.len > 0) .fade_out else .perform;
}

pub fn update(self: *Game) void {
    // update top scene
    self.scenes.getLast().update();

    // handle transitions
    if (self.transition) |*transition| {
        switch (self.transition_step) {
            .fade_out => {
                if (transition.to_black) |*to_black| {
                    to_black.update();
                    if (to_black.is_finished) self.transition_step = .hold;
                } else {
                    self.transition_step = .hold;
                }
            },
            .hold => {
                transition.hold_on_black_for -= time.delta;
                if (transition.hold_on_black_for <= 0) {
                    if (transition.from_black) |from_black| transition.to_black = from_black;
                    if (transition.to_black) |*to_black| to_black.restart(true);
                    self.transition_step = .perform;
                }
            },
            .perform => {
                // exit last scene

                if (self.transition) |t| {
                    switch (t.mode) {
                        .replace => {
                            if (self.scenes.popOrNull()) |*top| {
                                top.deinit();
                            }
                            self.scenes.append(t.scene) catch unreachable;
                        },
                    }
                }

                self.transition_step = .fade_in;
            },
            .fade_in => {
                if (transition.to_black) |*to_black| {
                    to_black.update();
                    if (to_black.is_finished) {
                        self.transition_step = .none;
                        self.transition = null;
                    }
                } else {
                    self.transition_step = .none;
                    self.transition = null;
                }
            },
            .none => {},
        }
    }
}

pub fn draw(self: *Game, target: Target) void {
    if (self.transition_step != .perform and self.transition_step != .hold) {
        // draw the world to the target
        self.scenes.getLast().draw(target);

        // draw screen wipe over top
        if (self.transition) |*transition| {
            if (transition.to_black) |*to_black| {
                gl.glClear(gl.GL_DEPTH_BUFFER_BIT);
                to_black.draw(&self.batcher, target.width, target.height);
                self.batcher.draw(target);
                self.batcher.clear();
            }
        }

        // draw the target to the window
    }
}
