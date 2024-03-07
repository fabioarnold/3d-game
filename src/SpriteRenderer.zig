const std = @import("std");
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const gl = @import("web/webgl.zig");
const Sprite = @import("Sprite.zig");

const logger = std.log.scoped(.sprite_renderer);

const SpriteRenderer = @This();

const Vertex = packed struct { x: f32, y: f32, z: f32, u: f32, v: f32, r: f32, g: f32, b: f32, a: f32, pad: f32 = undefined };
const Batch = struct { texture_id: gl.GLuint, index_start: u32, index_count: u32 };

const t0 = Vec2.new(0, 0);
const t1 = Vec2.new(1, 0);
const t2 = Vec2.new(1, 1);
const t3 = Vec2.new(0, 1);

var vbo: gl.GLuint = undefined;
var ebo: gl.GLuint = undefined;
var vertices: std.ArrayList(Vertex) = undefined;
var indices: std.ArrayList(u32) = undefined;
var batches: std.ArrayList(Batch) = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    vertices = std.ArrayList(Vertex).init(allocator);
    indices = std.ArrayList(u32).init(allocator);
    batches = std.ArrayList(Batch).init(allocator);
    gl.glGenBuffers(1, &vbo);
    gl.glGenBuffers(1, &ebo);
}

fn addVertex(list: *std.ArrayList(Vertex), v: Vec3, uv: Vec2, color: [4]f32) void {
    list.appendAssumeCapacity(.{
        .x = v.x(),
        .y = v.y(),
        .z = v.z(),
        .u = uv.x(),
        .v = uv.y(),
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    });
}

pub fn draw(sprites: []const Sprite, post_effects: bool) !void {
    if (sprites.len == 0) return;

    vertices.clearRetainingCapacity();
    try vertices.ensureTotalCapacity(sprites.len * 4);
    indices.clearRetainingCapacity();
    try indices.ensureTotalCapacity(sprites.len * 6);
    batches.clearRetainingCapacity();

    var init_batch = Batch{ .texture_id = 0xFFFFFFFF, .index_start = 0, .index_count = 0 };
    var current = &init_batch;
    for (sprites) |*sprite| {
        if (sprite.post != post_effects) continue;

        if (sprite.texture.id != current.texture_id) {
            current = batches.addOne() catch unreachable;
            current.* = .{
                .texture_id = sprite.texture.id,
                .index_start = indices.items.len,
                .index_count = 0,
            };
        }
        const i = vertices.items.len;
        addVertex(&vertices, sprite.v0, t0, sprite.color);
        addVertex(&vertices, sprite.v1, t1, sprite.color);
        addVertex(&vertices, sprite.v2, t2, sprite.color);
        addVertex(&vertices, sprite.v3, t3, sprite.color);

        indices.appendAssumeCapacity(i + 2);
        indices.appendAssumeCapacity(i + 1);
        indices.appendAssumeCapacity(i + 0);
        indices.appendAssumeCapacity(i + 3);
        indices.appendAssumeCapacity(i + 2);
        indices.appendAssumeCapacity(i + 0);

        current.index_count += 6;
    }

    if (post_effects) gl.glDisable(gl.GL_DEPTH_TEST);
    defer gl.glEnable(gl.GL_DEPTH_TEST);

    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(@sizeOf(Vertex) * vertices.items.len), @ptrCast(vertices.items.ptr), gl.GL_STREAM_DRAW);

    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(u32) * indices.items.len), @ptrCast(indices.items.ptr), gl.GL_STREAM_DRAW);

    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), null);
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(3 * @sizeOf(gl.GLfloat)));
    gl.glEnableVertexAttribArray(2);
    gl.glVertexAttribPointer(2, 4, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(5 * @sizeOf(gl.GLfloat)));

    for (batches.items) |*batch| {
        gl.glBindTexture(gl.GL_TEXTURE_2D, batch.texture_id);
        gl.glDrawElements(gl.GL_TRIANGLES, @intCast(batch.index_count), gl.GL_UNSIGNED_INT, batch.index_start * @sizeOf(u32));
    }
}
