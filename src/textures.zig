const std = @import("std");
const assets = @import("assets");
const gl = @import("web/webgl.zig");

pub const Texture = struct {
    id: gl.GLuint,
    width: u16,
    height: u16,
};

var textures: [@typeInfo(assets.textures).Struct.decls.len]Texture = undefined;

pub fn load() void {
    inline for (@typeInfo(assets.textures).Struct.decls, 0..) |decl, i| {
        const data = @field(assets.textures, decl.name);
        textures[i].id = gl.jsLoadTexturePNG(data.ptr, data.len, &textures[i].width, &textures[i].height);
    }
}

pub fn findByName(name: []const u8) Texture {
    inline for (@typeInfo(assets.textures).Struct.decls, 0..) |decl, i| {
        if (std.mem.eql(u8, decl.name, name)) return textures[i];
    }
    unreachable;
}
