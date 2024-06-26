const std = @import("std");
const za = @import("zalgebra");
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Quat = za.Quat;
const gl = @import("web/webgl.zig");
const wasm = @import("web/wasm.zig");
const keys = @import("web/keys.zig");
const time = @import("time.zig");
const controls = @import("controls.zig");
const maps = @import("maps.zig");
const primitives = @import("primitives.zig");
const shaders = @import("shaders.zig");
const textures = @import("textures.zig");
const SpriteRenderer = @import("SpriteRenderer.zig");
const models = @import("models.zig");
const Target = @import("Target.zig");
const Camera = @import("Camera.zig");
const World = @import("World.zig");
const Game = @import("Game.zig");
const game = &Game.game;
pub const std_options = .{
    .log_level = .info,
    .logFn = wasm.log,
};

const logger = std.log.scoped(.main);

const allocator = std.heap.wasm_allocator;

var video_width: f32 = 1280;
var video_height: f32 = 720;
var video_scale: f32 = 1;

const State = struct {
    camera: Camera,
    player_position: Vec3,
};
var state: State = undefined;

var loaded: bool = false; // all textures are loaded

export fn onLoadImages() void {
    textures.load();

    SpriteRenderer.init(allocator);
    shaders.load();
    models.load(allocator) catch unreachable;
    primitives.load();
    maps.load(allocator) catch unreachable;
}

export fn onImagesLoaded() void {
    loaded = true;

    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glEnable(gl.GL_CULL_FACE);
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);

    textures.updateParameters();

    game.startup(allocator);

    // world.camera.position = state.camera.position;
    // world.camera.angles = state.camera.angles;
    // world.player.actor.position = state.player_position;
}

export fn onLoadSnapshot(handle: wasm.String.Handle) void {
    const string = wasm.String.get(handle);
    defer wasm.String.dealloc(handle);
    const parsed = std.json.parseFromSlice(State, allocator, string, .{ .ignore_unknown_fields = true }) catch |e| {
        logger.err("Snapshot loading failed {}", .{e});
        return;
    };
    defer parsed.deinit();
    state = parsed.value;
}

export fn onSaveSnapshot() wasm.String.Handle {
    // state.camera = game.scene.camera;
    // state.player_position = game.scene.player.actor.position;

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
}

export fn onMouseMove(dx: c_int, dy: c_int) void {
    mrx += @floatFromInt(dx);
    mry += @floatFromInt(dy);
}
var mrx: f32 = 0;
var mry: f32 = 0;

var jump_last_down = false;
var climb_last_down = false;
var dash_last_down = false;

export fn onAnimationFrame() void {
    if (!loaded) return;

    time.now = @floatCast(wasm.performanceNow() / 1000.0);
    time.delta = time.now - time.last;
    defer time.last = time.now;

    defer {
        mrx = 0;
        mry = 0;
    }

    gl.glClearColor(0, 0, 0, 1);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

    const target = Target{.width = video_width, .height = video_height};

    controls.move = Vec2.new(wasm.getAxis(0), -wasm.getAxis(1));
    if (wasm.isKeyDown(keys.KEY_W)) controls.move.data[1] += 1;
    if (wasm.isKeyDown(keys.KEY_A)) controls.move.data[0] -= 1;
    if (wasm.isKeyDown(keys.KEY_S)) controls.move.data[1] -= 1;
    if (wasm.isKeyDown(keys.KEY_D)) controls.move.data[0] += 1;
    const length = controls.move.length();
    if (length > 1) controls.move = controls.move.scale(1.0 / length);

    controls.camera = Vec2.new(wasm.getAxis(2), wasm.getAxis(3));
    if (wasm.isKeyDown(keys.KEY_LEFT)) controls.camera.data[0] -= 1;
    if (wasm.isKeyDown(keys.KEY_RIGHT)) controls.camera.data[0] += 1;
    if (wasm.isKeyDown(keys.KEY_UP)) controls.camera.data[1] += 1;
    if (wasm.isKeyDown(keys.KEY_DOWN)) controls.camera.data[1] -= 1;
    controls.camera.data[0] += 0.1 * mrx;
    controls.camera.data[1] += 0.1 * mry;

    controls.jump.down = wasm.isButtonDown(0) or wasm.isKeyDown(keys.KEY_SPACE);
    controls.climb.down = wasm.isButtonDown(1) or wasm.isKeyDown(keys.KEY_E);
    controls.dash.down = wasm.isButtonDown(2) or wasm.isKeyDown(keys.KEY_SHIFT);
    controls.jump.pressed = !jump_last_down and controls.jump.down;
    jump_last_down = controls.jump.down;
    controls.climb.pressed = !climb_last_down and controls.climb.down;
    climb_last_down = controls.climb.down;
    controls.dash.pressed = !dash_last_down and controls.dash.down;
    dash_last_down = controls.dash.down;

    game.update();

    game.draw(target);
}
