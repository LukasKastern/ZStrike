const std = @import("std");
const Engine = @import("Engine");
const Physics = Engine.Physics;
const Transform = Engine.Core.Transform;
const Application = Engine.Application;
const Renderer = Engine.Renderer;

const ecs = Engine.ecs;
const zm = Engine.zm;
const GuiRendererDX12 = Renderer.GuiRendererDX12;
const ControlledEntity = Engine.Core.Gameplay.ControlledEntity;

pub const CapsuleShapeSettings = Physics.CapsuleShapeSettings;
pub const Shape = Physics.Shape;
pub const CharacterVirtual = Physics.CharacterVirtual;
pub const CharacterVirtualSettings = Physics.CharacterVirtualSettings;

pub const Controller = struct {
    physics_character: *CharacterVirtual,
};

pub const AimData = struct {
    yaw: f32 = 0,
    pitch: f32 = 0,
};

pub const FirstPersonCamera = struct {
    target: ecs.entity_t,
    pos_offset: zm.F32x4,
    rot_offset: zm.Quat,
};

pub const Models = struct {
    first_person: ecs.entity_t,
    third_person: ecs.entity_t,
};

dummy: u8 = 0,

pub fn updateFirstPersonCameras(it: *ecs.iter_t) callconv(.C) void {
    var entity_array = ecs.field(it, ecs.entity_t, 0).?;
    var position_array = ecs.field(it, Transform.Position, 1).?;
    var rotation_array = ecs.field(it, Transform.Rotation, 2).?;
    var first_person_camera_array = ecs.field(it, FirstPersonCamera, 3).?;

    for (entity_array, position_array, rotation_array, first_person_camera_array) |entity, *position, *rotation, *first_person_camera| {
        var other_pos_maybe = ecs.get(it.world, first_person_camera.target, Transform.Position);
        var other_aim_data_maybe = ecs.get(it.world, first_person_camera.target, AimData);

        if (other_pos_maybe == null or other_aim_data_maybe == null) {
            return;
        }

        var other_pos = other_pos_maybe.?;
        var other_rot = zm.quatFromRollPitchYaw(other_aim_data_maybe.?.pitch, other_aim_data_maybe.?.yaw, 0);

        position.value = other_pos.value + first_person_camera.pos_offset;
        rotation.value = zm.qmul(other_rot, first_person_camera.rot_offset);

        ecs.modified_id(it.world, entity, ecs.id(it.world, Transform.Position));
        ecs.modified_id(it.world, entity, ecs.id(it.world, Transform.Rotation));
    }
}

