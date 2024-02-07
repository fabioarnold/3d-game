const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const gl = @import("web/webgl.zig");
const models = @import("models.zig");
const Camera = @import("Camera.zig");
const Skybox = @import("Skybox.zig");
const Map = @import("Map.zig");

const World = @This();

pub const Actor = struct {
    position: Vec3 = Vec3.zero,
    draw: *const fn (*Actor, Mat4) void,
};

pub const Solid = struct {
    actor: Actor,
    collidable: bool = true,
    model: Map.Model,

    pub fn create(allocator: Allocator) !*Solid {
        var solid = try allocator.create(Solid);
        solid.actor.draw = &Solid.draw;
        return solid;
    }

    fn draw(actor: *Actor, vp: Mat4) void {
        const solid = @fieldParentPtr(Solid, "actor", actor);
        const mvp = vp.mul(Mat4.fromTranslate(actor.position));
        gl.glUniformMatrix4fv(textured_mvp_loc, 1, gl.GL_FALSE, &mvp.data[0]);
        solid.model.draw();
    }
};

pub const Strawberry = struct {
    actor: Actor,
    const model = models.findByName("strawberry");

    pub fn create(allocator: Allocator) !*Strawberry {
        var strawberry = try allocator.create(Strawberry);
        strawberry.actor.draw = &Strawberry.draw;
        return strawberry;
    }

    fn draw(actor: *Actor, vp: Mat4) void {
        const scale = Mat4.fromScale(Vec3.new(15, 15, 15));
        model.draw(textured_mvp_loc, vp.mul(Mat4.fromTranslate(actor.position)).mul(scale));
    }
};

pub const StaticProp = struct {
    actor: Actor,
    model: *models.Model,

    pub fn create(allocator: Allocator) !*StaticProp {
        var static_prop = try allocator.create(StaticProp);
        static_prop.actor.draw = &StaticProp.draw;
        return static_prop;
    }

    fn draw(actor: *Actor, vp: Mat4) void {
        const static_prop = @fieldParentPtr(StaticProp, "actor", actor);
        static_prop.model.draw(textured_mvp_loc, vp.mul(Mat4.fromTranslate(actor.position)));
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