const std = @import("std");
const Texture = @import("textures.zig").Texture;
const zgltf = @import("zgltf");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Quat = za.Quat;
const Mat4 = za.Mat4;
const gl = @import("web/webgl.zig");

const Model = @This();

pub const ShaderInfo = struct {
    model_loc: gl.GLint,
    joints_loc: gl.GLint,
    blend_skin_loc: gl.GLint,
    color_loc: gl.GLint,
};

gltf: zgltf,
buffer_objects: []gl.GLuint,
textures: []gl.GLuint,

pub fn load(self: *Model, allocator: std.mem.Allocator, data: []align(4) const u8) !void {
    self.gltf = zgltf.init(allocator);
    try self.gltf.parse(data);
    const binary = self.gltf.glb_binary.?;

    // load buffers
    self.buffer_objects = try allocator.alloc(gl.GLuint, self.gltf.data.buffer_views.items.len);
    gl.glGenBuffers(@intCast(self.buffer_objects.len), self.buffer_objects.ptr);
    for (self.gltf.data.buffer_views.items, self.buffer_objects) |buffer_view, buffer_object| {
        if (buffer_view.target) |target| {
            gl.glBindBuffer(@intFromEnum(target), buffer_object);
            gl.glBufferData(@intFromEnum(target), @intCast(buffer_view.byte_length), binary.ptr + buffer_view.byte_offset, gl.GL_STATIC_DRAW);
        }
    }

    // load textures
    self.textures = try allocator.alloc(gl.GLuint, self.gltf.data.textures.items.len);
    gl.glGenTextures(@intCast(self.textures.len), self.textures.ptr);
    for (self.gltf.data.textures.items, 0..) |texture, i| {
        const image = self.gltf.data.images.items[texture.source.?];
        std.debug.assert(std.mem.eql(u8, image.mime_type.?, "image/png"));
        self.textures[i] = gl.jsLoadTexturePNG(image.data.?.ptr, image.data.?.len, null, null);
        // const sampler = self.gltf.data.samplers.items[texture.sampler.?]; // TODO set filter, wrap
    }
}

pub fn computeAnimationDuration(self: Model, animation: zgltf.Animation) f32 {
    var duration: f32 = 0;
    for (animation.samplers.items) |sampler| {
        const input = self.gltf.data.accessors.items[sampler.input];
        const samples = self.getFloatBuffer(input);
        duration = @max(duration, samples[samples.len - 1]);
    }
    return duration;
}

fn getComponentCount(accessor: zgltf.Accessor) usize {
    return switch (accessor.type) {
        .scalar => 1,
        .vec2 => 2,
        .vec3 => 3,
        .vec4 => 4,
        .mat2x2 => 4,
        .mat3x3 => 9,
        .mat4x4 => 16,
    };
}

pub fn getFloatBuffer(self: Model, accessor: zgltf.Accessor) []const f32 {
    std.debug.assert(accessor.component_type == .float);
    const binary = self.gltf.glb_binary.?;
    const buffer_view = self.gltf.data.buffer_views.items[accessor.buffer_view.?];
    const byte_offset = accessor.byte_offset + buffer_view.byte_offset;
    std.debug.assert(byte_offset % 4 == 0);
    const buffer: [*]align(4) const u8 = @alignCast(binary.ptr + byte_offset);
    const component_count = getComponentCount(accessor);
    const count = component_count * @as(usize, @intCast(accessor.count));
    return @as([*]const f32, @ptrCast(buffer))[0..count];
}

pub fn access(comptime T: type, data: []const f32, i: usize) T {
    return switch (T) {
        Vec3 => Vec3.new(data[3 * i + 0], data[3 * i + 1], data[3 * i + 2]),
        Quat => Quat.new(data[4 * i + 3], data[4 * i + 0], data[4 * i + 1], data[4 * i + 2]),
        Mat4 => Mat4.fromSlice(data[16 * i ..][0..16]),
        else => @compileError("unexpected type"),
    };
}

fn bindVertexAttrib(self: Model, accessor_index: usize, attrib_index: usize) void {
    const accessor = self.gltf.data.accessors.items[accessor_index];
    const buffer_view = self.gltf.data.buffer_views.items[accessor.buffer_view.?];
    gl.glBindBuffer(@intFromEnum(buffer_view.target.?), self.buffer_objects[accessor.buffer_view.?]);
    const size: gl.GLint = @intCast(getComponentCount(accessor));
    const typ: gl.GLenum = @intFromEnum(accessor.component_type);
    const normalized: gl.GLboolean = @intFromBool(accessor.normalized);
    const stride: gl.GLsizei = @intCast(accessor.stride);
    const pointer: ?*const anyopaque = @ptrFromInt(accessor.byte_offset);
    gl.glEnableVertexAttribArray(attrib_index);
    gl.glVertexAttribPointer(attrib_index, size, typ, normalized, stride, pointer);
}

