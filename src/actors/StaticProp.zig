const Actor = @import("Actor.zig");
const Model = @import("../Model.zig");
const ShaderInfo = Model.ShaderInfo;

const StaticProp = @This();

actor: Actor,
model: *Model,

pub fn draw(actor: *Actor, si: ShaderInfo) void {
    const static_prop = @fieldParentPtr(StaticProp, "actor", actor);
    static_prop.model.draw(si, actor.getTransform());
}
