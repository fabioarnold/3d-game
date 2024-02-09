const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const wasm = @import("web/wasm.zig");
const gl = @import("web/webgl.zig");
const models = @import("models.zig");
const ShaderInfo = models.Model.ShaderInfo;
const SkinnedModel = @import("SkinnedModel.zig");
const Camera = @import("Camera.zig");
const Skybox = @import("Skybox.zig");
const Map = @import("Map.zig");
const logger = std.log.scoped(.world);

const World = @This();

pub const Actor = struct {
    position: Vec3 = Vec3.zero(),
    angle: f32 = 0,
    draw: *const fn (*Actor, ShaderInfo, Mat4) void,

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

    fn draw(actor: *Actor, si: ShaderInfo, view_projection: Mat4) void {
        const solid = @fieldParentPtr(Solid, "actor", actor);
        const mvp = view_projection.mul(Mat4.fromTranslate(actor.position));
        gl.glUniformMatrix4fv(si.mvp_loc, 1, gl.GL_FALSE, &mvp.data[0]);
        solid.model.draw();
    }
};

pub const FloatingDecoration = struct {
    actor: Actor,
    model: Map.Model,
    rate: f32,
    offset: f32,

    fn draw(actor: *Actor, si: ShaderInfo, view_projection: Mat4) void {
        const self = @fieldParentPtr(FloatingDecoration, "actor", actor);
        const t: f32 = @floatCast(wasm.performanceNow() / 1000.0);
        const translation = Mat4.fromTranslate(Vec3.new(0, 0, @sin(self.rate * t + self.offset) * 60.0));
        const mvp = view_projection.mul(translation);
        gl.glUniformMatrix4fv(si.mvp_loc, 1, gl.GL_FALSE, &mvp.data[0]);
        self.model.draw();
    }
};

pub const Strawberry = struct {
    actor: Actor,
    const model = models.findByName("strawberry");

    fn draw(actor: *Actor, si: ShaderInfo, view_projection: Mat4) void {
        const scale = Mat4.fromScale(Vec3.new(15, 15, 15));
        const mvp = view_projection.mul(actor.getTransform()).mul(scale);
        model.draw(si, mvp);
    }
};

pub const StaticProp = struct {
    actor: Actor,
    model: *models.Model,

    fn draw(actor: *Actor, si: ShaderInfo, view_projection: Mat4) void {
        const static_prop = @fieldParentPtr(StaticProp, "actor", actor);
        static_prop.model.draw(si, view_projection.mul(actor.getTransform()));
    }
};

pub const Checkpoint = struct {
    const model_off = models.findByName("flag_off");

    actor: Actor,
    model_on: SkinnedModel,
    current: bool,

    fn draw(actor: *Actor, si: ShaderInfo, view_projection: Mat4) void {
        const checkpoint = @fieldParentPtr(Checkpoint, "actor", actor);
        const mvp = view_projection.mul(actor.getTransform());
        if (checkpoint.current) {
            checkpoint.model_on.draw(si, mvp);
        } else {
            model_off.draw(si, mvp);
        }
    }
};

actors: std.ArrayList(*Actor),
skybox: Skybox,

var textured_unlit_shader: gl.GLuint = undefined;
var textured_unlit_mvp_loc: gl.GLint = undefined;

var textured_skinned_shader: gl.GLuint = undefined;
var textured_skinned_mvp_loc: gl.GLint = undefined;
var textured_skinned_joints_loc: gl.GLint = undefined;
var textured_skinned_blend_skin_loc: gl.GLint = undefined;

fn loadShader(vert_src: []const u8, frag_src: []const u8, attribs: []const []const u8) gl.GLuint {
    const vert_shader = gl.glInitShader(vert_src.ptr, vert_src.len, gl.GL_VERTEX_SHADER);
    const frag_shader = gl.glInitShader(frag_src.ptr, frag_src.len, gl.GL_FRAGMENT_SHADER);
    const program = gl.glCreateProgram();
    gl.glAttachShader(program, vert_shader);
    gl.glAttachShader(program, frag_shader);
    for (attribs, 0..) |attrib, i| {
        gl.glBindAttribLocation(program, i, @ptrCast(attrib));
    }
    gl.glLinkProgram(program);
    return program;
}

pub fn loadShaders() void {
    textured_unlit_shader = loadShader(
        @embedFile("shaders/transform_pt.vert"),
        @embedFile("shaders/textured_unlit.frag"),
        &.{ "position", "texcoord" },
    );
    gl.glUseProgram(textured_unlit_shader);
    textured_unlit_mvp_loc = gl.glGetUniformLocation(textured_unlit_shader, "mvp");
    gl.glUniform1i(gl.glGetUniformLocation(textured_unlit_shader, "texture"), 0);

    textured_skinned_shader = loadShader(
        @embedFile("shaders/transform_skinned.vert"),
        @embedFile("shaders/textured.frag"),
        &.{ "position", "normal", "texcoord", "joint", "weight" },
    );
    gl.glUseProgram(textured_skinned_shader);
    textured_skinned_mvp_loc = gl.glGetUniformLocation(textured_skinned_shader, "mvp");
    textured_skinned_joints_loc = gl.glGetUniformLocation(textured_skinned_shader, "joints");
    textured_skinned_blend_skin_loc = gl.glGetUniformLocation(textured_skinned_shader, "blend_skin");
    gl.glUniform1f(textured_skinned_blend_skin_loc, 0);
    gl.glUniform1i(gl.glGetUniformLocation(textured_skinned_shader, "texture"), 0);
}

pub fn load(self: *World, allocator: Allocator, map_name: []const u8) !void {
    self.actors = std.ArrayList(*Actor).init(allocator);
    // self.clear()
    try Map.load(allocator, self, map_name);
}

pub fn draw(self: World, camera: Camera) void {
    const view_projection = camera.projection().mul(camera.view());

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

    gl.glUseProgram(textured_skinned_shader);
    const si = ShaderInfo{
        .mvp_loc = textured_skinned_mvp_loc,
        .joints_loc = textured_skinned_joints_loc,
        .blend_skin_loc = textured_skinned_joints_loc,
    };
    for (self.actors.items) |actor| {
        actor.draw(actor, si, view_projection);
    }
}
