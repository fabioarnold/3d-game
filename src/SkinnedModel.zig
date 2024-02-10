const std = @import("std");
const za = @import("zalgebra");
const zgltf = @import("zgltf");
const Vec3 = za.Vec3;
const Quat = za.Quat;
const Mat4 = za.Mat4;
const wasm = @import("web/wasm.zig");
const gl = @import("web/webgl.zig");
const Model = @import("models.zig").Model;
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

fn getFloatBuffer(self: SkinnedModel, accessor: zgltf.Accessor) []const f32 {
    std.debug.assert(accessor.component_type == .float);
    const binary = self.model.gltf.glb_binary.?;
    const buffer_view = self.model.gltf.data.buffer_views.items[accessor.buffer_view.?];
    const byte_offset = accessor.byte_offset + buffer_view.byte_offset;
    std.debug.assert(byte_offset % 4 == 0);
    const buffer: [*]align(4) const u8 = @alignCast(binary.ptr + byte_offset);
    const component_count: usize = switch (accessor.type) {
        .scalar => 1,
        .vec2 => 2,
        .vec3 => 3,
        .vec4 => 4,
        .mat2x2 => 4,
        .mat3x3 => 9,
        .mat4x4 => 16,
    };
    const count: usize = component_count * @as(usize, @intCast(accessor.count));
    return @as([*]const f32, @ptrCast(buffer))[0..count];
}

const Transform = struct {
    rotation: Quat, // glb data is x,y,z,w instead of w,x,y,z
    scale: Vec3,
    translation: Vec3,

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

fn sampleVec3(self: SkinnedModel, sampler: zgltf.AnimationSampler, t: f32) Vec3 {
    const t_samples = self.getFloatBuffer(self.model.gltf.data.accessors.items[sampler.input]);
    const data = self.getFloatBuffer(self.model.gltf.data.accessors.items[sampler.output]);

    switch (sampler.interpolation) {
        .step => return accessVec3(data, stepInterpolation(t_samples, t)),
        .linear => {
            var prev_i: usize = undefined;
            var next_i: usize = undefined;
            var alpha: f32 = undefined;
            linearInterpolation(t_samples, t, &prev_i, &next_i, &alpha);
            return Vec3.lerp(accessVec3(data, prev_i), accessVec3(data, next_i), alpha);
        },
        else => @panic("not implemented"),
    }
}

fn sampleQuat(self: SkinnedModel, sampler: zgltf.AnimationSampler, t: f32) Quat {
    const t_samples = self.getFloatBuffer(self.model.gltf.data.accessors.items[sampler.input]);
    const data = self.getFloatBuffer(self.model.gltf.data.accessors.items[sampler.output]);

    switch (sampler.interpolation) {
        .step => {
            return accessQuat(data, stepInterpolation(t_samples, t));
        },
        .linear => {
            var prev_i: usize = undefined;
            var next_i: usize = undefined;
            var alpha: f32 = undefined;
            linearInterpolation(t_samples, t, &prev_i, &next_i, &alpha);
            return Quat.slerp(accessQuat(data, prev_i), accessQuat(data, next_i), alpha);
        },
        else => @panic("not implemented"),
    }
}

pub fn draw(self: SkinnedModel, si: Model.ShaderInfo, view_projection: Mat4) void {
    const data = &self.model.gltf.data;
    const nodes = data.nodes.items;

    var poses: [32]Transform = undefined;
    for (0..poses.len) |i| {
        if (i < nodes.len) {
            const node = nodes[i];
            poses[i] = .{
                .rotation = Quat.new(node.rotation[3], node.rotation[0], node.rotation[1], node.rotation[2]),
                .scale = Vec3.new(node.scale[0], node.scale[1], node.scale[2]),
                .translation = Vec3.new(node.translation[0], node.translation[1], node.translation[2]),
            };
        } else {
            poses[i] = Transform.identity();
        }
    }

    const now: f32 = @floatCast(wasm.performanceNow() / 1000.0);
    const t_min = 0.041667;
    const t_max = 1.08333;
    const t = @mod(now, (t_max - t_min)) + t_min;

    const animation = data.animations.items[self.animation_index];
    for (animation.channels.items) |channel| {
        const sampler = animation.samplers.items[channel.sampler];

        // logger.info("animating node {} property {}", .{channel.target.node, channel.target.property});
        switch (channel.target.property) {
            .translation => poses[channel.target.node].translation = self.sampleVec3(sampler, t),
            .rotation => poses[channel.target.node].rotation = self.sampleQuat(sampler, t),
            .scale => poses[channel.target.node].scale = self.sampleVec3(sampler, t),
            else => @panic("not implemented"),
        }
    }

    var global_poses: [32]Mat4 = undefined;
    for (poses, 0..) |pose, i| {
        var transform = pose.toMat4();

        if (i < nodes.len) {
            var node = &nodes[i];
            while (node.parent) |parent_index| : (node = &nodes[parent_index]) {
                const parent_transform = poses[parent_index].toMat4();
                transform = parent_transform.mul(transform);
            }
        }

        global_poses[i] = transform;
    }

    var joints: [32]Mat4 = undefined;

    const skin = data.skins.items[0];
    const ibm_buf = self.getFloatBuffer(data.accessors.items[skin.inverse_bind_matrices.?]);
    for (skin.joints.items, 0..) |joint_index, i| {
        var ibm: Mat4 = undefined;
        @memcpy(@as([*]f32, @ptrCast(&ibm.data[0][0])), ibm_buf[16 * i .. 16 * i + 16]);
        joints[i] = global_poses[joint_index].mul(ibm);
    }

    gl.glUniformMatrix4fv(si.joints_loc, joints.len, gl.GL_FALSE, &joints[0].data[0]);

    self.model.draw(si, view_projection);
}

fn accessQuat(data: []const f32, i: usize) Quat {
    return Quat.new(data[4 * i + 3], data[4 * i + 0], data[4 * i + 1], data[4 * i + 2]);
}

fn accessVec3(data: []const f32, i: usize) Vec3 {
    return Vec3.new(data[3 * i + 0], data[3 * i + 1], data[3 * i + 2]);
}

fn stepInterpolation(t_samples: []const f32, t: f32) usize {
    var prev_i: usize = 0;
    var prev_t: f32 = t_samples[prev_i];
    for (t_samples, 0..) |t_sample, i| {
        if (t_sample < t and t_sample > prev_t) {
            prev_t = t_sample;
            prev_i = i;
        }
    }
    return prev_i;
}

fn linearInterpolation(t_samples: []const f32, t: f32, out_prev_i: *usize, out_next_i: *usize, out_alpha: *f32) void {
    var prev_i: usize = 0;
    var prev_t: f32 = t_samples[prev_i];
    var next_i: usize = t_samples.len - 1;
    var next_t: f32 = t_samples[next_i];
    for (t_samples, 0..) |t_sample, i| {
        if (t_sample < t and t_sample > prev_t) {
            prev_t = t_sample;
            prev_i = i;
        }
        if (t_sample > t and t_sample < next_t) {
            next_t = t_sample;
            next_i = i;
        }
    }
    const alpha = (t - prev_t) / (next_t - prev_t);

    out_prev_i.* = prev_i;
    out_next_i.* = next_i;
    out_alpha.* = alpha;
}
