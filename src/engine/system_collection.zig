const std = @import("std");

const ecs = @import("zflecs");
const application = @import("application.zig");
const ProcessWindowEvents = @import("ProcessWindowEvents.zig");
const Renderer = @import("renderer.zig");

const GameStats = @import("GameStats.zig");

pub const WorldType = enum { Server, Client };

const Core = @import("Core.zig");

const Modules = [_]type{
    Core,
    @import("Physics.zig"),
};

const ClientModules = [_]type{
    @import("renderer.zig"),
    @import("application.zig"),
    @import("input/Input.zig"),
};

pub fn populateSystem(allocator: std.mem.Allocator, world: *ecs.world_t, comptime config: WorldType) !void {
    try Core.initializeAllocators(world, config, allocator);

    const all_modules = if (config == .Client) Modules ++ ClientModules else Modules;

    inline for (all_modules) |module| {
        if (!@hasDecl(module, "preInitializeModule")) {
            @compileError(@typeName(module) ++ " missing declaration " ++ "preInitializeModule");
        }

        module.preInitializeModule(world);
    }

    inline for (all_modules) |module| {
        if (!@hasDecl(module, "initializeModule")) {
            @compileError(@typeName(module) ++ "missing declaration " ++ "initializeModule");
        }

        module.initializeModule(world);
    }

    if (config == .Client) {
        GameStats.loadModule(world);
        ProcessWindowEvents.loadModule(world);
    }
}

pub fn deinit(world: *ecs.world_t) void {
    inline for (Modules) |module| {
        if (@hasDecl(module, "deinitModule")) {
            module.deinitModule(world);
        }
    }
}
