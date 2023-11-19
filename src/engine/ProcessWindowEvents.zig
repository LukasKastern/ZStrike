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

    var main_win: ?Application.Window = null;

    for (window_array) |*window| {
        if (window.has_focus or main_win == null) {
            main_win = window.*;
        }

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
                        platform_input.pressed_keys.unset(@intFromEnum(key_event.key));
                    },
                    .KeyDown => |key_event| {
                        std.log.info("Down: {}", .{key_event.key});
                        platform_input.pressed_keys.set(@intFromEnum(key_event.key));
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

    if (main_win) |win| {
        passInputToGUI(it.world, win);
    }
}

// This function tells imgui about the current input state.
fn passInputToGUI(world: *ecs.world_t, win: Application.Window) void {
    var platform_input = ecs.get_mut(world, ecs.id(world, Application.PlatformInput), Application.PlatformInput).?;

    var mouse_x = win.cursor_pos[0];
    var mouse_y = win.cursor_pos[1];

    const io = GuiRendererDX12.c.igGetIO();
    GuiRendererDX12.c.ImGuiIO_AddMousePosEvent(io, mouse_x, mouse_y);

    // std.log.info("Mouse: {d:.1}x{d:.1}", .{ mouse_x, mouse_y });

    const pressed_set = platform_input.pressed_keys;
    const last_frame_set = platform_input.last_frame_pressed_keys;

    // Xor the current keys with the last frame to find all keys that changed state since last tick.
    const changed = pressed_set.xorWith(last_frame_set);

    var changed_iterator = changed.iterator(.{ .kind = .set });
    while (changed_iterator.next()) |changed_key| {
        const is_pressed = pressed_set.isSet(changed_key);
        const changed_platform_key: Application.PlatformKeyCodes = @enumFromInt(changed_key);

        const imgui_mouse_button_maybe = blk: {
            switch (changed_platform_key) {
                .LButton => {
                    break :blk GuiRendererDX12.c.ImGuiMouseButton_Left;
                },
                .RButton => {
                    break :blk GuiRendererDX12.c.ImGuiMouseButton_Right;
                },
                else => {
                    break :blk null;
                },
            }
        };

        if (imgui_mouse_button_maybe) |mouse_button| {
            GuiRendererDX12.c.ImGuiIO_AddMouseButtonEvent(io, mouse_button, is_pressed);
        }

        //TODO: Implement other keys as needed (lukas)
    }
}

pub fn loadModule(world: *ecs.world_t) void {
    {
        var system_desc = ecs.system_desc_t{};
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(world, Application.Window) };
        system_desc.callback = processWindowEvents;
        ecs.SYSTEM(world, "Process Window Events", ecs.OnUpdate, &system_desc);
    }
}
