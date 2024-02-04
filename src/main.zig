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
const Camera = @import("Camera.zig");
const Skybox = @import("Skybox.zig");
const Map = @import("Map.zig");
pub const std_options = struct {
    pub const log_level = .info;
    pub const logFn = wasm.log;
};

const logger = std.log.scoped(.main);

const allocator = std.heap.wasm_allocator;

var video_width: f32 = 1280;
var video_height: f32 = 720;
var video_scale: f32 = 1;

const State = struct {
    camera: Camera = .{},
};
var state: State = .{};

var textured_shader: gl.GLuint = undefined;
var textured_mvp_loc: gl.GLint = undefined;
var textured_unlit_shader: gl.GLuint = undefined;
var textured_unlit_mvp_loc: gl.GLint = undefined;

var loaded: bool = false; // all textures are loaded

var skybox: Skybox = undefined;
var map: Map = undefined;

export fn onLoadImages() void {
    textures.load();
}

export fn onImagesLoaded() void {
    loaded = true;

    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glEnable(gl.GL_CULL_FACE);

    textures.updateParameters();

    map = Map.load(allocator, "1", assets.maps.map1) catch unreachable;
    skybox = Skybox.load("skybox_city");

    const ptn_vert_src = @embedFile("shaders/transform_ptn.vert");
    const ptn_vert_shader = gl.glInitShader(ptn_vert_src, ptn_vert_src.len, gl.GL_VERTEX_SHADER);
    const textured_frag_src = @embedFile("shaders/textured.frag");
    const textured_frag_shader = gl.glInitShader(textured_frag_src, textured_frag_src.len, gl.GL_FRAGMENT_SHADER);
    textured_shader = gl.glLinkShaderProgram(ptn_vert_shader, textured_frag_shader);
    gl.glUseProgram(textured_shader);
    textured_mvp_loc = gl.glGetUniformLocation(textured_shader, "mvp");
    gl.glUniform1i(gl.glGetUniformLocation(textured_shader, "texture"), 0);
    
    const pt_vert_src = @embedFile("shaders/transform_pt.vert");
    const pt_vert_shader = gl.glInitShader(pt_vert_src, pt_vert_src.len, gl.GL_VERTEX_SHADER);
    const textured_unlit_frag_src = @embedFile("shaders/textured_unlit.frag");
    const textured_unlit_frag_shader = gl.glInitShader(textured_unlit_frag_src, textured_unlit_frag_src.len, gl.GL_FRAGMENT_SHADER);
    textured_unlit_shader = gl.glLinkShaderProgram(pt_vert_shader, textured_unlit_frag_shader);
    gl.glUseProgram(textured_unlit_shader);
    textured_unlit_mvp_loc = gl.glGetUniformLocation(textured_unlit_shader, "mvp");
    gl.glUniform1i(gl.glGetUniformLocation(textured_unlit_shader, "texture"), 0);
}

export fn onLoadSnapshot(handle: wasm.String.Handle) void {
    const string = wasm.String.get(handle);
    defer wasm.String.dealloc(handle);
    const parsed = std.json.parseFromSlice(State, allocator, string, .{.ignore_unknown_fields=true}) catch |e| {
        logger.err("Snapshot loading failed {}", .{e});
        return;
    };
    defer parsed.deinit();
    state = parsed.value;

}

export fn onSaveSnapshot() wasm.String.Handle {
    var array = std.ArrayList(u8).init(allocator);
    std.json.stringify(state, .{}, array.writer()) catch |e| {
        logger.err("Snapshot saving failed {}", .{e});
        return wasm.String.invalid;
    };
    logger.info("snapshot: {s}", .{array.items});
    return wasm.String.fromSlice(array.items);
}

export fn onResize(w: c_uint, h: c_uint, s: f32) void {
    video_width = @floatFromInt(w);
    video_height = @floatFromInt(h);
    video_scale = s;
    gl.glViewport(0, 0, @intFromFloat(s * video_width), @intFromFloat(s * video_height));
    state.camera.aspect_ratio = video_width / video_height;
}

export fn onKeyDown(key: c_uint) void {
    _ = key;
}
export fn onKeyUp(key: c_uint) void {
    _ = key;
}
export fn onMouseMove(x: c_int, y: c_int) void {
    const dx: f32 = @floatFromInt(y);
    const dy: f32 = @floatFromInt(x);
    state.camera.rotateView(dx * -0.25, dy * 0.25);
}

export fn onAnimationFrame() void {
    gl.glClearColor(0, 0, 0, 1);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

    if (!loaded) return;

    state.camera.handleKeys();
    state.camera.inspect();

    const projection = state.camera.projection();
    const view = state.camera.view();
    const view_projection = projection.mul(view);

    {
        gl.glUseProgram(textured_unlit_shader);
        gl.glDisable(gl.GL_DEPTH_TEST);
        gl.glDepthMask(gl.GL_FALSE);
        gl.glCullFace(gl.GL_FRONT);
        const mvp = view_projection.mul(Mat4.fromTranslate(state.camera.position));
        skybox.draw(textured_unlit_mvp_loc, mvp, 300);
        gl.glCullFace(gl.GL_BACK);
        gl.glDepthMask(gl.GL_TRUE);
        gl.glEnable(gl.GL_DEPTH_TEST);
    }
    gl.glUseProgram(textured_shader);
    map.draw(textured_mvp_loc, view_projection);
}
