const std = @import("std");
const Allocator = std.mem.Allocator;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const wasm = @import("web/wasm.zig");
const gl = @import("web/webgl.zig");
const models = @import("models.zig");
const Model = @import("Model.zig");
const ShaderInfo = Model.ShaderInfo;
const SkinnedModel = @import("SkinnedModel.zig");
const Camera = @import("Camera.zig");
const Skybox = @import("Skybox.zig");
const Map = @import("Map.zig");
const logger = std.log.scoped(.world);

const World = @This();

pub const Actor = struct {
    position: Vec3 = Vec3.zero(),
    angle: f32 = 0,
    updateFn: *const fn (*Actor) void,
    drawFn: *const fn (*Actor, ShaderInfo) void,

    pub fn create(comptime T: type, allocator: Allocator) !*T {
        var t = try allocator.create(T);
        t.actor = .{
            .updateFn = if (@hasDecl(T, "update")) &@field(T, "update") else &updateNoOp,
            .drawFn = &T.draw,
        };
        if (@hasDecl(T, "init")) {
            const initFn = &@field(T, "init");
            initFn(&t.actor);
        }
        return t;
    }

    fn getTransform(self: Actor) Mat4 {
        const r = Mat4.fromRotation(self.angle, Vec3.new(0, 0, 1));
        const t = Mat4.fromTranslate(self.position);
        return t.mul(r);
    }

    fn updateNoOp(_: *Actor) void {}

    fn update(self: *Actor) void {
        self.updateFn(self);
    }

    fn draw(self: *Actor, si: ShaderInfo) void {
        self.drawFn(self, si);
    }
};

pub const Solid = struct {
    actor: Actor,
    collidable: bool = true,
    model: Map.Model,

    fn draw(actor: *Actor, si: ShaderInfo) void {
        const solid = @fieldParentPtr(Solid, "actor", actor);
        const model_mat = Mat4.fromTranslate(actor.position);
        gl.glUniformMatrix4fv(si.model_loc, 1, gl.GL_FALSE, &model_mat.data[0]);
        solid.model.draw();
    }
};

pub const FloatingDecoration = struct {
    actor: Actor,
    model: Map.Model,
    rate: f32,
    offset: f32,

    fn draw(actor: *Actor, si: ShaderInfo) void {
        const self = @fieldParentPtr(FloatingDecoration, "actor", actor);
        const t: f32 = @floatCast(wasm.performanceNow() / 1000.0);
        const model_mat = Mat4.fromTranslate(Vec3.new(0, 0, @sin(self.rate * t + self.offset) * 60.0));
        gl.glUniformMatrix4fv(si.model_loc, 1, gl.GL_FALSE, &model_mat.data[0]);
        self.model.draw();
    }
};

pub const Strawberry = struct {
    actor: Actor,
    const model = models.findByName("strawberry");

    fn draw(actor: *Actor, si: ShaderInfo) void {
        const t: f32 = @floatCast(wasm.performanceNow() / 1000.0);
        const transform = actor.getTransform().mul(
            Mat4.fromScale(Vec3.new(3, 3, 3)),
        ).mul(Mat4.fromTranslate(
            Vec3.new(0, 0, 2 * @sin(t * 2)),
        ).mul(
            Mat4.fromRotation(std.math.radiansToDegrees(f32, 3 * t), Vec3.new(0, 0, 1)),
        ).mul(
            Mat4.fromScale(Vec3.new(5, 5, 5)),
        ));
        model.draw(si, transform);
    }
};

pub const Granny = struct {
    actor: Actor,
    skinned_model: SkinnedModel,

    fn init(actor: *Actor) void {
        const granny = @fieldParentPtr(Granny, "actor", actor);
        granny.skinned_model.model = models.findByName("granny");
        granny.skinned_model.play("Idle");
    }

    fn draw(actor: *Actor, si: ShaderInfo) void {
        const granny = @fieldParentPtr(Granny, "actor", actor);
        const transform = Mat4.fromScale(Vec3.new(15, 15, 15)).mul(Mat4.fromTranslate(Vec3.new(0, 0, -0.5)));
        const model_mat = actor.getTransform().mul(transform);
        granny.skinned_model.draw(si, model_mat);
    }
};

