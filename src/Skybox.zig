const std = @import("std");
const List = std.ArrayListUnmanaged;
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const gl = @import("web/webgl.zig");
const textures = @import("textures.zig");
const Texture = textures.Texture;

const Skybox = @This();

const Vertex = packed struct { x: f32, y: f32, z: f32, u: f32, v: f32 };

texture: Texture,
vertex_buffer: gl.GLuint,
index_buffer: gl.GLuint,

pub fn load(name: []const u8) Skybox {
    var self: Skybox = undefined;
    self.texture = textures.findByName(name);

    const tw: f32 = 1.0 / 4.0;
    const th: f32 = 1.0 / 3.0;
    const half_pixel: f32 = 0.5 / @as(f32,@floatFromInt(self.texture.width / 4));
    const u = makeTexcoords(0 * tw, 0 * th, tw, th, half_pixel);
    const d = makeTexcoords(0 * tw, 2 * th, tw, th, half_pixel);
    const n = makeTexcoords(0 * tw, 1 * th, tw, th, half_pixel);
    const e = makeTexcoords(1 * tw, 1 * th, tw, th, half_pixel);
    const s = makeTexcoords(2 * tw, 1 * th, tw, th, half_pixel);
    const w = makeTexcoords(3 * tw, 1 * th, tw, th, half_pixel);

    const v0 = Vec3.new(-1, -1, 1);
    const v1 = Vec3.new(1, -1, 1);
    const v2 = Vec3.new(1, 1, 1);
    const v3 = Vec3.new(-1, 1, 1);
    const v4 = Vec3.new(-1, -1, -1);
    const v5 = Vec3.new(1, -1, -1);
    const v6 = Vec3.new(1, 1, -1);
    const v7 = Vec3.new(-1, 1, -1);

    var vertices: [6 * 4]Vertex = undefined;
    var indices: [6 * 6]u32 = undefined;
    var vertex_list = List(Vertex).initBuffer(&vertices);
    var index_list = List(u32).initBuffer(&indices);
    addFace(&vertex_list, &index_list, &.{ v0, v1, v2, v3 }, &.{ u[3], u[2], u[1], u[0] });
    addFace(&vertex_list, &index_list, &.{ v7, v6, v5, v4 }, &.{ d[3], d[2], d[1], d[0] });
    addFace(&vertex_list, &index_list, &.{ v4, v5, v1, v0 }, &.{ n[2], n[3], n[0], n[1] });
    addFace(&vertex_list, &index_list, &.{ v6, v7, v3, v2 }, &.{ s[2], s[3], s[0], s[1] });
    addFace(&vertex_list, &index_list, &.{ v0, v3, v7, v4 }, &.{ e[0], e[1], e[2], e[3] });
    addFace(&vertex_list, &index_list, &.{ v5, v6, v2, v1 }, &.{ w[2], w[3], w[0], w[1] });

    gl.glGenBuffers(1, &self.vertex_buffer);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vertex_buffer);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(@sizeOf(@TypeOf(vertices))), @ptrCast(&vertices), gl.GL_STATIC_DRAW);
    gl.glGenBuffers(1, &self.index_buffer);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.index_buffer);
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(@TypeOf(indices))), @ptrCast(&indices), gl.GL_STATIC_DRAW);

    return self;
}

fn makeTexcoords(x: f32, y: f32, w: f32, h: f32, half_pixel: f32) [4]Vec2 {
    const x0 = x + half_pixel;
    const y0 = y + half_pixel;
    const x1 = x + w - half_pixel;
    const y1 = y + h - half_pixel;
    return .{ Vec2.new(x0, y0), Vec2.new(x1, y0), Vec2.new(x1, y1), Vec2.new(x0, y1) };
}

fn addFace(vertices: *List(Vertex), indices: *List(u32), positions: []const Vec3, texcoords: []const Vec2) void {
    const n = vertices.items.len;
    for (positions, texcoords) |position, texcoord| {
        vertices.appendAssumeCapacity(.{
            .x = position.x(),
            .y = position.y(),
            .z = position.z(),
            .u = texcoord.x(),
            .v = texcoord.y(),
        });
    }
    indices.appendSliceAssumeCapacity(&.{ n + 0, n + 1, n + 2, n + 0, n + 2, n + 3 });
}

pub fn draw(self: Skybox, mvp_loc: gl.GLint, view_projection: Mat4, size: f32) void {
    const mvp = view_projection.mul(Mat4.fromScale(Vec3.set(size)));
    gl.glUniformMatrix4fv(mvp_loc, 1, gl.GL_FALSE, &mvp.data[0]);

    gl.glBindTexture(gl.GL_TEXTURE_2D, self.texture.id);

    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vertex_buffer);
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), null);
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(3 * @sizeOf(gl.GLfloat)));

    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.index_buffer);
    gl.glDrawElements(gl.GL_TRIANGLES, 6 * 6, gl.GL_UNSIGNED_INT, null);
}
