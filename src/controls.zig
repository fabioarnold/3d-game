const za = @import("zalgebra");
const Vec2 = za.Vec2;

pub const ButtonState = struct {
    pressed: bool = false,
    down: bool = false,

    pub fn consumePress(self: *ButtonState) bool {
        if (self.pressed) {
            self.pressed = false;
            return true;
        }
        return false;
    }
};

pub var move: Vec2 = Vec2.zero();
pub var jump: ButtonState = .{};
pub var climb: ButtonState = .{};
pub var dash: ButtonState = .{};
pub const confirm = &jump; // alias
