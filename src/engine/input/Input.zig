const std = @import("std");
const ecs = @import("zflecs");
const zm = @import("zmath");

pub const ClientInput = @import("ClientInput.zig");
const Application = @import("../application.zig");
const Renderer = @import("../renderer.zig");

fn sampleClientInput(it: *ecs.iter_t) callconv(.C) void {
    _ = it;
}

pub fn preInitializeModule(world: *ecs.world_t) void {
    ecs.COMPONENT(world, ClientInput);
}

pub fn initializeModule(world: *ecs.world_t) void {
    {
        var system_desc = ecs.system_desc_t{};
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(world, ClientInput) };
        system_desc.callback = sampleClientInput;
        ecs.SYSTEM(world, "Sample Client Input", ecs.PostFrame, &system_desc);
    }
}
