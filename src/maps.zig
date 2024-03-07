const std = @import("std");
const assets = @import("assets");
const Map = @import("Map.zig");

var maps: [@typeInfo(assets.maps).Struct.decls.len]Map = undefined;

pub fn load(allocator: std.mem.Allocator) !void {
    inline for (@typeInfo(assets.maps).Struct.decls, 0..) |decl, i| {
        const data = @field(assets.maps, decl.name);
        maps[i] = try Map.init(allocator, decl.name, data);
    }
}

pub fn findByName(name: []const u8) Map {
    inline for (@typeInfo(assets.maps).Struct.decls, 0..) |decl, i| {
        if (std.mem.eql(u8, decl.name, name)) return maps[i];
    }
    unreachable;
}