pub fn stepMovement(it: *ecs.iter_t) callconv(.C) void {
    var platform_input = ecs.getSingleton(it.world, Application.PlatformInput).?;

    var entity_array = ecs.field(it, ecs.entity_t, 0).?;
    var character_array = ecs.field(it, Controller, 1).?;
    var position_array = ecs.field(it, Transform.Position, 2).?;
    var rotation_array = ecs.field(it, Transform.Rotation, 3).?;
    var character_aim_data_array = ecs.field(it, AimData, 4).?;

    var physics_world = ecs.getSingleton(it.world, Physics.PhysicsWorld).?;

    for (
        entity_array,
        character_array,
        position_array,
        rotation_array,
        character_aim_data_array,
    ) |entity, *character, *position, *rotation, *character_aim_data| {
        var movement_input = zm.f32x4s(0.0);
        var rotation_input: [2]f32 = .{ 0.0, 0.0 };

        if (platform_input.has_focus) {
            var is_controlled = ecs.has_id(it.world, entity, ecs.id(it.world, ControlledEntity));

            if (is_controlled) {
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

                rotation_input[0] = platform_input.mouse_pos[2];
                rotation_input[1] = platform_input.mouse_pos[3];
            }
        }

        var character_controller = character.physics_character;

        character_controller.setUp(.{ 0.0, 1.0, 0.0 });

        var in_position: [3]Physics.Real = .{
            position.value[0],
            position.value[1],
            position.value[2],
        };

        // Apply rotation input
        {
            const rotation_speed = 0.5;
            character_aim_data.yaw += rotation_input[0] * it.delta_time * rotation_speed;
            character_aim_data.pitch += rotation_input[1] * it.delta_time * rotation_speed;

            const pitch_max_extent = std.math.pi / 2.0 - 0.01;
            character_aim_data.pitch = std.math.clamp(character_aim_data.pitch, -pitch_max_extent, pitch_max_extent);
        }

        rotation.value = zm.quatFromRollPitchYaw(0, character_aim_data.yaw, 0);

        character_controller.setPosition(in_position);
        character_controller.setRotation(rotation.value);

        var physics_system = physics_world.physics_system;

        var current_velocity = character_controller.getLinearVelocity();

        var max_velocity: f32 = 4.0;
        var friction: f32 = 12.0;
        var acceleration: f32 = 100.0;

        var current_velocity_register = zm.loadArr3(current_velocity);
        var prev_velocity = zm.loadArr3(current_velocity);

        var speed = zm.length3(current_velocity_register)[0];
        if (speed > 0) {
            var drop = speed * friction * it.delta_time;
            prev_velocity *= zm.f32x4s(zm.max(speed - drop, 0.0) / speed);
        }

        if (!zm.approxEqAbs(movement_input, zm.f32x4s(0.0), std.math.floatEps(f32))) {
            movement_input = zm.mul(
                movement_input,
                zm.matFromQuat(
                    rotation.value,
                ),
            );
            var acceleration_direction = zm.normalize3(movement_input);

            var projected_velocity = zm.dot3(prev_velocity, acceleration_direction);
            var acceleration_velocity = acceleration * it.delta_time;

            if (projected_velocity[0] + acceleration_velocity > max_velocity) {
                acceleration_velocity = max_velocity - projected_velocity[0];
            }

            prev_velocity += acceleration_direction * zm.f32x4s(acceleration_velocity);
        }

        var new_velocity: [3]Physics.Real = undefined;
        zm.storeArr3(&new_velocity, prev_velocity);

        new_velocity[1] = -9.81;

        GuiRendererDX12.c.igSetNextWindowPos(
            GuiRendererDX12.c.ImVec2{ .x = 300.0, .y = 0.0 },
            GuiRendererDX12.c.ImGuiCond_FirstUseEver,
            GuiRendererDX12.c.ImVec2{ .x = 0.0, .y = 0.0 },
        );

        _ = GuiRendererDX12.c.igBegin(
            "Movement",
            null,
            GuiRendererDX12.c.ImGuiWindowFlags_NoTitleBar |
                GuiRendererDX12.c.ImGuiWindowFlags_NoMove |
                GuiRendererDX12.c.ImGuiWindowFlags_NoBackground |
                GuiRendererDX12.c.ImGuiWindowFlags_NoResize |
                GuiRendererDX12.c.ImGuiWindowFlags_NoSavedSettings,
        );
        defer GuiRendererDX12.c.igEnd();

        _ = GuiRendererDX12.c.igText(
            "Velocity=(%.2f). Direction=(%.2f, %.2f, %.2f)",
            zm.length3(zm.loadArr3(new_velocity))[0],
            new_velocity[0],
            new_velocity[1],
            new_velocity[2],
        );

        character_controller.setLinearVelocity(new_velocity);

        character_controller.extendedUpdate(
            it.delta_time,
            physics_system.getGravity(),
            .{},
            1,
            1,
            physics_system,
        );

        var new_position = character_controller.getPosition();

        position.value[0] = new_position[0];
        position.value[1] = new_position[1];
        position.value[2] = new_position[2];

        ecs.modified_id(it.world, entity, ecs.id(it.world, Transform.Position));
    }
}

pub const InitialCharacterConfig = struct {
    first_person_model: ecs.entity_t = 0,
    third_person_model: ecs.entity_t = 0,
};

pub fn addCharacterComponent(world: *ecs.world_t, entity: ecs.entity_t, config: InitialCharacterConfig) void {
    _ = ecs.set(world, entity, Character, .{});
    _ = ecs.set(world, entity, AimData, .{});
    _ = ecs.set(world, entity, Models, .{
        .first_person = config.first_person_model,
        .third_person = config.third_person_model,
    });
}

pub const Character = @This();

fn initializeController(it: *ecs.iter_t) callconv(.C) void {
    _ = ecs.defer_begin(it.world);
    defer _ = ecs.defer_end(it.world);

    var entity_array = ecs.field(it, ecs.entity_t, 0).?;
    _ = ecs.field(it, Character, 1).?;

    var physics_world = ecs.getSingleton(it.world, Physics.PhysicsWorld).?;

    for (entity_array) |entity| {
        var capsule_shape_settings = CapsuleShapeSettings.create(0.9, 0.3) catch unreachable;
        defer capsule_shape_settings.release();

        var capsule_shape = CapsuleShapeSettings.createShape(capsule_shape_settings) catch unreachable;
        defer capsule_shape.release();

        var character_settings = CharacterVirtualSettings.create() catch unreachable;
        defer character_settings.release();

        character_settings.setShape(capsule_shape);

        var character_virtual = CharacterVirtual.create(character_settings, undefined, [_]f32{ 1.0, 0.0, 0.0, 0.0 }, physics_world.physics_system) catch unreachable;
        _ = ecs.set(it.world, entity, Controller, .{ .physics_character = character_virtual });
    }
}

