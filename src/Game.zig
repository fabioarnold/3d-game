const std = @import("std");
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const gl = @import("web/webgl.zig");
const math = @import("math.zig");
const time = @import("time.zig");
const Batcher = @import("Batcher.zig");
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

const AngledWipe = struct {
    const rows = 12;
    const angle_size = 64;
    const duration = 0.5;

    fn draw(_: *AngledWipe, wipe: *ScreenWipe, batch: *Batcher, bounds_width: f32, bounds_height: f32) void {
        const black = [_]f32{ 0, 0, 0, 1 };
        var triangles: [rows * 6]Vec2 = undefined;

        if ((wipe.percent <= 0 and wipe.is_from_black) or (wipe.percent >= 1 and !wipe.is_from_black)) {
            batch.rect(0, 0, bounds_width, bounds_height, black);
        }

        const row_height = (bounds_height + 20) / rows;
        const left = -angle_size;
        const width = bounds_width + angle_size;

        for (0..rows) |i| {
            const x = left;
            const y = -10 + @as(f32, @floatFromInt(i)) * row_height;
            var e: f32 = 0;

            // get delay based on Y
            const across = @as(f32, @floatFromInt(i)) / rows;
            const delay = (if (wipe.is_from_black) 1 - across else across) * 0.3;

            // get ease after delay
            if (wipe.percent > delay) {
                e = @min(1, (wipe.percent - delay) / 0.7);
            }

            // start full, go to nothing, if we're wiping in
            if (wipe.is_from_black) {
                e = 1 - e;
            }

            // resulting width
            const w = width * e;

            const v = i * 6;
            triangles[v + 0] = Vec2.new(x, y);
            triangles[v + 1] = Vec2.new(x, y + row_height);
            triangles[v + 2] = Vec2.new(x + w, y);

            triangles[v + 3] = Vec2.new(x + w, y);
            triangles[v + 4] = Vec2.new(x, y + row_height);
            triangles[v + 5] = Vec2.new(x + w + angle_size, y + row_height);
        }

        // flip if we're wiping in
        if (wipe.is_from_black) {
            for (&triangles) |*triangle| {
                triangle.xMut().* = bounds_width - triangle.x();
                triangle.yMut().* = bounds_height - triangle.y();
            }
        }

        var i: usize = 0;
        while (i < triangles.len) : (i += 3) {
            batch.triangle(triangles[i + 0], triangles[i + 1], triangles[i + 2], black);
        }
    }
};

pub const ScreenWipe = struct {
    const Type = enum {
        angled,
    };

    typ: Type,
    is_from_black: bool = false,
    is_finished: bool = false,
    percent: f32 = 0,
    duration: f32,

    angled_wipe: AngledWipe = .{},

    pub fn init(typ: Type) ScreenWipe {
        return switch (typ) {
            .angled => .{
                .typ = typ,
                .duration = AngledWipe.duration,
            },
        };
    }

    pub fn restart(self: *ScreenWipe, is_from_black: bool) void {
        self.percent = 0;
        self.is_from_black = is_from_black;
        self.is_finished = false;
    }

    fn update(self: *ScreenWipe) void {
        if (self.percent < 1) {
            self.percent = math.approach(self.percent, 1, time.delta / self.duration);
            if (self.percent >= 1) {
                self.is_finished = true;
            }
        }
    }

    fn draw(self: *ScreenWipe, batch: *Batcher, bounds_width: f32, bounds_height: f32) void {
        switch (self.typ) {
            .angled => self.angled_wipe.draw(self, batch, bounds_width, bounds_height),
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
