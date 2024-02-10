const std = @import("std");
const assets = @import("assets");
const Texture = @import("textures.zig").Texture;
const zgltf = @import("zgltf");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Quat = za.Quat;
const Mat4 = za.Mat4;
const gl = @import("web/webgl.zig");
const logger = std.log.scoped(.models);

pub const Model = struct {
    gltf: zgltf,
    buffer_objects: []gl.GLuint,
    textures: []gl.GLuint,

    fn load(self: *Model, allocator: std.mem.Allocator, data: []align(4) const u8) !void {
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

    fn bindVertexAttrib(self: Model, accessor_index: usize, attrib_index: usize) void {
        const accessor = self.gltf.data.accessors.items[accessor_index];
        const buffer_view = self.gltf.data.buffer_views.items[accessor.buffer_view.?];
        gl.glBindBuffer(@intFromEnum(buffer_view.target.?), self.buffer_objects[accessor.buffer_view.?]);
        const size: gl.GLint = switch (accessor.type) {
            .scalar => 1,
            .vec2 => 2,
            .vec3 => 3,
            .vec4 => 4,
            .mat2x2 => 4,
            .mat3x3 => 9,
            .mat4x4 => 16,
        };
        const typ: gl.GLenum = @intFromEnum(accessor.component_type);
        const normalized: gl.GLboolean = @intFromBool(accessor.normalized);
        const stride: gl.GLsizei = @intCast(accessor.stride);
        const pointer: ?*const anyopaque = @ptrFromInt(accessor.byte_offset);
        gl.glEnableVertexAttribArray(attrib_index);
        gl.glVertexAttribPointer(attrib_index, size, typ, normalized, stride, pointer);
    }

    pub const ShaderInfo = struct {
        mvp_loc: gl.GLint,
        joints_loc: gl.GLint,
        blend_skin_loc: gl.GLint,
    };

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
};

var models: [@typeInfo(assets.models).Struct.decls.len]Model = undefined;

pub fn load(allocator: std.mem.Allocator) !void {
    inline for (@typeInfo(assets.models).Struct.decls, 0..) |decl, i| {
        const data = @field(assets.models, decl.name);
        // FIXME @embedFile isn't aligned https://github.com/ziglang/zig/issues/4680
        const aligned_data = try allocator.alignedAlloc(u8, 4, data.len);
        @memcpy(aligned_data, data);
        // defer allocator.free(aligned_data); // TODO: we can free if we load the animation data
        try models[i].load(allocator, aligned_data);
        // logger.info("loaded {s}:", .{decl.name});
        // debugPrint(&models[i].gltf);
    }
}

pub fn findByName(name: []const u8) *Model {
    inline for (@typeInfo(assets.models).Struct.decls, 0..) |decl, i| {
        if (std.mem.eql(u8, decl.name, name)) return &models[i];
    }
    unreachable;
}

pub fn debugPrint(self: *const zgltf) void {
    const msg =
        \\
        \\  glTF file info:
        \\
        \\    Node       {}
        \\    Mesh       {}
        \\    Skin       {}
        \\    Animation  {}
        \\    Texture    {}
        \\    Material   {}
        \\
    ;

    logger.info(msg, .{
        self.data.nodes.items.len,
        self.data.meshes.items.len,
        self.data.skins.items.len,
        self.data.animations.items.len,
        self.data.textures.items.len,
        self.data.materials.items.len,
    });

    logger.info("  Details:\n", .{});

    if (self.data.skins.items.len > 0) {
        logger.info("   Skins found:", .{});

        for (self.data.skins.items) |skin| {
            logger.info("     '{s}' found with {} joint(s).", .{
                skin.name,
                skin.joints.items.len,
            });
        }

        logger.info("", .{});
    }

    if (self.data.animations.items.len > 0) {
        logger.info("  Animations found:", .{});

        for (self.data.animations.items) |anim| {
            logger.info(
                "     '{s}' found with {} sampler(s) and {} channel(s).",
                .{ anim.name, anim.samplers.items.len, anim.channels.items.len },
            );
        }

        logger.info("", .{});
    }
}
