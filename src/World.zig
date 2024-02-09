const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const wasm = @import("web/wasm.zig");
const gl = @import("web/webgl.zig");
const models = @import("models.zig");
const SkinnedModel = @import("SkinnedModel.zig");
const Camera = @import("Camera.zig");
const Skybox = @import("Skybox.zig");
const Map = @import("Map.zig");
const logger = std.log.scoped(.world);

const World = @This();

pub const Actor = struct {
    position: Vec3 = Vec3.zero(),
    angle: f32 = 0,
    draw: *const fn (*Actor, Mat4) void,

    pub fn create(comptime T: type, allocator: Allocator) !*T {
        var t = try allocator.create(T);
        t.actor = .{
            .draw = &T.draw,
        };
        return t;
    }

    fn getTransform(self: Actor) Mat4 {
        const r = Mat4.fromRotation(self.angle, Vec3.new(0, 0, 1));
        const t = Mat4.fromTranslate(self.position);
        return t.mul(r);
    }
};

pub const Solid = struct {
    actor: Actor,
    collidable: bool = true,
    model: Map.Model,

    fn draw(actor: *Actor, vp: Mat4) void {
        const solid = @fieldParentPtr(Solid, "actor", actor);
        const mvp = vp.mul(Mat4.fromTranslate(actor.position));
        gl.glUniformMatrix4fv(textured_mvp_loc, 1, gl.GL_FALSE, &mvp.data[0]);
        solid.model.draw();
    }
};

pub const FloatingDecoration = struct {
    actor: Actor,
    model: Map.Model,
    rate: f32,
    offset: f32,

    fn draw(actor: *Actor, vp: Mat4) void {
        const self = @fieldParentPtr(FloatingDecoration, "actor", actor);
        const t: f32 = @floatCast(wasm.performanceNow() / 1000.0);
        const mvp = vp.mul(Mat4.fromTranslate(Vec3.new(0, 0, @sin(self.rate * t + self.offset) * 60.0)));
        gl.glUniformMatrix4fv(textured_mvp_loc, 1, gl.GL_FALSE, &mvp.data[0]);
        self.model.draw();
    }
};

pub const Strawberry = struct {
    actor: Actor,
    const model = models.findByName("strawberry");

    fn draw(actor: *Actor, vp: Mat4) void {
        const scale = Mat4.fromScale(Vec3.new(15, 15, 15));
        model.draw(textured_mvp_loc, vp.mul(actor.getTransform()).mul(scale));
    }
};

pub const StaticProp = struct {
    actor: Actor,
    model: *models.Model,

    fn draw(actor: *Actor, vp: Mat4) void {
        const static_prop = @fieldParentPtr(StaticProp, "actor", actor);
        static_prop.model.draw(textured_mvp_loc, vp.mul(actor.getTransform()));
    }
};

pub const Checkpoint = struct {
    const model_off = models.findByName("flag_off");

    actor: Actor,
    model_on: SkinnedModel,
    current: bool,

    fn draw(actor: *Actor, vp: Mat4) void {
        const checkpoint = @fieldParentPtr(Checkpoint, "actor", actor);
        if (checkpoint.current) {
            checkpoint.model_on.draw(textured_mvp_loc, vp.mul(actor.getTransform()));
        } else {
            model_off.draw(textured_mvp_loc, vp.mul(actor.getTransform()));
        }
    }
};

actors: std.ArrayList(*Actor),
skybox: Skybox,

// TODO: move to Material struct
var textured_shader: gl.GLuint = undefined;
var textured_mvp_loc: gl.GLint = undefined;
var textured_unlit_shader: gl.GLuint = undefined;
var textured_unlit_mvp_loc: gl.GLint = undefined;

pub fn loadShaders() void {
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

pub fn load(self: *World, allocator: Allocator, map_name: []const u8) !void {
    self.actors = std.ArrayList(*Actor).init(allocator);
    // self.clear()
    try Map.load(allocator, self, map_name);
}

pub fn draw(self: World, camera: Camera) void {
    const projection = camera.projection();
    const view = camera.view();
    const view_projection = projection.mul(view);

    {
        gl.glUseProgram(textured_unlit_shader);
        gl.glDisable(gl.GL_DEPTH_TEST);
        gl.glDepthMask(gl.GL_FALSE);
        gl.glCullFace(gl.GL_FRONT);
        const mvp = view_projection.mul(Mat4.fromTranslate(camera.position));
        self.skybox.draw(textured_unlit_mvp_loc, mvp, 300);
        gl.glCullFace(gl.GL_BACK);
        gl.glDepthMask(gl.GL_TRUE);
        gl.glEnable(gl.GL_DEPTH_TEST);
    }
    gl.glUseProgram(textured_shader);

    for (self.actors.items) |actor| {
        actor.draw(actor, view_projection);
    }
}
