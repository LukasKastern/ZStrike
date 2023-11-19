const builtin = @import("builtin");
const std = @import("std");
const ecs = @import("zflecs");
const zm = @import("zmath");

const SystemCollection = @import("system_collection.zig");

const Self = @This();

pub usingnamespace switch (builtin.target.os.tag) {
    .windows => @import("application/windows_application.zig"),
    else => @compileError("Application is not supported on selected platform"),
};

pub const ApplicationError = error{
    InitializationFailed,
};

pub const CreateWindowError = error{
    NameTooLong,
    CreationFailed,
    OutOfMemory,
};

pub const WindowMode = enum {
    FullScreen,
    Minimized,
};

const HideWindowFlags = enum {
    RendererReady,
};

pub const ApplicationConfig = struct {
    name: []const u8,
};

pub const WindowHandle = struct {};

pub const WindowEvent = union(enum) {
    CloseRequested: void,
    KeyDown: struct {
        key: u8,
    },
    KeyUp: struct {
        key: u8,
    },
    MouseMove: struct {
        move_x: i32,
        move_y: i32,
    },
    FocusChanged: struct {
        has_focus: bool,
    },
};

pub const CursorMode = enum {
    Constrained,
    Locked,
    Unlocked,
};

pub const Window = struct {
    event_queue: ?*std.ArrayList(WindowEvent),
    title: []const u8,
    startup_mode: WindowMode = .FullScreen,
    has_focus: bool = false,
    cursor_mode: CursorMode = .Constrained,
    cursor_visible: bool = true,

    cursor_pos: [2]f32 = .{ 0.0, 0.0 },
    size: [2]f32 = .{ 0.0, 0.0 },
};

pub const PlatformInput = struct {
    pressed_keys: std.StaticBitSet(256),
    last_frame_pressed_keys: std.StaticBitSet(256),

    // First two components store the position.
    // The latter two contain the delta movement since the previous frame.
    mouse_pos: zm.F32x4,
    is_mouse_pos_initialized: bool = false,

    has_focus: bool,

    pub fn init() PlatformInput {
        return .{
            .pressed_keys = std.StaticBitSet(256).initEmpty(),
            .last_frame_pressed_keys = std.StaticBitSet(256).initEmpty(),
            .mouse_pos = zm.f32x4s(0.0),
            .has_focus = false,
        };
    }

    pub fn isKeyPressed(self: PlatformInput, key: Self.PlatformKeyCodes) bool {
        return self.pressed_keys.isSet(@intFromEnum(key));
    }

    pub fn isKeyPressedThisFrame(self: PlatformInput, key: Self.PlatformKeyCodes) bool {
        return !self.last_frame_pressed_keys.isSet(@intFromEnum(key)) and self.pressed_keys.isSet(@intFromEnum(key));
    }
};

fn assertHasDecl(comptime T: anytype, comptime name: []const u8) void {
    if (!@hasDecl(T, name)) @compileError("Application missing declaration: " ++ name);
}

pub fn initializeModule(world: *ecs.world_t) void {
    @This().initializePlatformModule(world);
}

pub fn preInitializeModule(world: *ecs.world_t) void {
    ecs.COMPONENT(world, PlatformInput);
    ecs.COMPONENT(world, ApplicationConfig);
    ecs.COMPONENT(world, Window);

    ecs.setSingleton(world, ApplicationConfig, .{
        .name = "default",
    });

    ecs.setSingleton(world, PlatformInput, PlatformInput.init());
    @This().preInitializePlatformModule(world);
}
