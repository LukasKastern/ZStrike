const std = @import("std");
const ecs = @import("zflecs");
const zm = @import("zmath");

const Core = @import("Core.zig");
const SystemCollection = @import("system_collection.zig");
const GuiRendererDX12 = @import("renderer/GuiRendererDX12.zig");
const Renderer = @import("renderer.zig");

pub fn SampleArray(comptime num_samples: u32) type {
    return struct {
        const Self = @This();

        sample_sequence: usize = 0,
        samples: [num_samples]f32 = [1]f32{0.0} ** num_samples,
        min: f32 = 0.0,
        max: f32 = 0.0,
        avg: f32 = 0.0,

        fn addSample(self: *Self, value: f32) void {
            var sample_idx = self.sample_sequence % num_samples;
            self.samples[sample_idx] = value;

            var avg_accumulator = value;
            var min = value;
            var max = value;

            var num_valid_samples = std.math.min(num_samples, self.sample_sequence);
            var idx: usize = 1;
            while (idx < num_valid_samples) : (idx += 1) {
                var sample_at_idx = self.samples[(idx + self.sample_sequence) % num_samples];
                avg_accumulator += sample_at_idx;
                min = std.math.min(min, sample_at_idx);
                max = std.math.max(max, sample_at_idx);
            }

            self.sample_sequence += 1;
            self.min = min;
            self.max = max;
            self.avg = avg_accumulator / @intToFloat(f32, num_valid_samples);
        }
    };
}

const GameStats = @This();

camera_query: *ecs.query_t,

frame_time: SampleArray(60) = .{},
frame_start_time_ns: i128 = 0,

pub fn collectFrameStats(it: *ecs.iter_t) callconv(.C) void {
    var game_stats = ecs.field(it, GameStats, 1).?;
    for (game_stats) |*stats| {
        var last_frame_time_ns = stats.frame_start_time_ns;
        var now_ns = std.time.nanoTimestamp();

        var elapsed_ns = now_ns - last_frame_time_ns;
        var elapsed_ms = @intToFloat(f32, elapsed_ns) / @intToFloat(f32, std.time.ns_per_ms);

        stats.frame_time.addSample(elapsed_ms);
        stats.frame_start_time_ns = now_ns;
        // std.log.info("Elapsed={}, ElapsedNs={}", .{ elapsed_ms, elapsed_ns });
    }
}

pub fn drawDebugPanel(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;
    if (ecs.get(it.world, ecs.id(world, Renderer.Renderer), Renderer.Renderer) == null) {
        return;
    }

    var game_stats = ecs.get(it.world, ecs.id(world, GameStats), GameStats).?;

    GuiRendererDX12.c.igSetNextWindowSize(
        GuiRendererDX12.c.ImVec2{ .x = 600.0, .y = 0.0 },
        GuiRendererDX12.c.ImGuiCond_FirstUseEver,
    );

    _ = GuiRendererDX12.c.igBegin(
        "Demo Settings",
        null,
        GuiRendererDX12.c.ImGuiWindowFlags_NoTitleBar |
            GuiRendererDX12.c.ImGuiWindowFlags_NoMove |
            GuiRendererDX12.c.ImGuiWindowFlags_NoBackground |
            GuiRendererDX12.c.ImGuiWindowFlags_NoResize |
            GuiRendererDX12.c.ImGuiWindowFlags_NoSavedSettings,
    );
    defer GuiRendererDX12.c.igEnd();

    _ = GuiRendererDX12.c.igText(
        "FPS: %.2f (Min=%.2f, Max=%.2f)",
        std.time.ms_per_s / game_stats.frame_time.avg,
        std.time.ms_per_s / game_stats.frame_time.max,
        std.time.ms_per_s / game_stats.frame_time.min,
    );

    // Copied from renderer_dx12.
    {
        const CameraData = struct { priority: isize, transform: zm.Mat };

        var camera_data: CameraData = .{
            .transform = zm.identity(),
            .priority = -1000,
        };
        // Find camera to use
        {
            var camera_it = ecs.query_iter(it.world, game_stats.camera_query);
            while (ecs.query_next(&camera_it)) {
                var camera_array = ecs.field(&camera_it, Renderer.Camera, 1).?;
                var transform_array = ecs.field(&camera_it, Core.Transform.LocalToWorld, 2).?;

                for (camera_array, transform_array) |camera, transform| {
                    if (camera_data.priority < camera.priority) {
                        camera_data = .{
                            .priority = camera.priority,
                            .transform = transform.value,
                        };
                    }
                }
            }
        }

        var camera_pos = zm.util.getTranslationVec(camera_data.transform);
        var camera_rot = zm.util.getRotationQuat(camera_data.transform);

        var rotation = zm.quatToRollPitchYaw(camera_rot);

        _ = GuiRendererDX12.c.igText(
            "Camera Position: (%.2f, %.2f, %.2f)",
            camera_pos[0],
            camera_pos[1],
            camera_pos[2],
        );
        _ = GuiRendererDX12.c.igText(
            "Camera Rotation: (%.2f, %.2f, %.2f)",
            rotation[0],
            rotation[1],
            rotation[2],
        );
    }
}

pub fn loadModule(world: *ecs.world_t) void {
    var camera_query_desc = ecs.query_desc_t{};
    camera_query_desc.filter.terms[0] = .{ .id = ecs.id(world, Renderer.Camera) };
    camera_query_desc.filter.terms[1] = .{ .id = ecs.id(world, Core.Transform.LocalToWorld) };

    var camera_query = ecs.query_init(world, &camera_query_desc) catch @panic("Failed to create resource upload query");

    ecs.setSingleton(
        world,
        GameStats,
        .{
            .camera_query = camera_query,
        },
    );

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(world, GameStats) };
        system_desc.callback = collectFrameStats;
        ecs.SYSTEM(world, "Collect Frame Stats", ecs.PreFrame, &system_desc);
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = drawDebugPanel;
        ecs.SYSTEM(world, "Draw Debug Panel", ecs.OnUpdate, &system_desc);
    }
}
