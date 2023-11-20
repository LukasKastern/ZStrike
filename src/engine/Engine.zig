pub const Core = @import("Core.zig");
pub const Renderer = @import("renderer.zig");
pub const Application = @import("application.zig");
pub const Physics = @import("Physics.zig");

pub const ecs = @import("zflecs");
pub const zm = @import("zmath");
pub const zmesh = @import("zmesh");
const FreeLookCamera = @import("dev/FreeLookCamera.zig");

const SystemCollection = Core.SystemCollection;

const std = @import("std");

pub const EngineConfig = struct {
    window_name: []const u8 = "My Game",
    with_developer_content: bool = false,
    world_type: SystemCollection.WorldType,
};

const Self = @This();

world: *ecs.world_t,
engine_config: EngineConfig,
allocator: std.mem.Allocator,
window: ecs.entity_t,

pub fn init(allocator: std.mem.Allocator, comptime config: EngineConfig) !Self {
    var world = ecs.init();

    ecs.os.ecs_os_api.log_ = nativeLogCallback;
    ecs.os.ecs_os_api.abort_ = nativeAbort;
    zmesh.init(allocator);

    try SystemCollection.populateSystem(allocator, world, config.world_type);

    var window = ecs.new_entity(world, "Main Window");

    if (config.world_type == .Client) {
        _ = ecs.set(world, window, Application.Window, .{
            .event_queue = null,
            .title = config.window_name,
            .startup_mode = .FullScreen,
        });

        if (config.with_developer_content) {
            FreeLookCamera.init(world);
        }
    }

    return .{
        .window = window,
        .allocator = allocator,
        .world = world,
        .engine_config = config,
    };
}

pub fn deinit(self: Self) void {
    ecs.delete(self.world, self.window);

    SystemCollection.deinit(self.world);

    zmesh.deinit();
    _ = ecs.fini(self.world);
}

pub fn tick(self: Self) !void {
    _ = ecs.progress(self.world, 0.0);

    var quit_app_maybe = ecs.get(self.world, ecs.id(self.world, Core.QuitApplication), Core.QuitApplication);

    if (quit_app_maybe) |quit_app| {
        std.log.info("[Engine] Exit Requested. Reason: {s}", .{quit_app.reason});
        return error.ExitRequested;
    }
}

fn nativeLogCallback(level: c_int, file: [*:0]const u8, line: c_int, message: [*:0]const u8) callconv(.C) void {
    _ = level;
    _ = file;
    _ = line;

    std.log.info("{s}", .{std.mem.span(message)});
}

fn nativeAbort() callconv(.C) void {
    std.debug.dumpCurrentStackTrace(@returnAddress());
    std.os.exit(1);
}

test "Engine should initialize and shutdown" {
    var engine = try Self.init(std.testing.allocator, .{});
    defer engine.deinit();

    while (true) {
        engine.tick() catch |e| switch (e) {
            error.ExitRequested => {
                break;
            },
        };

        _ = ecs.set(
            engine.world,
            ecs.id(engine.world, Core.QuitApplication),
            Core.QuitApplication,
            .{
                .reason = "Test",
            },
        );
    }
}
