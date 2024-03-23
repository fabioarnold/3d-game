const std = @import("std");
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const math = @import("math.zig");
const time = @import("time.zig");
const easings = @import("easings.zig");
const Batcher = @import("Batcher.zig");

const color_black = [_]f32{ 0, 0, 0, 1 };

const AngledWipe = struct {
    const rows = 12;
    const angle_size = 64;
    const duration = 0.5;

    fn draw(_: *AngledWipe, wipe: *ScreenWipe, batch: *Batcher, bounds_width: f32, bounds_height: f32) void {
        var triangles: [rows * 6]Vec2 = undefined;

        if ((wipe.percent <= 0 and wipe.is_from_black) or (wipe.percent >= 1 and !wipe.is_from_black)) {
            batch.rect(0, 0, bounds_width, bounds_height, color_black);
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
            batch.triangle(triangles[i + 0], triangles[i + 1], triangles[i + 2], color_black);
        }
    }
};

const SpotlightWipe = struct {
    const small_circle_radius = 96; // * Game.RelativeScale;
    const duration = 1.2;
    const ease_open_percent = 0.3; // how long (in percent) it eases the small circle open
    const ease_close_percent = 0.3; // how long (in percent) it eases the entire screen
    // ex. if 0.2 and 0.3, it would open for 0.2, wait until 0.7, then open for the remaining 0.3

    fn draw(_: *SpotlightWipe, wipe: *ScreenWipe, batch: *Batcher, bounds_width: f32, bounds_height: f32) void {
        const black = [_]f32{ 0, 0, 0, 1 };
        if ((wipe.percent <= 0 and wipe.is_from_black) or (wipe.percent >= 1 and !wipe.is_from_black)) {
            batch.rect(0, 0, bounds_width, bounds_height, black);
        }

        const ease = if (wipe.is_from_black) wipe.percent else 1 - wipe.percent;
        const point = Vec2.new(0.5 * bounds_width, 0.5 * bounds_height);

        // get the radius
        var radius: f32 = 0;
        const open_radius = small_circle_radius;

        if (ease < ease_open_percent) {
            radius = easings.outCubic(ease / ease_open_percent) * open_radius;
        } else if (ease < 1 - ease_close_percent) {
            radius = open_radius;
        } else {
            radius = open_radius + ((ease - (1 - ease_close_percent)) / ease_close_percent) * (bounds_width - open_radius);
        }

        drawSpotlight(batch, point, radius);
    }
};

fn drawSpotlight(batch: *Batcher, position: Vec2, radius: f32) void {
    var last_angle = Vec2.new(0, -1);
    const steps = 240;

    var i: f32 = 0;
    while (i < steps) : (i += 12) {
        const next_angle = math.dirFromAngle(((i + 12) / steps) * 360);

        // main circle
        {
            batch.triangle(
                position.add(last_angle.scale(5000)),
                position.add(last_angle.scale(radius)),
                position.add(next_angle.scale(radius)),
                color_black,
            );
            batch.triangle(
                position.add(last_angle.scale(5000)),
                position.add(next_angle.scale(radius)),
                position.add(next_angle.scale(5000)),
                color_black,
            );
        }

        last_angle = next_angle;
    }
}

pub const ScreenWipe = struct {
    const Type = enum {
        angled,
        spotlight,
    };

    typ: Type,
    is_from_black: bool = false,
    is_finished: bool = false,
    percent: f32 = 0,
    duration: f32,

    angled_wipe: AngledWipe = .{},
    spotlight_wipe: SpotlightWipe = .{},

    pub fn init(typ: Type) ScreenWipe {
        return switch (typ) {
            .angled => .{
                .typ = typ,
                .duration = AngledWipe.duration,
            },
            .spotlight => .{
                .typ = typ,
                .duration = SpotlightWipe.duration,
            },
        };
    }

    pub fn restart(self: *ScreenWipe, is_from_black: bool) void {
        self.percent = 0;
        self.is_from_black = is_from_black;
        self.is_finished = false;
    }

    pub fn update(self: *ScreenWipe) void {
        if (self.percent < 1) {
            self.percent = math.approach(self.percent, 1, time.delta / self.duration);
            if (self.percent >= 1) {
                self.is_finished = true;
            }
        }
    }

    pub fn draw(self: *ScreenWipe, batch: *Batcher, bounds_width: f32, bounds_height: f32) void {
        switch (self.typ) {
            .angled => self.angled_wipe.draw(self, batch, bounds_width, bounds_height),
            .spotlight => self.spotlight_wipe.draw(self, batch, bounds_width, bounds_height),
        }
    }
};
