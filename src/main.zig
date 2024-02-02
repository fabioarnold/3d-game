const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const gl = @import("web/webgl.zig");
const keys = @import("web/keys.zig");
const wasm = @import("web/wasm.zig");
const assets = @import("assets");
const textures = @import("textures.zig");
const Map = @import("Map.zig");
pub const std_options = struct {
    pub const log_level = .info;
    pub const logFn = wasm.log;
};

const allocator = std.heap.wasm_allocator;

var video_width: f32 = 1280;
var video_height: f32 = 720;
var video_scale: f32 = 1;

var mvp_loc: gl.GLint = undefined;
var texture_loc: gl.GLint = undefined;
var color_loc: gl.GLint = undefined;

var loaded: bool = false;
var map: Map = undefined;
var map_vbo: gl.GLuint = undefined;
var map_ibo: gl.GLuint = undefined;

export fn onLoadImages() void {
    textures.load();
}

export fn onImagesLoaded() void {
    loaded = true;

    gl.glEnable(gl.GL_DEPTH_TEST);
    map = Map.load(allocator, "1", assets.maps.map1) catch unreachable;
    gl.glGenBuffers(1, &map_vbo);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, map_vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(map.vertices.items.len * @sizeOf(f32)), @ptrCast(map.vertices.items.ptr), gl.GL_STATIC_DRAW);
    gl.glGenBuffers(1, &map_ibo);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, map_ibo);
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(map.indices.items.len * @sizeOf(u16)), @ptrCast(map.indices.items.ptr), gl.GL_STATIC_DRAW);

    const vert_src = @embedFile("shaders/transform.vert");
    const frag_src = @embedFile("shaders/color.frag");
    const vert_shader = gl.glInitShader(vert_src, vert_src.len, gl.GL_VERTEX_SHADER);
    const frag_shader = gl.glInitShader(frag_src, frag_src.len, gl.GL_FRAGMENT_SHADER);
    const program = gl.glLinkShaderProgram(vert_shader, frag_shader);
    gl.glUseProgram(program);
    mvp_loc = gl.glGetUniformLocation(program, "mvp");
    texture_loc = gl.glGetUniformLocation(program, "texture");
    color_loc = gl.glGetUniformLocation(program, "color");
    gl.glUniform1i(texture_loc, 0);

    // var buf: c_uint = undefined;
    // gl.glGenBuffers(1, &buf);
    // gl.glBindBuffer(gl.GL_ARRAY_BUFFER, buf);
    // const vertex_data = @import("zig-mark.zig").positions;
    // gl.glBufferData(gl.GL_ARRAY_BUFFER, vertex_data.len * @sizeOf(f32), &vertex_data, gl.GL_STATIC_DRAW);

}

export fn onResize(w: c_uint, h: c_uint, s: f32) void {
    video_width = @floatFromInt(w);
    video_height = @floatFromInt(h);
    video_scale = s;
    gl.glViewport(0, 0, @intFromFloat(s * video_width), @intFromFloat(s * video_height));
}

var cam_x: f32 = 0;
var cam_y: f32 = -600;
export fn onKeyDown(key: c_uint) void {
    switch (key) {
        keys.KEY_LEFT => cam_x -= 10,
        keys.KEY_RIGHT => cam_x += 10,
        keys.KEY_DOWN => cam_y -= 10,
        keys.KEY_UP => cam_y += 10,
        else => {},
    }
}

var frame: usize = 0;
export fn onAnimationFrame() void {
    gl.glClearColor(0.5, 0.5, 0.5, 1);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

    if (!loaded) return;

    const projection = za.perspective(45.0, video_width / video_height, 0.1, 10000.0);
    const view = Mat4.fromTranslate(Vec3.new(cam_x, cam_y, -3000));
    const zUp = Mat4.fromRotation(-90, Vec3.right());
    const rot_anim = Mat4.fromRotation(0.2 * @as(f32, @floatFromInt(frame)), Vec3.up());
    const model = rot_anim.mul(Mat4.fromTranslate(Vec3.new(0, 0, 0)).mul(zUp));

    const mvp = projection.mul(view.mul(model));
    gl.glUniformMatrix4fv(mvp_loc, 1, gl.GL_FALSE, &mvp.data[0]);

    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(gl.GLfloat), null);
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(gl.GLfloat), @ptrFromInt(3 * @sizeOf(gl.GLfloat)));
    gl.glEnableVertexAttribArray(2);
    gl.glVertexAttribPointer(2, 3, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(gl.GLfloat), @ptrFromInt(5 * @sizeOf(gl.GLfloat)));

    // gl.glUniform4f(color_loc, 0.97, 0.64, 0.11, 1);
    // gl.glDrawArrays(gl.GL_TRIANGLES, 0, 120);
    // gl.glUniform4f(color_loc, 0.98, 0.82, 0.6, 1);
    // gl.glDrawArrays(gl.GL_TRIANGLES, 120, 66);
    // gl.glUniform4f(color_loc, 0.6, 0.35, 0.02, 1);
    // gl.glDrawArrays(gl.GL_TRIANGLES, 186, 90);

    for (map.materials.items) |material| {
        gl.glBindTexture(gl.GL_TEXTURE_2D, material.texture.id);
        gl.glDrawElements(gl.GL_TRIANGLES, material.index_count, gl.GL_UNSIGNED_SHORT, material.index_start * @sizeOf(u16));
    }

    // frame += 1;
}
