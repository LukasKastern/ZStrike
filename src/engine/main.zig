const std = @import("std");
// const Window = @import("window.zig").Window;
const Application = @import("application.zig");
const Renderer = @import("renderer.zig");
const ecs = @import("zflecs");

const Input = @import("input/Input.zig");
const SystemCollection = @import("system_collection.zig");
const QuitApplication = @import("QuitApplication.zig");
const zmesh = @import("zmesh");
const zm = @import("zmath");
const Core = @import("core.zig");
const PingPongEntity = @import("PingPongEntity.zig");

const DefaultMap = @import("DefaultMap.zig");

const GameStats = @import("GameStats.zig");

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

pub fn main() !void {
    ecs.os.ecs_os_api.log_ = nativeLogCallback;

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 16 }){};
    defer _ = general_purpose_allocator.deinit();

    const gpa = general_purpose_allocator.allocator();

    zmesh.init(gpa);
    defer zmesh.deinit();

    const world = ecs.init();
    defer _ = ecs.fini(world);

    ecs.os.ecs_os_api.abort_ = nativeAbort;

    try SystemCollection.populateSystem(gpa, world, .Client);
    defer SystemCollection.deinit(world);

    var window = ecs.new_entity(world, "Main Window");
    defer ecs.delete(world, window);

    _ = ecs.set(world, window, Application.Window, .{
        .event_queue = null,
        .title = "Main Window",
        .startup_mode = .FullScreen,
    });

    var player = ecs.new_entity(world, "Player");
    defer ecs.delete(world, player);

    _ = ecs.set(world, player, Input.ClientInput, .{
        .move_x = 0.0,
        .move_y = 0.0,
    });

    FreeLookCamera.init(world);

    var player_model = Core.AssetImporting.loadAsset(world, "assets/prototype/military_RTS_character.glb");
    defer ecs.delete(world, player_model);

    var player_model_texture = Core.AssetImporting.loadAsset(world, "assets/prototype/textures/soldier1_diff.dds");
    defer ecs.delete(world, player_model_texture);

    var pbr_shader = Core.AssetImporting.loadAsset(world, "assets/shaders/mesh_pbr.shader");
    defer ecs.delete(world, pbr_shader);

    {
        _ = ecs.set(world, player, Renderer.RenderTransform, zm.transpose(zm.mul(
            zm.mul(
                zm.mul(
                    zm.rotationZ(std.math.degreesToRadians(f32, 90)),
                    zm.rotationX(std.math.degreesToRadians(f32, -90)),
                ),
                zm.scaling(5, 5, 5),
            ),
            zm.translation(0.0, 2.0, 0.0),
        )));

        ecs.add_pair(world, player, ecs.id(Renderer.RenderMeshRef), player_model);
        _ = ecs.set(world, player, Renderer.Material, .{
            .textures = .{
                .base_color = player_model_texture,
            },
        });

        ecs.add_pair(world, player, ecs.id(Renderer.ShaderRef), pbr_shader);
    }

    DefaultMap.SpawnEntites(world);

    while (true) {
        _ = ecs.progress(world, 0.0);

        var quit_app_maybe = ecs.get(
            world,
            ecs.id(QuitApplication),
            QuitApplication,
        );

        if (quit_app_maybe) |quit_app| {
            std.log.info("Quitting Application, Reason={s}", .{quit_app.reason});
            break;
        }
    }
}

// fn allocMemAligned(size: i32) callconv(.C) ?*anyopaque {
//     var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};

//     const gpa = general_purpose_allocator.allocator();

//     var mem = gpa.alignedAlloc(u8, 128, @intCast(usize, size)) catch @panic("OOM");
//     return mem.ptr;
// }

// fn realloc(old: ?*anyopaque, size: i32) callconv(.C) ?*anyopaque {
//     _ = old;
//     return allocMemAligned(size);
// }

// fn allocFree(val: ?*anyopaque) callconv(.C) void {
//     _ = val;
// }

// test "zlecs aligngment" {
//     const State = struct { byte_array: [816]u8 align(16) };

//     // ecs.os.ecs_os_api.malloc_ = allocMemAligned;
//     // ecs.os.ecs_os_api.realloc_ = realloc;
//     // ecs.os.ecs_os_api.free_ = allocFree;

//     const world = ecs.init();
//     defer _ = ecs.fini(world);

//     var ent = ecs.new_entity(world, "Test");

//     ecs.COMPONENT(world, State);

//     _ = ecs.set(world, ent, State, undefined);

//     var component = ecs.get(world, ent, State).?;
//     _ = component;
// }

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test {
    // std.testing.refAllDecls(@import("application.zig"));
    // std.testing.refAllDecls(@import("renderer.zig"));

    std.testing.refAllDecls(@import("Core.zig"));
}
