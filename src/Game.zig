const Game = @This();

const TransitionStep = enum {
    none,
    fade_out,
    hold,
    perform,
    fade_in,
};

pub var game = Game{};

transition_step: TransitionStep = .none,

pub fn isMidTransition(self: *Game) bool {
    return self.transition_step != .none;
}
