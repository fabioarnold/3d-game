const std = @import("std");
const za = @import("zalgebra");
const gl = @import("../web/webgl.zig");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const Plane = @import("../math.zig").Plane;
const ShaderInfo = @import("../Model.zig").ShaderInfo;
const Map = @import("../Map.zig");
const Actor = @import("Actor.zig");
const World = @import("../World.zig");

pub const Solid = @This();

pub const Face = struct {
    plane: Plane,
    vertex_start: usize,
    vertex_count: usize,
};

actor: Actor,
collidable: bool = true,
model: Map.Model,
vertices: std.ArrayList(Vec3),
faces: std.ArrayList(Face),

pub const vtable = Actor.Interface.VTable{
// TODO: connect to Actor
    // .deinit = deinit,
    .draw = draw,
};

pub fn create(world: *World) !*Solid {
    const solid = try world.allocator.create(Solid);
    solid.* = .{
        .actor = .{ .world = world },
        .model = undefined,
        .vertices = undefined,
        .faces = undefined,
    };
    return solid;
}

pub fn deinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *Solid = @alignCast(@ptrCast(ptr));
    self.vertices.deinit();
    self.faces.deinit();
    allocator.destroy(self);
}

pub fn moveTo(self: *Solid, target: Vec3) void {
    const delta = target.sub(self.actor.position);

    // if (self.collidable) {
    //     if (delta.length_squared() > 0.001) {
    //         for (world.all("i_ride_platforms")) |actor| {
    //             if (actor == self)
    //                 continue;

    //             if (rider.riding_platform_check(this)) {
    //                 collidable = false;
    //                 rider.riding_platform_set_velocity(velocity);
    //                 rider.riding_platform_moved(delta);
    //                 collidable = true;
    //             }
    //         }

    //         position += delta;
    //     }
    // } else {
    self.actor.position = self.actor.position.add(delta);
    // }
}

pub fn draw(ptr: *anyopaque, si: ShaderInfo) void {
    const self: *Solid = @alignCast(@ptrCast(ptr));
    const model_mat = Mat4.fromTranslate(self.actor.position);
    gl.glUniformMatrix4fv(si.model_loc, 1, gl.GL_FALSE, &model_mat.data[0]);
    self.model.draw();
}
