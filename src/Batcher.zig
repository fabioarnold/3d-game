const std = @import("std");
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Mat4 = za.Mat4;
const gl = @import("web/webgl.zig");
const shaders = @import("shaders.zig");
const Target = @import("Target.zig");

const Color = [4]f32;

const Vertex = packed struct { x: f32, y: f32, r: f32, g: f32, b: f32, a: f32 };

const Batcher = @This();

vertex_buffer: gl.GLuint = 0,
vertices: std.ArrayList(Vertex),

pub fn init(allocator: std.mem.Allocator) Batcher {
    return .{
        .vertices = std.ArrayList(Vertex).init(allocator),
    };
}

pub fn clear(self: *Batcher) void {
    self.vertices.clearRetainingCapacity();
}

pub fn draw(self: *Batcher, target: Target) void {
    const projection = Mat4.orthographic(0, target.width, target.height, 0, -1, 1);
    gl.glUseProgram(shaders.unlit.shader);
    gl.glUniformMatrix4fv(shaders.unlit.mvp_loc, 1, gl.GL_FALSE, &projection.data[0]);

    if (self.vertex_buffer == 0) gl.glGenBuffers(1, &self.vertex_buffer);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vertex_buffer);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(@sizeOf(Vertex) * self.vertices.items.len), @ptrCast(self.vertices.items.ptr), gl.GL_STREAM_DRAW);
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 2, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), null);
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 4, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(2 * @sizeOf(gl.GLfloat)));

    gl.glDrawArrays(gl.GL_TRIANGLES, 0, @intCast(self.vertices.items.len));
}

pub fn triangle(self: *Batcher, v0: Vec2, v1: Vec2, v2: Vec2, c: Color) void {
    self.vertices.append(.{ .x = v0.x(), .y = v0.y(), .r = c[0], .g = c[1], .b = c[2], .a = c[3] }) catch unreachable;
    self.vertices.append(.{ .x = v1.x(), .y = v1.y(), .r = c[0], .g = c[1], .b = c[2], .a = c[3] }) catch unreachable;
    self.vertices.append(.{ .x = v2.x(), .y = v2.y(), .r = c[0], .g = c[1], .b = c[2], .a = c[3] }) catch unreachable;
}

pub fn rect(self: *Batcher, x: f32, y: f32, w: f32, h: f32, color: Color) void {
    const v0 = Vec2.new(x, y);
    const v1 = Vec2.new(x + w, y);
    const v2 = Vec2.new(x + w, y + h);
    const v3 = Vec2.new(x, y + h);
    self.triangle(v0, v1, v2, color);
    self.triangle(v0, v2, v3, color);
}