pub fn drawWithTransforms(self: Model, si: ShaderInfo, model_mat: Mat4, global_transforms: []const Mat4) void {
    const data = &self.gltf.data;
    const nodes = data.nodes.items;

    const z_up = Mat4.fromRotation(90, Vec3.new(1, 0, 0));

    for (nodes, 0..) |node, node_i| {
        const mesh = data.meshes.items[node.mesh orelse continue];

        if (node.skin) |skin_index| {
            const skin = data.skins.items[skin_index];
            const inverse_bind_matrices = self.getFloatBuffer(data.accessors.items[skin.inverse_bind_matrices.?]);
            var joints: [32]Mat4 = undefined;
            for (skin.joints.items, 0..) |joint_index, i| {
                const inverse_bind_matrix = access(Mat4, inverse_bind_matrices, i);
                joints[i] = global_transforms[joint_index].mul(inverse_bind_matrix);
            }
            gl.glUniformMatrix4fv(si.joints_loc, @intCast(skin.joints.items.len), gl.GL_FALSE, &joints[0].data[0]);
            gl.glUniform1f(si.blend_skin_loc, 1);
            const model = model_mat.mul(z_up);
            gl.glUniformMatrix4fv(si.model_loc, 1, gl.GL_FALSE, &model.data[0]);
        } else {
            const model = model_mat.mul(z_up).mul(global_transforms[node_i]);
            gl.glUniformMatrix4fv(si.model_loc, 1, gl.GL_FALSE, &model.data[0]);
        }
        defer gl.glUniform1f(si.blend_skin_loc, 0);

        for (mesh.primitives.items) |primitive| {
            const material = data.materials.items[primitive.material.?].metallic_roughness;
            const texture = self.textures[material.base_color_texture.?.index];
            gl.glBindTexture(gl.GL_TEXTURE_2D, texture);
            const c = material.base_color_factor;
            gl.glUniform4f(si.color_loc, c[0], c[1], c[2], c[3]);
            for (primitive.attributes.items) |attribute| {
                switch (attribute) {
                    .position => |accessor_index| self.bindVertexAttrib(accessor_index, 0),
                    .normal => |accessor_index| self.bindVertexAttrib(accessor_index, 1),
                    .texcoord => |accessor_index| self.bindVertexAttrib(accessor_index, 2),
                    .joints => |accessor_index| self.bindVertexAttrib(accessor_index, 3),
                    .weights => |accessor_index| self.bindVertexAttrib(accessor_index, 4),
                    else => {},
                }
            }
            defer for (primitive.attributes.items) |attribute| {
                switch (attribute) {
                    .position => gl.glDisableVertexAttribArray(0),
                    .normal => gl.glDisableVertexAttribArray(1),
                    .texcoord => gl.glDisableVertexAttribArray(2),
                    .joints => gl.glDisableVertexAttribArray(3),
                    .weights => gl.glDisableVertexAttribArray(4),
                    else => {},
                }
            };
            const accessor_index = primitive.indices.?;
            const accessor = data.accessors.items[accessor_index];
            const buffer_view = data.buffer_views.items[accessor.buffer_view.?];
            gl.glBindBuffer(@intFromEnum(buffer_view.target.?), self.buffer_objects[accessor.buffer_view.?]);
            gl.glDrawElements(@intFromEnum(primitive.mode), accessor.count, @intFromEnum(accessor.component_type), accessor.byte_offset);
        }
    }
}

pub fn draw(self: Model, si: ShaderInfo, model_mat: Mat4) void {
    const nodes = self.gltf.data.nodes.items;

    var local_transforms: [32]Mat4 = undefined;
    for (nodes, 0..) |node, i| {
        local_transforms[i] = .{ .data = zgltf.getLocalTransform(node) };
    }

    var global_transforms: [32]Mat4 = undefined;
    for (0..nodes.len) |i| {
        global_transforms[i] = local_transforms[i];
        // in gltf parents can appear after their children, so we can't do a linear scan
        var node = &nodes[i];
        while (node.parent) |parent_index| : (node = &nodes[parent_index]) {
            global_transforms[i] = local_transforms[parent_index].mul(global_transforms[i]);
        }
    }

    self.drawWithTransforms(si, model_mat, &global_transforms);
}
