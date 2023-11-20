const Engine = @import("Engine");
const Core = Engine.Core;
const ecs = Engine.ecs;

const std = @import("std");
const enet = @import("enet");

pub const ConnectionComponent = struct {
    _: u8,
};

pub const State = enum {
    Invalid,
    Connecting,
    Connected,
    InGame,
};

pub const Host = struct {
    value: *enet.Host,
    port: u16,
    max_connections: usize,
};

var is_enet_initialized: bool = false;

pub fn bind(
    world: *ecs.world_t,
    options: struct {
        port: u16,
        max_connections: usize,
    },
) !ecs.entity_t {
    if (!is_enet_initialized) {
        is_enet_initialized = true;
        enet.initialize();
    }

    var address = enet.Address{
        .host = enet.HOST_ANY,
        .port = options.port,
    };

    var host = try enet.Host.create(address, options.max_connections, 0, 0, 0);

    var host_entity = ecs.new_entity(world, "Host");
    _ = ecs.set(
        world,
        host_entity,
        Host,
        .{ .value = host, .port = options.port, .max_connections = options.max_connections },
    );

    return host_entity;
}

pub fn connect(address: std.net.Address, world: *ecs.world_t) void {
    if (!is_enet_initialized) {
        is_enet_initialized = true;
        enet.initialize();
    }

    _ = world;
    _ = address;
}

pub fn init(world: *ecs.world_t) void {
    ecs.COMPONENT(world, State);
    ecs.COMPONENT(world, ConnectionComponent);
    ecs.COMPONENT(world, Host);
}
