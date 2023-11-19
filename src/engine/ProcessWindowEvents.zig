const std = @import("std");

const ecs = @import("zflecs");
const zm = @import("zmath");

const QuitApplication = @import("Core.zig").QuitApplication;
const Application = @import("application.zig");

const Renderer = @import("renderer.zig");
const GuiRendererDX12 = Renderer.GuiRendererDX12;

fn processWindowEvents(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;
    var platform_input = ecs.get_mut(it.world, ecs.id(world, Application.PlatformInput), Application.PlatformInput).?;

    const window_array = ecs.field(it, Application.Window, 1).?;

    platform_input.last_frame_pressed_keys = platform_input.pressed_keys;

    // Reset mouse delta movement.
    platform_input.mouse_pos[2] = 0.0;
    platform_input.mouse_pos[3] = 0.0;

    for (window_array) |*window| {
        if (window.event_queue) |event_queue| {
            for (event_queue.items) |event| {
                switch (event) {
                    .CloseRequested => {
                        _ = ecs.set(
                            it.world,
                            ecs.id(world, QuitApplication),
                            QuitApplication,
                            .{
                                .reason = "Window Closed",
                            },
                        );
                    },
                    .KeyUp => |key_event| {
                        platform_input.pressed_keys.unset(key_event.key);
                    },
                    .KeyDown => |key_event| {
                        platform_input.pressed_keys.set(key_event.key);
                    },
                    .MouseMove => |move_event| {
                        platform_input.mouse_pos[0] += @as(f32, @floatFromInt(move_event.move_x));
                        platform_input.mouse_pos[1] += @as(f32, @floatFromInt(move_event.move_y));
                        platform_input.mouse_pos[2] += @as(f32, @floatFromInt(move_event.move_x));
                        platform_input.mouse_pos[3] += @as(f32, @floatFromInt(move_event.move_y));
                    },
                    .FocusChanged => |focus_changed| {
                        platform_input.has_focus = focus_changed.has_focus;
                        window.has_focus = focus_changed.has_focus;
                    },
                }
            }

            event_queue.clearRetainingCapacity();
        }
    }
}

fn passInputToGUI(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;
    var platform_input = ecs.get_mut(it.world, ecs.id(world, Application.PlatformInput), Application.PlatformInput).?;

    var mouse_x = platform_input.mouse_pos[0];
    var mouse_y = platform_input.mouse_pos[1];

    const io = GuiRendererDX12.c.igGetIO();
    GuiRendererDX12.c.ImGuiIO_AddMousePosEvent(io, mouse_x, mouse_y);
    std.log.info("Cusor Pos:  {}", .{ mouse_x, mouse_y });
}

pub fn loadModule(world: *ecs.world_t) void {
    {
        var system_desc = ecs.system_desc_t{};
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(world, Application.Window) };
        system_desc.callback = processWindowEvents;
        ecs.SYSTEM(world, "Process Window Events", ecs.OnUpdate, &system_desc);
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = passInputToGUI;
        ecs.SYSTEM(world, "Forward Input To GUI", ecs.OnUpdate, &system_desc);
    }
}
