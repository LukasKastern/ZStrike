const std = @import("std");
const ecs = @import("zflecs");
const zm = @import("zmath");

const Core = @import("../Core.zig");
const Application = @import("../application.zig");
const Renderer = @import("../renderer.zig");

const Self = @This();
const CameraPriority = 1000;

movement_speed: f32 = 1.0,
boost_factor: f32 = 2.0,

yaw_rotation_speed: f32 = 0.5,
pitch_rotation_speed: f32 = 0.5,

yaw: f32 = 0,
pitch: f32 = 0,

fn updateFreeLookCamera(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;
    var platform_input = ecs.get(it.world, ecs.id(world, Application.PlatformInput), Application.PlatformInput).?;

    if (!platform_input.has_focus) {
        return;
    }

    var entity_array = ecs.field(it, ecs.entity_t, 0).?;
    var free_look_camera_array = ecs.field(it, Self, 1).?;
    var position_array = ecs.field(it, Core.Transform.Position, 2).?;
    var rotation_array = ecs.field(it, Core.Transform.Rotation, 3).?;

    var delta_time = it.delta_time;

    for (entity_array, free_look_camera_array, position_array, rotation_array) |entity, *free_look_cam, *position, *rotation| {
        var movement_input = zm.f32x4(0.0, 0.0, 0.0, 0.0);

        var movement_base_speed = delta_time * free_look_cam.movement_speed;

        if (platform_input.isKeyPressed(Application.PlatformKeyCodes.W)) {
            movement_input[2] += 1;
        }
        if (platform_input.isKeyPressed(Application.PlatformKeyCodes.S)) {
            movement_input[2] -= 1;
        }
        if (platform_input.isKeyPressed(Application.PlatformKeyCodes.D)) {
            movement_input[0] += 1;
        }
        if (platform_input.isKeyPressed(Application.PlatformKeyCodes.A)) {
            movement_input[0] -= 1;
        }
        if (platform_input.isKeyPressed(Application.PlatformKeyCodes.Q)) {
            movement_input[1] -= 1;
        }
        if (platform_input.isKeyPressed(Application.PlatformKeyCodes.E)) {
            movement_input[1] += 1;
        }
        if (platform_input.isKeyPressed(Application.PlatformKeyCodes.Shift)) {
            movement_base_speed *= free_look_cam.boost_factor;
        }

        if (!zm.all(zm.isNearEqual(movement_input, zm.f32x4s(0.0), zm.f32x4s(std.math.floatEps(f32))), 3)) {
            var input = zm.normalize3(movement_input) * zm.f32x4s(movement_base_speed);

            position.value += zm.mul(input, zm.matFromQuat(rotation.value));

            ecs.modified_id(it.world, entity, ecs.id(world, Core.Transform.Position));
        }

        if (!std.math.approxEqRel(f32, platform_input.mouse_pos[2], 0, std.math.floatEps(f32)) or
            !std.math.approxEqRel(f32, platform_input.mouse_pos[3], 0, std.math.floatEps(f32)))
        {
            free_look_cam.yaw += platform_input.mouse_pos[2] * delta_time * free_look_cam.yaw_rotation_speed;
            free_look_cam.pitch += platform_input.mouse_pos[3] * delta_time * free_look_cam.pitch_rotation_speed;

            const pitch_max_extent = std.math.pi / 2.0 - 0.01;
            free_look_cam.pitch = std.math.clamp(free_look_cam.pitch, -pitch_max_extent, pitch_max_extent);

            rotation.value = zm.quatFromRollPitchYaw(free_look_cam.pitch, free_look_cam.yaw, 0);

            ecs.modified_id(it.world, entity, ecs.id(world, Core.Transform.Rotation));
        }
    }
}

fn toggleFreeLookCamera(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;
    var platform_input = ecs.get(it.world, ecs.id(world, Application.PlatformInput), Application.PlatformInput).?;

    if (!platform_input.has_focus) {
        return;
    }

    if (!platform_input.isKeyPressedThisFrame(Application.PlatformKeyCodes.G)) {
        return;
    }

    _ = ecs.defer_begin(it.world);
    defer _ = ecs.defer_end(it.world);

    if (ecs.get(it.world, ecs.id(world, Self), Renderer.Camera) != null) {
        ecs.remove(it.world, ecs.id(world, Self), Renderer.Camera);
        ecs.remove(it.world, ecs.id(world, Self), Core.Gameplay.ControlEntity);

        std.log.info("[FreeLookCamera] Disabled", .{});
    } else {
        _ = ecs.set(
            it.world,
            ecs.id(world, Self),
            Core.Gameplay.ControlEntity,
            .{
                .priority = CameraPriority,
            },
        );

        _ = ecs.set(
            it.world,
            ecs.id(world, Self),
            Renderer.Camera,
            .{
                .priority = CameraPriority,
            },
        );

        std.log.info("[FreeLookCamera] Enabled", .{});
    }
}

pub fn init(world: *ecs.world_t) void {
    std.log.info("[FreeLookCamera] Initializing...", .{});

    ecs.COMPONENT(world, Self);

    Core.Transform.addTransformToEntity(world, ecs.id(world, Self), .{});

    _ = ecs.set(
        world,
        ecs.id(world, Self),
        Self,
        .{ .movement_speed = 20 },
    );

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(world, Self) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(world, Core.Transform.Position) };
        system_desc.query.filter.terms[2] = .{ .id = ecs.id(world, Core.Transform.Rotation) };
        system_desc.query.filter.terms[3] = .{ .id = ecs.id(world, Core.Gameplay.ControlledEntity) };
        system_desc.callback = updateFreeLookCamera;
        ecs.SYSTEM(world, "Update Free Look Camera", ecs.OnUpdate, &system_desc);
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = toggleFreeLookCamera;
        ecs.SYSTEM(world, "Toggle Free Look Camera", ecs.OnUpdate, &system_desc);
    }
}
