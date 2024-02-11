const std = @import("std");
const za = @import("zalgebra");
const zgltf = @import("zgltf");
const Vec3 = za.Vec3;
const Quat = za.Quat;
const Mat4 = za.Mat4;
const wasm = @import("web/wasm.zig");
const gl = @import("web/webgl.zig");
const Model = @import("Model.zig");
const logger = std.log.scoped(.skinned_model);

const SkinnedModel = @This();

model: *Model,
animation_index: usize,
time: f32, // in seconds

pub fn play(self: *SkinnedModel, animation_name: []const u8) void {
    for (self.model.gltf.data.animations.items, 0..) |animation, i| {
        if (std.mem.eql(u8, animation.name, animation_name)) {
            self.animation_index = i;
            break;
        }
    }
}

pub fn draw(self: SkinnedModel, si: Model.ShaderInfo, view_projection: Mat4) void {
    const data = &self.model.gltf.data;
    const nodes = data.nodes.items;

    var local_transforms: [32]Transform = undefined;
    for (nodes, 0..) |node, i| {
        local_transforms[i] = Transform.fromNode(node);
    }

    const now: f32 = @floatCast(wasm.performanceNow() / 1000.0);
    const t_min = 0.041667;
    const t_max = 1.08333;
    const t = @mod(now, (t_max - t_min)) + t_min;

    const animation = data.animations.items[self.animation_index];
    for (animation.channels.items) |channel| {
        const sampler = animation.samplers.items[channel.sampler];

        switch (channel.target.property) {
            .translation => local_transforms[channel.target.node].translation = self.sample(Vec3, sampler, t),
            .rotation => local_transforms[channel.target.node].rotation = self.sample(Quat, sampler, t),
            .scale => local_transforms[channel.target.node].scale = self.sample(Vec3, sampler, t),
            .weights => @panic("not implemented"),
        }
    }

    var global_transforms: [32]Mat4 = undefined;
    for (0..nodes.len) |i| {
        global_transforms[i] = local_transforms[i].toMat4();
        var node = &nodes[i];
        while (node.parent) |parent_index| : (node = &nodes[parent_index]) {
            const parent_transform = local_transforms[parent_index].toMat4();
            global_transforms[i] = parent_transform.mul(global_transforms[i]);
        }
    }

    self.model.drawWithTransforms(si, view_projection, &global_transforms);
}

const Transform = struct {
    rotation: Quat,
    scale: Vec3,
    translation: Vec3,

    fn fromNode(node: zgltf.Node) Transform {
        return .{
            // glb data is x,y,z,w instead of w,x,y,z
            .rotation = Quat.new(node.rotation[3], node.rotation[0], node.rotation[1], node.rotation[2]),
            .scale = Vec3.new(node.scale[0], node.scale[1], node.scale[2]),
            .translation = Vec3.new(node.translation[0], node.translation[1], node.translation[2]),
        };
    }

    fn identity() Transform {
        return .{
            .rotation = Quat.identity(),
            .scale = Vec3.new(1, 1, 1),
            .translation = Vec3.zero(),
        };
    }

    fn toMat4(self: Transform) Mat4 {
        return Mat4.recompose(self.translation, self.rotation, self.scale);
    }
};

fn sample(self: SkinnedModel, comptime T: type, sampler: zgltf.AnimationSampler, t: f32) T {
    const samples = self.model.getFloatBuffer(self.model.gltf.data.accessors.items[sampler.input]);
    const data = self.model.getFloatBuffer(self.model.gltf.data.accessors.items[sampler.output]);

    switch (sampler.interpolation) {
        .step => return Model.access(T, data, stepInterpolation(samples, t)),
        .linear => {
            const r = linearInterpolation(samples, t);
            const v0 = Model.access(T, data, r.prev_i);
            const v1 = Model.access(T, data, r.next_i);
            return switch (T) {
                Vec3 => Vec3.lerp(v0, v1, r.alpha),
                Quat => Quat.slerp(v0, v1, r.alpha),
                else => @compileError("unexpected type"),
            };
        },
        .cubicspline => @panic("not implemented"),
    }
}

/// Returns the index of the last sample less than `t`.
fn stepInterpolation(samples: []const f32, t: f32) usize {
    std.debug.assert(samples.len > 0);
    const S = struct {
        fn lessThan(_: void, lhs: f32, rhs: f32) bool {
            return lhs < rhs;
        }
    };
    const i = std.sort.lowerBound(f32, t, samples, {}, S.lessThan);
    return if (i > 0) i - 1 else 0;
}

/// Returns the indices of the samples around `t` and `alpha` to interpolate between those.
fn linearInterpolation(samples: []const f32, t: f32) struct {
    prev_i: usize,
    next_i: usize,
    alpha: f32,
} {
    const i = stepInterpolation(samples, t);
    if (i == samples.len - 1) return .{ .prev_i = i, .next_i = i, .alpha = 0 };

    const d = samples[i + 1] - samples[i];
    std.debug.assert(d > 0);
    const alpha = std.math.clamp((t - samples[i]) / d, 0, 1);

    return .{ .prev_i = i, .next_i = i + 1, .alpha = alpha };
}

test "stepInterpolation" {
    const samples = &[_]f32{ 0.1, 0.3, 0.6, 0.8, 1.2 };
    try std.testing.expectEqual(3, stepInterpolation(samples, 0.9));
    try std.testing.expectEqual(0, stepInterpolation(samples, 0));
    try std.testing.expectEqual(0, stepInterpolation(samples, -1));
    try std.testing.expectEqual(4, stepInterpolation(samples, 2));
    try std.testing.expectEqual(1, stepInterpolation(samples, 0.6));
}
