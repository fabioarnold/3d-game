const std = @import("std");
const assets = @import("assets");
const Model = @import("Model.zig");
const logger = std.log.scoped(.models);

var models: [@typeInfo(assets.models).Struct.decls.len]Model = undefined;

pub fn load(allocator: std.mem.Allocator) !void {
    inline for (@typeInfo(assets.models).Struct.decls, 0..) |decl, i| {
        const data = @field(assets.models, decl.name);
        // FIXME @embedFile isn't aligned https://github.com/ziglang/zig/issues/4680
        const aligned_data = try allocator.alignedAlloc(u8, 4, data.len);
        @memcpy(aligned_data, data);
        // defer allocator.free(aligned_data); // TODO: we can free if we load the animation data
        try models[i].load(allocator, aligned_data);
    }
}

pub fn findByName(name: []const u8) *Model {
    inline for (@typeInfo(assets.models).Struct.decls, 0..) |decl, i| {
        if (std.mem.eql(u8, decl.name, name)) return &models[i];
    }
    unreachable;
}
