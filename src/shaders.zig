const gl = @import("web/webgl.zig");
const Vec3 = @import("zalgebra").Vec3;

pub const textured_unlit = struct {
    pub var shader: gl.GLuint = undefined;
    pub var mvp_loc: gl.GLint = undefined;
};

pub const textured_skinned = struct {
    pub var shader: gl.GLuint = undefined;
    pub var viewprojection_loc: gl.GLint = undefined;
    pub var model_loc: gl.GLint = undefined;
    pub var joints_loc: gl.GLint = undefined;
    pub var blend_skin_loc: gl.GLint = undefined;
    pub var color_loc: gl.GLint = undefined;
    pub var effects_loc: gl.GLint = undefined;
};

pub const sprite = struct {
    pub var shader: gl.GLuint = undefined;
    pub var viewprojection_loc: gl.GLint = undefined;
};

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

pub fn load() void {
    textured_unlit.shader = loadShader(
        @embedFile("shaders/transform_pt.vert"),
        @embedFile("shaders/textured_unlit.frag"),
        &.{ "a_position", "a_texcoord" },
    );
    gl.glUseProgram(textured_unlit.shader);
    textured_unlit.mvp_loc = gl.glGetUniformLocation(textured_unlit.shader, "u_mvp");
    gl.glUniform1i(gl.glGetUniformLocation(textured_unlit.shader, "u_texture"), 0);

    textured_skinned.shader = loadShader(
        @embedFile("shaders/transform_skinned.vert"),
        @embedFile("shaders/textured.frag"),
        &.{ "a_position", "a_normal", "a_texcoord", "a_joint", "a_weight" },
    );
    gl.glUseProgram(textured_skinned.shader);
    textured_skinned.viewprojection_loc = gl.glGetUniformLocation(textured_skinned.shader, "u_viewprojection");
    textured_skinned.model_loc = gl.glGetUniformLocation(textured_skinned.shader, "u_model");
    textured_skinned.joints_loc = gl.glGetUniformLocation(textured_skinned.shader, "u_joints");
    textured_skinned.blend_skin_loc = gl.glGetUniformLocation(textured_skinned.shader, "u_blend_skin");
    const textured_skinned_texture_loc = gl.glGetUniformLocation(textured_skinned.shader, "u_texture");
    textured_skinned.color_loc = gl.glGetUniformLocation(textured_skinned.shader, "u_color");
    const textured_skinned_sun_loc = gl.glGetUniformLocation(textured_skinned.shader, "u_sun");
    textured_skinned.effects_loc = gl.glGetUniformLocation(textured_skinned.shader, "u_effects");
    gl.glUniform1f(textured_skinned.blend_skin_loc, 0);
    gl.glUniform1i(textured_skinned_texture_loc, 0);
    gl.glUniform4f(textured_skinned.color_loc, 1, 1, 1, 1);
    const sun = Vec3.new(0, -0.7, -1.0).norm();
    gl.glUniform3f(textured_skinned_sun_loc, sun.x(), sun.y(), sun.z());
    gl.glUniform1f(textured_skinned.effects_loc, 1);

    sprite.shader = loadShader(
        @embedFile("shaders/sprite.vert"),
        @embedFile("shaders/sprite.frag"),
        &.{ "a_position", "a_texcoord", "a_color" },
    );
    gl.glUseProgram(sprite.shader);
    sprite.viewprojection_loc = gl.glGetUniformLocation(sprite.shader, "u_viewprojection");
    const sprite_texture_loc = gl.glGetUniformLocation(sprite.shader, "u_texture");
    gl.glUniform1i(sprite_texture_loc, 0);
}