pub const StaticProp = struct {
    actor: Actor,
    model: *Model,

    fn draw(actor: *Actor, si: ShaderInfo) void {
        const static_prop = @fieldParentPtr(StaticProp, "actor", actor);
        static_prop.model.draw(si, actor.getTransform());
    }
};

pub const Checkpoint = struct {
    const model_off = models.findByName("flag_off");

    actor: Actor,
    model_on: SkinnedModel,
    current: bool,

    fn draw(actor: *Actor, si: ShaderInfo) void {
        const checkpoint = @fieldParentPtr(Checkpoint, "actor", actor);
        const model_mat = actor.getTransform();
        if (checkpoint.current) {
            checkpoint.model_on.draw(si, model_mat);
        } else {
            model_off.draw(si, model_mat);
        }
    }
};

pub const Player = struct {
    actor: Actor,
    skinned_model: SkinnedModel,

    fn init(actor: *Actor) void {
        const player = @fieldParentPtr(Player, "actor", actor);
        player.skinned_model.model = models.findByName("player");
        player.skinned_model.play("Idle");
    }

    fn update(actor: *Actor) void {
        actor.angle += 1;
    }

    fn draw(actor: *Actor, si: ShaderInfo) void {
        const player = @fieldParentPtr(Player, "actor", actor);
        const transform = Mat4.fromScale(Vec3.new(15, 15, 15));
        const model_mat = actor.getTransform().mul(transform);
        player.skinned_model.draw(si, model_mat);
    }
};

actors: std.ArrayList(*Actor),
skybox: Skybox,

var textured_unlit_shader: gl.GLuint = undefined;
var textured_unlit_mvp_loc: gl.GLint = undefined;

var textured_skinned_shader: gl.GLuint = undefined;
var textured_skinned_viewprojection_loc: gl.GLint = undefined;
var textured_skinned_model_loc: gl.GLint = undefined;
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
        &.{ "a_position", "a_texcoord" },
    );
    gl.glUseProgram(textured_unlit_shader);
    textured_unlit_mvp_loc = gl.glGetUniformLocation(textured_unlit_shader, "u_mvp");
    gl.glUniform1i(gl.glGetUniformLocation(textured_unlit_shader, "u_texture"), 0);

    textured_skinned_shader = loadShader(
        @embedFile("shaders/transform_skinned.vert"),
        @embedFile("shaders/textured.frag"),
        &.{ "a_position", "a_normal", "a_texcoord", "a_joint", "a_weight" },
    );
    gl.glUseProgram(textured_skinned_shader);
    textured_skinned_viewprojection_loc = gl.glGetUniformLocation(textured_skinned_shader, "u_viewprojection");
    textured_skinned_model_loc = gl.glGetUniformLocation(textured_skinned_shader, "u_model");
    textured_skinned_joints_loc = gl.glGetUniformLocation(textured_skinned_shader, "u_joints");
    textured_skinned_blend_skin_loc = gl.glGetUniformLocation(textured_skinned_shader, "u_blend_skin");
    gl.glUniform1f(textured_skinned_blend_skin_loc, 0);
    gl.glUniform1i(gl.glGetUniformLocation(textured_skinned_shader, "u_texture"), 0);
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
    gl.glUniformMatrix4fv(textured_skinned_viewprojection_loc, 1, gl.GL_FALSE, &view_projection.data[0]);
    const si = ShaderInfo{
        .model_loc = textured_skinned_model_loc,
        .joints_loc = textured_skinned_joints_loc,
        .blend_skin_loc = textured_skinned_blend_skin_loc,
    };
    for (self.actors.items) |actor| {
        actor.update();
        actor.draw(si);
    }
}
