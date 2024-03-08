const World = @import("World.zig");
const Game = @This();

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
    scene: *World,
};
pub var game = Game{ .scene = undefined };

transition_step: TransitionStep = .none,
transition: ?Transition = null,
scene: *World,

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
