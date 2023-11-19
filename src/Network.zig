const Engine = @import("Engine");
const Core = Engine.Core;
const ecs = Engine.ecs;

pub const ConnectionComponent = struct {
    _: u8,
};

pub const State = enum {
    Invalid,
    Connecting,
    Connected,
    InGame,
};

pub fn init(world: *ecs.world_t) void {
    ecs.COMPONENT(world, State);
    ecs.COMPONENT(world, ConnectionComponent);
}
