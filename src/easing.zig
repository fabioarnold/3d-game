pub fn outCubic(x: f32) f32 {
    const one_minus_x = 1.0 - x;
    return 1.0 - one_minus_x * one_minus_x * one_minus_x;
}