fn deinitializeControllers(it: *ecs.iter_t) callconv(.C) void {
    _ = ecs.defer_begin(it.world);
    defer _ = ecs.defer_end(it.world);

    var entity_array = ecs.field(it, ecs.entity_t, 0).?;
    var controller_array = ecs.field(it, Controller, 1).?;

    for (entity_array, controller_array) |entity, controller| {
        controller.physics_character.release();
        ecs.remove(it.world, entity, Controller);
    }
}

pub fn updateCharacterModels(it: *ecs.iter_t) callconv(.C) void {
    _ = ecs.defer_begin(it.world);
    defer _ = ecs.defer_end(it.world);

    var entity_array = ecs.field(it, ecs.entity_t, 0).?;
    var character_models_array = ecs.field(it, Models, 1).?;

    for (entity_array, character_models_array) |entity, character_models| {
        var is_controlled = ecs.has_id(it.world, entity, ecs.id(it.world, ControlledEntity));

        var target_model = if (is_controlled) character_models.first_person else character_models.third_person;

        var render_mesh_ref_id = ecs.id(it.world, Renderer.RenderMeshRef);
        var render_mesh_pair = ecs.pair(render_mesh_ref_id, ecs.Wildcard);

        var has_render_mesh_ref = ecs.has_id(it.world, entity, render_mesh_pair);

        if (has_render_mesh_ref) {
            var current_render_mesh = ecs.pair_second(render_mesh_pair);
            if (target_model != current_render_mesh) {
                ecs.remove_pair(it.world, entity, render_mesh_ref_id, current_render_mesh);
                has_render_mesh_ref = false;
            }
        }

        if (!has_render_mesh_ref and target_model != 0) {
            ecs.add_pair(it.world, entity, render_mesh_ref_id, target_model);
        }
    }
}

pub fn init(world: *ecs.world_t) void {
    ecs.COMPONENT(world, Controller);
    ecs.COMPONENT(world, AimData);
    ecs.COMPONENT(world, FirstPersonCamera);
    ecs.COMPONENT(world, Character);
    ecs.COMPONENT(world, Models);

    {
        var initialize_controller = ecs.observer_desc_t{
            .callback = initializeController,
        };
        initialize_controller.filter.terms[0] = .{ .id = ecs.id(world, Character) };
        initialize_controller.filter.terms[1] = .{ .id = ecs.id(world, Controller), .oper = .Not };

        initialize_controller.events[0] = ecs.OnSet;
        ecs.OBSERVER(world, "InitializeCharacterControllers", &initialize_controller);
    }

    {
        var deinitialize_controller = ecs.observer_desc_t{
            .callback = deinitializeControllers,
        };
        deinitialize_controller.filter.terms[0] = .{ .id = ecs.id(world, Controller) };

        deinitialize_controller.events[0] = ecs.OnRemove;

        ecs.OBSERVER(world, "DeinitializeCharacterControllers", &deinitialize_controller);
    }

    {
        var character_controller_query = ecs.system_desc_t{
            .callback = stepMovement,
        };

        character_controller_query.query.filter.terms[0] = .{
            .id = ecs.id(world, Controller),
        };

        character_controller_query.query.filter.terms[1] = .{
            .id = ecs.id(world, Transform.Position),
        };

        character_controller_query.query.filter.terms[2] = .{
            .id = ecs.id(world, Transform.Rotation),
        };

        character_controller_query.query.filter.terms[3] = .{
            .id = ecs.id(world, AimData),
        };

        ecs.SYSTEM(world, "StepMovement", ecs.OnUpdate, &character_controller_query);
    }

    {
        var first_person_camera_desc = ecs.system_desc_t{
            .callback = updateFirstPersonCameras,
        };
        first_person_camera_desc.query.filter.terms[0] = .{ .id = ecs.id(world, Transform.Position) };
        first_person_camera_desc.query.filter.terms[1] = .{ .id = ecs.id(world, Transform.Rotation) };
        first_person_camera_desc.query.filter.terms[2] = .{ .id = ecs.id(world, FirstPersonCamera) };

        ecs.SYSTEM(world, "UpdateFirstPersonCameras", ecs.OnUpdate, &first_person_camera_desc);
    }

    {
        var update_character_model_desc = ecs.system_desc_t{
            .callback = updateCharacterModels,
        };
        update_character_model_desc.query.filter.terms[0] = .{ .id = ecs.id(world, Models) };

        ecs.SYSTEM(world, "UpdateCharacterModels", ecs.OnUpdate, &update_character_model_desc);
    }
}
