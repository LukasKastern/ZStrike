const std = @import("std");

const ecs = @import("zflecs");
const application = @import("application.zig");
const ProcessWindowEvents = @import("ProcessWindowEvents.zig");
const Renderer = @import("Renderer.zig");

const GameStats = @import("GameStats.zig");

pub const WorldConfig = enum { Server, Client };

const Core = @import("Core.zig");

const Modules = [_]type{
    Core,
    @import("Physics.zig"),
    @import("renderer.zig"),
    @import("application.zig"),
    @import("input/Input.zig"),
};

pub fn populateSystem(allocator: std.mem.Allocator, world: *ecs.world_t, config: WorldConfig) !void {
    try Core.initializeAllocators(world, allocator);

    inline for (Modules) |module| {
        if (!@hasDecl(module, "preInitializeModule")) {
            @compileError(@typeName(module) ++ " missing declaration " ++ "preInitializeModule");
        }

        module.preInitializeModule(world);
    }

    inline for (Modules) |module| {
        if (!@hasDecl(module, "initializeModule")) {
            @compileError(@typeName(module) ++ "missing declaration " ++ "initializeModule");
        }

        module.initializeModule(world);
    }

    GameStats.loadModule(world);
    ProcessWindowEvents.loadModule(world);
    // _ = world;
    _ = config;
}

pub fn deinit(world: *ecs.world_t) void {
    inline for (Modules) |module| {
        if (@hasDecl(module, "deinitModule")) {
            module.deinitModule(world);
        }
    }
}
