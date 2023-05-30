const std = @import("std");
const Engine = @import("Engine");
const Physics = Engine.Physics;
const Transform = Engine.Core.Transform;
const Application = Engine.Application;
const ecs = Engine.ecs;
const zm = Engine.zm;

pub const CapsuleShapeSettings = Physics.CapsuleShapeSettings;
pub const Shape = Physics.Shape;
pub const CharacterVirtual = Physics.CharacterVirtual;
pub const CharacterVirtualSettings = Physics.CharacterVirtualSettings;

pub const CharacterController = struct {
    physics_character: ?*CharacterVirtual,
};

pub fn stepCharacterMovement(it: *ecs.iter_t) callconv(.C) void {
    var platform_input = ecs.getSingleton(it.world, Application.PlatformInput).?;

    // if (input[0] == 0.0) {
    // return;
    // }

    // if(platform_input.has_focus) {
    // return;
    // }

    var physics_world = ecs.getSingleton(it.world, Physics.PhysicsWorld).?;
    var entity_array = ecs.field(it, ecs.entity_t, 0).?;
    var character_array = ecs.field(it, CharacterController, 1).?;
    var position_array = ecs.field(it, Transform.Position, 2).?;
    var rotation_array = ecs.field(it, Transform.Rotation, 3).?;

    for (entity_array, character_array, position_array, rotation_array) |entity, *character, *position, *rotation| {
        var movement_input: [2]f32 = .{ 0.0, 0.0 };

        if (platform_input.has_focus) {
            var is_controlled = ecs.has_id(it.world, entity, ecs.id(it.world, Engine.Core.Gameplay.ControlledEntity));

            if (is_controlled) {
                if (platform_input.isKeyPressed(Application.PlatformKeyCodes.W)) {
                    movement_input[1] += 1;
                }
                if (platform_input.isKeyPressed(Application.PlatformKeyCodes.S)) {
                    movement_input[1] -= 1;
                }
                if (platform_input.isKeyPressed(Application.PlatformKeyCodes.D)) {
                    movement_input[0] += 1;
                }
                if (platform_input.isKeyPressed(Application.PlatformKeyCodes.A)) {
                    movement_input[0] -= 1;
                }
            }
        }

        if (character.physics_character == null) {
            var capsule_shape_settings = CapsuleShapeSettings.create(0.8, 0.3) catch unreachable;
            defer capsule_shape_settings.release();

            var capsule_shape = CapsuleShapeSettings.createShape(capsule_shape_settings) catch unreachable;
            defer capsule_shape.release();

            var character_settings = CharacterVirtualSettings.create() catch unreachable;
            defer character_settings.release();

            character_settings.setShape(capsule_shape);

            character.physics_character = CharacterVirtual.create(character_settings, undefined, [_]f32{ 1.0, 0.0, 0.0, 0.0 }, physics_world.physics_system) catch unreachable;
        }

        var character_controller = character.physics_character.?;
        // _ = character_controller;

        _ = rotation;

        character_controller.setUp(.{ 0.0, 1.0, 0.0 });

        var in_position: [3]Physics.Real = .{
            position.value[0],
            position.value[1],
            position.value[2],
        };
        character_controller.setPosition(in_position);

        var physics_system = physics_world.physics_system;

        var max_movement_speed: f32 = 5.0;
        // var current_velocity = character_controller.getLinearVelocity();

        var desired_velocity = zm.f32x4(movement_input[0], 0, movement_input[1], 0.0);
        desired_velocity *= zm.f32x4s(max_movement_speed);

        var velocity = desired_velocity;

        var in_velocity: [3]Physics.Real = .{
            velocity[0],
            velocity[1],
            velocity[2],
        };

        character_controller.setLinearVelocity(in_velocity);

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

pub fn init(world: *ecs.world_t) void {
    ecs.COMPONENT(world, CharacterController);

    var character_controller_query = ecs.system_desc_t{
        .callback = stepCharacterMovement,
    };

    character_controller_query.query.filter.terms[0] = .{
        .id = ecs.id(world, CharacterController),
    };

    character_controller_query.query.filter.terms[1] = .{
        .id = ecs.id(world, Transform.Position),
    };

    character_controller_query.query.filter.terms[2] = .{
        .id = ecs.id(world, Transform.Rotation),
    };

    ecs.SYSTEM(world, "StepCharacterMovement", ecs.OnUpdate, &character_controller_query);
}
