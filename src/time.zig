// in seconds
pub var now: f32 = 0;
pub var last: f32 = 0;
pub var delta: f32 = 1.0 / 60.0;

pub fn onInterval(interval: f32) bool {
    return @floor((now - delta) / interval) < @floor(now / interval);
}
