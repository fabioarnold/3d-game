const std = @import("std");
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const gl = @import("../web/webgl.zig");
const time = @import("../time.zig");
const controls = @import("../controls.zig");
const easings = @import("../easings.zig");
const math = @import("../math.zig");
const shaders = @import("../shaders.zig");
const models = @import("../models.zig");
const Model = @import("../Model.zig");
const World = @import("../World.zig");
const Target = @import("../Target.zig");
const Camera = @import("../Camera.zig");
const Game = @import("../Game.zig");

const Titlescreen = @This();

const game = &Game.game;

allocator: std.mem.Allocator,
// batch: Batch,
model: *Model,
easing: f32 = 0,
input_delay: f32 = 5.0,
wobble: Vec2 = Vec2.zero(),

pub fn create(allocator: std.mem.Allocator) !*Titlescreen {
    const self = try allocator.create(Titlescreen);
    self.* = .{
        .allocator = allocator,
        .model = models.findByName("logo"),
        // music = "event:/music/mus_title";
    };
    return self;
}

pub fn deinit(self: *Titlescreen) void {
    self.allocator.destroy(self);
    self.* = undefined;
}

pub fn update(self: *Titlescreen) void {
    self.easing = math.approach(self.easing, 1, time.delta / 5.0);
    self.input_delay = math.approach(self.input_delay, 0, time.delta);

    if (controls.confirm.pressed and !game.isMidTransition()) {
        // audio.play(sfx.main_menu_first_input);
        // game.goto(.{
        //     .mode = .replace,
        //     .scene = Overworld(false),
        //     .to_black = angled_wipe(),
        //     .to_pause = true,
        // });

        const world = World.create(self.allocator, .{
            .map = "1",
            .checkpoint = "",
            .submap = false,
            .reason = .entered,
        }) catch unreachable;
        game.goto(.{
            .mode = .replace,
            .scene = .{ .world = world },
            .to_black = Game.ScreenWipe.init(.angled),
        });
    }

    // if (controls.cancel.pressed) {
    //     app.exit();
    // }
}

pub fn draw(self: *Titlescreen, target: Target) void { // , target: Target
    // target.clear(color.black, 1, 0, clear_mask.all);

    const cam_from = Vec3.new(0, -200, 60);
    const cam_to = Vec3.new(0, -80, 50);

    // wobble += (controls.camera.value - wobble) * (1 - math_f.pow(0.1, time.delta));

    var camera = Camera{
        .aspect_ratio = target.width / target.height,
        .position = Vec3.lerp(cam_from, cam_to, easings.outCubic(self.easing)),
        .look_at = Vec3.new(0, 0, 70),
        .near_plane = 10,
        .far_plane = 300,
    };

    // var state = render_state(){
    //     .camera = camera,
    //     .model_matrix = matrix.identity *
    //         matrix.create_scale(10) *
    //         matrix.create_rotation_x(wobble.y) *
    //         matrix.create_rotation_z(wobble.x) *
    //         matrix.create_translation(0, 0, 53) *
    //         matrix.create_rotation_z(-(1.0f - easings.outCubic(easing)) * 10),
    //     .silhouette = false,
    //     .sun_direction = -vec3.unit_z,
    //     .vertical_fog_color = color.white,
    //     .depth_compare = depth_compare.less,
    //     .depth_mask = true,
    //     .cutout_mode = false,
    // };
    const angle_z = -(1 - easings.outCubic(self.easing)) * std.math.radiansToDegrees(f32, 10);
    const model_mat = Mat4.fromRotation(angle_z, Vec3.new(0, 0, 1))
        .mul(Mat4.fromTranslate(Vec3.new(0, 0, 53)))
        .mul(Mat4.fromScale(Vec3.new(10, 10, 10)));

    const view_projection = camera.projection().mul(camera.view());
    gl.glUseProgram(shaders.textured_skinned.shader);
    gl.glUniformMatrix4fv(shaders.textured_skinned.viewprojection_loc, 1, gl.GL_FALSE, &view_projection.data[0]);
    const si = Model.ShaderInfo{
        .model_loc = shaders.textured_skinned.model_loc,
        .joints_loc = shaders.textured_skinned.joints_loc,
        .blend_skin_loc = shaders.textured_skinned.blend_skin_loc,
        .color_loc = shaders.textured_skinned.color_loc,
        .effects_loc = shaders.textured_skinned.effects_loc,
    };
    self.model.draw(si, model_mat);

    // overlay
    // if (false) {
    //     batch.set_sampler(texture_sampler(texture_filter.linear, texture_wrap.clamp_to_edge, texture_wrap.clamp_to_edge));
    //     var bounds = rect(0, 0, target.width, target.height);
    //     var scroll = -vec2(1.25f, 0.9f) * (float)(time.duration.total_seconds) * 0.05f;

    //     batch.push_blend(blend_mode.add);
    //     batch.push_sampler(texture_sampler(texture_filter.linear, texture_wrap.repeat, texture_wrap.repeat));
    //     batch.image(assets.textures["overworld/overlay"], bounds.top_left, bounds.top_right, bounds.bottom_right, bounds.bottom_left, scroll + vec2(0, 0), scroll + vec2(1, 0), scroll + vec2(1, 1), scroll + vec2(0, 1), color.white * 0.10f);
    //     batch.pop_sampler();
    //     batch.pop_blend();
    //     batch.image(assets.textures["overworld/vignette"], bounds.top_left, bounds.top_right, bounds.bottom_right, bounds.bottom_left, vec2(0, 0), vec2(1, 0), vec2(1, 1), vec2(0, 1), color.white * 0.30f);

    //     if (input_delay <= 0) {
    //         var at = bounds.bottom_right + vec2(-16, -4) * game.relative_scale + vec2(0, -ui.prompt_size);
    //         ui.prompt(batch, controls.cancel, loc.str("exit"), at, width, 1.0f);
    //         at.x -= width + 8 * game.relative_scale;
    //         ui.prompt(batch, controls.confirm, loc.str("confirm"), at, {}, 1.0);
    //         ui.text(batch, game.version_string, bounds.bottom_left + vec2(4, -4) * game.relative_scale, vec2(0, 1), color.white * 0.25f);
    //     }

    //     if (easing < 1) {
    //         batch.push_blend(blend_mode.subtract);
    //         batch.rect(bounds, color.white * (1 - ease.cube.out(easing)));
    //         batch.pop_blend();
    //     }

    //     batch.render(target);
    //     batch.clear();
    // }
}
