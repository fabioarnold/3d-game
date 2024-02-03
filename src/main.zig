const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat3 = za.Mat3;
const Mat4 = za.Mat4;
const gl = @import("web/webgl.zig");
const keys = @import("web/keys.zig");
const wasm = @import("web/wasm.zig");
const inspector = @import("inspector.zig");
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

const Camera = struct {
    position: Vec3,
    angles: Vec3,
    field_of_view: f32,
    near_plane: f32,
    far_plane: f32,

    fn projection(self: Camera) Mat4 {
        const ar = video_width / video_height;
        return za.perspective(self.field_of_view, ar, self.near_plane, self.far_plane);
    }

    fn view(self: Camera) Mat4 {
        const z_up = Mat4.fromRotation(90, Vec3.right());
        const v = z_up.mul(Mat4.fromEulerAngles(self.angles)).translate(self.position);
        return v.inv();
    }

    fn inspect(self: *Camera) void {
        inspector.vec3("pos", &camera.position);
        inspector.floatRange("rot_x", &camera.angles.data[0], -90, 90);
        inspector.floatRange("rot_y", &camera.angles.data[1], -360, 360);
        inspector.floatRange("fov", &camera.field_of_view, 30, 120);
        inspector.float("near", &self.near_plane);
        inspector.float("far", &self.far_plane);
    }
};
var camera = Camera{
    .position = Vec3.new(0, 0, 1000),
    .angles = Vec3.new(0, 0, 0),
    .field_of_view = 90, // Quake Pro
    .near_plane = 1.0,
    .far_plane = 10000.0,
};

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
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(map.indices.items.len * @sizeOf(u32)), @ptrCast(map.indices.items.ptr), gl.GL_STATIC_DRAW);

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
}

export fn onResize(w: c_uint, h: c_uint, s: f32) void {
    video_width = @floatFromInt(w);
    video_height = @floatFromInt(h);
    video_scale = s;
    gl.glViewport(0, 0, @intFromFloat(s * video_width), @intFromFloat(s * video_height));
}

export fn onKeyDown(key: c_uint) void {
    _ = key;
}
export fn onKeyUp(key: c_uint) void {
    _ = key;
}
export fn onMouseMove(x: c_int, y: c_int) void {
    var dx: f32 = @floatFromInt(y);
    var dy: f32 = @floatFromInt(x);
    dx *= -0.3;
    dy *= -0.3;
    camera.angles.data[0] = std.math.clamp(camera.angles.x() + dx, -90, 90);
    camera.angles.data[1] = std.math.wrap(camera.angles.y() + dy, 360);
}

export fn onAnimationFrame() void {
    gl.glClearColor(1, 1, 1, 1);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

    if (!loaded) return;

    const speed: f32 = if (wasm.isKeyDown(keys.KEY_SHIFT)) 100 else 20;
    var move = Vec3.zero();
    if (wasm.isKeyDown(keys.KEY_W)) move.data[1] += speed;
    if (wasm.isKeyDown(keys.KEY_A)) move.data[0] -= speed;
    if (wasm.isKeyDown(keys.KEY_S)) move.data[1] -= speed;
    if (wasm.isKeyDown(keys.KEY_D)) move.data[0] += speed;
    const rot_x = Mat3.fromRotation(camera.angles.x(), Vec3.new(1, 0, 0));
    const rot_z = Mat3.fromRotation(camera.angles.y(), Vec3.new(0, 0, 1));
    move = rot_z.mul(rot_x).mulByVec3(move);
    if (wasm.isKeyDown(keys.KEY_Q)) move.data[2] -= speed;
    if (wasm.isKeyDown(keys.KEY_E)) move.data[2] += speed;
    camera.position = camera.position.add(move);

    camera.inspect();

    const projection = camera.projection();
    const view = camera.view();
    const model = Mat4.identity();

    const mvp = projection.mul(view.mul(model));
    gl.glUniformMatrix4fv(mvp_loc, 1, gl.GL_FALSE, &mvp.data[0]);

    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(gl.GLfloat), null);
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(gl.GLfloat), @ptrFromInt(3 * @sizeOf(gl.GLfloat)));
    gl.glEnableVertexAttribArray(2);
    gl.glVertexAttribPointer(2, 3, gl.GL_FLOAT, gl.GL_FALSE, 8 * @sizeOf(gl.GLfloat), @ptrFromInt(5 * @sizeOf(gl.GLfloat)));

    for (map.materials.items) |material| {
        gl.glBindTexture(gl.GL_TEXTURE_2D, material.texture.id);
        gl.glDrawElements(gl.GL_TRIANGLES, @intCast(material.index_count), gl.GL_UNSIGNED_INT, material.index_start * @sizeOf(u32));
    }

    // frame += 1;
}
