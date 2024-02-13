const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Quat = za.Quat;
const gl = @import("web/webgl.zig");
const wasm = @import("web/wasm.zig");
const keys = @import("web/keys.zig");
const textures = @import("textures.zig");
const models = @import("models.zig");
const Camera = @import("Camera.zig");
const World = @import("World.zig");
const world = &World.world;
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
    camera: Camera = .{
        .position = Vec3.new(0, -800, 200),
    },
};
var state: State = .{};

var loaded: bool = false; // all textures are loaded

export fn onLoadImages() void {
    textures.load();
    models.load(allocator) catch unreachable;
}

export fn onImagesLoaded() void {
    loaded = true;

    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glEnable(gl.GL_CULL_FACE);

    textures.updateParameters();

    World.loadShaders();
    world.load(allocator, "1") catch unreachable;
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

export fn onMouseMove(x: c_int, y: c_int) void {
    const dx: f32 = @floatFromInt(x);
    const dy: f32 = @floatFromInt(y);
    mrx += -0.25 * dy;
    mry += 0.25 * dx;
}
var mrx: f32 = 0;
var mry: f32 = 0;

export fn onAnimationFrame() void {
    if (!loaded) return;

    gl.glClearColor(0, 0, 0, 1);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

    state.camera.rotateView(mrx, mry);
    mrx = 0;
    mry = 0;
    if (false) {
        state.camera.handleKeys();
        state.camera.inspect();
    }

    state.camera.rotateView(-2 * wasm.getAxis(3), 2 * wasm.getAxis(2));
    const x = Quat.fromAxis(state.camera.angles.x(), Vec3.new(1, 0, 0));
    const y = Quat.fromAxis(state.camera.angles.y(), Vec3.new(0, 0, -1));
    const orientation = y.mul(x);
    const cam_forward = orientation.rotateVec(Vec3.new(0, 1, 0));
    var move = Vec3.new(wasm.getAxis(0), -wasm.getAxis(1), 0);
    if (wasm.isKeyDown(keys.KEY_W)) move.data[1] += 1;
    if (wasm.isKeyDown(keys.KEY_A)) move.data[0] -= 1;
    if (wasm.isKeyDown(keys.KEY_S)) move.data[1] -= 1;
    if (wasm.isKeyDown(keys.KEY_D)) move.data[0] += 1;
    const length = move.length();
    if (length > 0.1) {
        if (length > 1) move = move.scale(1.0 / length);
        const cam_move = y.rotateVec(move);
        const radians = std.math.atan2(cam_move.x(), -cam_move.y());
        world.player.actor.angle = std.math.radiansToDegrees(f32, radians);
        world.player.velocity = cam_move.scale(5 * 60.0);
        world.player.skinned_model.play("Run");
    } else {
        world.player.velocity = Vec3.zero();
        world.player.skinned_model.play("Idle");
    }

    // debug
    if (wasm.isKeyDown(keys.KEY_Q)) world.player.velocity.data[2] -= 300;
    if (wasm.isKeyDown(keys.KEY_E)) world.player.velocity.data[2] += 300;

    // TODO: compute delta time
    world.update(1.0 / 60.0);

    state.camera.position = world.player.actor.position.add(cam_forward.scale(-300));

    world.draw(state.camera);
}
