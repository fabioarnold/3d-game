const std = @import("std");
const za = @import("zalgebra");
const gl = @import("../web/webgl.zig");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const Plane = @import("../math.zig").Plane;
const ShaderInfo = @import("../Model.zig").ShaderInfo;
const Map = @import("../Map.zig");
const Actor = @import("Actor.zig");

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

pub fn deinit(actor: *Actor) void {
    const self = @fieldParentPtr(Solid, "actor", actor);
    self.vertices.deinit();
    self.faces.deinit();
}

pub fn draw(actor: *Actor, si: ShaderInfo) void {
    const self = @fieldParentPtr(Solid, "actor", actor);
    const model_mat = Mat4.fromTranslate(actor.position);
    gl.glUniformMatrix4fv(si.model_loc, 1, gl.GL_FALSE, &model_mat.data[0]);
    self.model.draw();
}
