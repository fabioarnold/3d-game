const std = @import("std");
const za = @import("zalgebra");
const Mat4 = za.Mat4;
const gl = @import("web/webgl.zig");
const Model = @import("models.zig").Model;
const logger = std.log.scoped(.skinned_model);

const SkinnedModel = @This();

model: *Model,
animation_index: usize,

pub fn play(self: *SkinnedModel, animation_name: []const u8) void {
    for (self.model.gltf.data.animations.items, 0..) |animation, i| {
        if (std.mem.eql(u8, animation.name, animation_name)) {
            self.animation_index = i;
            logger.info("found animation \"{s}\" at index {}", .{ animation_name, i });
        }
    }
}

pub fn draw(self: SkinnedModel, mvp_loc: gl.GLint, view_projection: Mat4) void {
    self.model.draw(mvp_loc, view_projection);
}
