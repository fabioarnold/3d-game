const std = @import("std");

pub fn inCubic(x: f32) f32 {
    return x * x * x;
}

pub fn outCubic(x: f32) f32 {
    const one_minus_x = 1.0 - x;
    return 1.0 - one_minus_x * one_minus_x * one_minus_x;
}

pub fn inSine(t: f32) f32 {
    return 0 - @cos(std.math.pi / 2.0 * t) + 1;
}

pub fn outSine(t: f32) f32 {
    return @sin(std.math.pi / 2.0 * t);
}
