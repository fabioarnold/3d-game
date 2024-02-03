const wasm = @import("web/wasm.zig");
const za = @import("zalgebra");
const Vec3 = za.Vec3;

pub fn float(name: []const u8, val: *f32) void {
    wasm.inspectFloat(name.ptr, name.len, val);
}

pub fn floatRange(name: []const u8, val: *f32, min: f32, max: f32) void {
    wasm.inspectFloatRange(name.ptr, name.len, val, min, max);
}

pub fn vec3(name: []const u8, val: *Vec3) void {
    wasm.inspectVec3(name.ptr, name.len, &val.data[0]);
}