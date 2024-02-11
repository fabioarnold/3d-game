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
    mvp_loc: gl.GLint,
    joints_loc: gl.GLint,
    blend_skin_loc: gl.GLint,
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

pub fn draw(self: Model, si: ShaderInfo, view_projection: Mat4) void {
    const z_up = Mat4.fromRotation(90, Vec3.new(1, 0, 0));

    for (self.gltf.data.nodes.items) |node| {
        const mesh_index = node.mesh orelse continue;
        var model = Mat4{ .data = zgltf.getGlobalTransform(&self.gltf.data, node) };
        if (node.skin) |_| {
            // TODO
            model = Mat4.identity();
            gl.glUniform1f(si.blend_skin_loc, 1);
        }
        defer gl.glUniform1f(si.blend_skin_loc, 0);
        const mvp = view_projection.mul(z_up).mul(model);
        gl.glUniformMatrix4fv(si.mvp_loc, 1, gl.GL_FALSE, &mvp.data[0]);
        const mesh = self.gltf.data.meshes.items[mesh_index];
        for (mesh.primitives.items) |primitive| {
            const material = self.gltf.data.materials.items[primitive.material.?];
            const texture = self.textures[material.metallic_roughness.base_color_texture.?.index];
            gl.glBindTexture(gl.GL_TEXTURE_2D, texture);
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
            const accessor = self.gltf.data.accessors.items[accessor_index];
            const buffer_view = self.gltf.data.buffer_views.items[accessor.buffer_view.?];
            gl.glBindBuffer(@intFromEnum(buffer_view.target.?), self.buffer_objects[accessor.buffer_view.?]);
            gl.glDrawElements(@intFromEnum(primitive.mode), accessor.count, @intFromEnum(accessor.component_type), accessor.byte_offset);
        }
    }
}
