const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const gl = @import("web/webgl.zig");
const logger = std.log.scoped(.primitives);

var sphere_vbo: gl.GLuint = undefined;
var sphere_ebo: gl.GLuint = undefined;

const Vertex = packed struct { x: f32, y: f32, z: f32, nx: f32, ny: f32, nz: f32 };

fn addVertex(vertex_list: *std.ArrayListUnmanaged(Vertex), x: f32, y: f32, z: f32) void {
    const n = Vec3.new(x, y, z).norm();
    vertex_list.appendAssumeCapacity(.{ .x = x, .y = y, .z = z, .nx = n.x(), .ny = n.y(), .nz = n.z() });
}

pub fn load() void {
    const stack_count = 6;
    const slice_count = 6;

    var vertices: [stack_count * slice_count + 2]Vertex = undefined;
    var indices: [(stack_count - 1) * slice_count * 6]u32 = undefined;

    var vertex_list = std.ArrayListUnmanaged(Vertex).initBuffer(&vertices);
    var index_list = std.ArrayListUnmanaged(u32).initBuffer(&indices);

    // add top vertex
    addVertex(&vertex_list, 0, 0, 1);

    // generate vertices per stack / slice
    for (0..stack_count) |i| {
        const phi: f32 = std.math.pi * @as(f32, @floatFromInt(i + 1)) / stack_count;
        for (0..slice_count) |j| {
            const theta = 2 * std.math.pi * @as(f32, @floatFromInt(j)) / slice_count;
            const x = @sin(phi) * @cos(theta);
            const y = @sin(phi) * @sin(theta);
            const z = @cos(phi);
            addVertex(&vertex_list, x, y, z);
        }
    }

    // add bottom vertex
    addVertex(&vertex_list, 0, 0, -1);

    // add top / bottom triangles
    for (0..slice_count) |i| {
        index_list.appendAssumeCapacity(0);
        index_list.appendAssumeCapacity(i + 1);
        index_list.appendAssumeCapacity((i + 1) % slice_count + 1);
        index_list.appendAssumeCapacity(slice_count * stack_count + 1);
        index_list.appendAssumeCapacity((i + 1) % slice_count + slice_count * (stack_count - 2) + 1);
        index_list.appendAssumeCapacity(i + slice_count * (stack_count - 2) + 1);
    }

    // add quads per stack / slice
    for (0..stack_count - 2) |j| {
        const j0 = j * slice_count + 1;
        const j1 = (j + 1) * slice_count + 1;
        for (0..slice_count) |i| {
            const index0 = j0 + i;
            const index1 = j1 + i;
            const index2 = j1 + (i + 1) % slice_count;
            const index3 = j0 + (i + 1) % slice_count;
            index_list.appendAssumeCapacity(index0);
            index_list.appendAssumeCapacity(index1);
            index_list.appendAssumeCapacity(index2);
            index_list.appendAssumeCapacity(index0);
            index_list.appendAssumeCapacity(index2);
            index_list.appendAssumeCapacity(index3);
        }
    }

    gl.glGenBuffers(1, &sphere_vbo);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, sphere_vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(@sizeOf(@TypeOf(vertices))), @ptrCast(&vertices), gl.GL_STATIC_DRAW);
    gl.glGenBuffers(1, &sphere_ebo);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, sphere_ebo);
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(@TypeOf(indices))), @ptrCast(&indices), gl.GL_STATIC_DRAW);
}

pub fn drawSphere() void {
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, sphere_vbo);
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), null);
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 3, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(3 * @sizeOf(gl.GLfloat)));

    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, sphere_ebo);
    gl.glDrawElements(gl.GL_TRIANGLES, 180, gl.GL_UNSIGNED_INT, null);
}
