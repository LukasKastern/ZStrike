const std = @import("std");

const zm = @import("zmath");
const ecs = @import("zflecs");

pub const Position = struct {
    value: zm.Vec,
};

pub const Rotation = struct {
    value: zm.Quat,
};

pub const Scale = struct {
    value: zm.Vec,
};

// World Translation of the entity.
// This is a result of combining Position+Rotation+Scale.
pub const LocalToWorld = struct {
    value: zm.Mat,
};

pub fn buildLocalToWorld(it: *ecs.iter_t) callconv(.C) void {
    var entity_array = ecs.field(it, ecs.entity_t, 0).?;
    var position_array = ecs.field(it, Position, 1).?;
    var rotation_array = ecs.field(it, Rotation, 2).?;
    var scale_array = ecs.field(it, Scale, 3).?;

    for (entity_array, position_array, rotation_array, scale_array) |entity, pos, rot, scale| {
        var rot_scale = zm.mul(zm.matFromQuat(rot.value), zm.scalingV(scale.value));

        _ = ecs.set(it.world, entity, LocalToWorld, .{
            .value = zm.mul(rot_scale, zm.translationV(pos.value)),
        });
    }
}

pub fn init(world: *ecs.world_t) void {
    ecs.COMPONENT(world, Position);
    ecs.COMPONENT(world, Rotation);
    ecs.COMPONENT(world, Scale);
    ecs.COMPONENT(world, LocalToWorld);

    var observer_desc: ecs.observer_desc_t = .{ .callback = buildLocalToWorld };

    observer_desc.filter.terms[0] = .{ .id = ecs.id(world, Position) };
    observer_desc.filter.terms[1] = .{ .id = ecs.id(world, Rotation) };
    observer_desc.filter.terms[2] = .{ .id = ecs.id(world, Scale) };

    observer_desc.events[0] = ecs.OnSet;
    observer_desc.events[1] = ecs.OnAdd;

    ecs.OBSERVER(world, "Construct LocalToWorld", &observer_desc);
}

pub const TransformInit = struct {
    position: zm.Vec = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    rotation: zm.Quat = zm.quatFromMat(zm.identity()),
    scale: zm.Vec = [_]f32{ 1.0, 1.0, 1.0, 0.0 },
};

pub fn addTransformToEntity(world: *ecs.world_t, target_entity: ecs.entity_t, initial_transform: TransformInit) void {
    _ = ecs.set(world, target_entity, LocalToWorld, .{ .value = undefined });
    _ = ecs.set(world, target_entity, Position, .{ .value = initial_transform.position });
    _ = ecs.set(world, target_entity, Rotation, .{ .value = initial_transform.rotation });
    _ = ecs.set(world, target_entity, Scale, .{ .value = initial_transform.scale });
}

test "Test local to world construction" {
    const world = ecs.init();
    defer _ = ecs.fini(world);

    init(world);

    var test_entity = ecs.new_entity(world, "");

    var transform = TransformInit{};
    addTransformToEntity(world, test_entity, transform);

    const TestHelper = struct {
        fn checkTransformEqualsReference(in_world: *ecs.world_t, in_entity: ecs.entity_t, in_reference: TransformInit) !void {
            var local_to_world = ecs.get(in_world, in_entity, LocalToWorld).?;
            var pos = zm.util.getTranslationVec(local_to_world.value);
            var rot = zm.util.getRotationQuat(local_to_world.value);
            var scale = zm.util.getScaleVec(local_to_world.value);

            try std.testing.expectEqual(in_reference.position, pos);
            try std.testing.expectEqual(in_reference.rotation, rot);
            try std.testing.expectEqual(in_reference.scale, scale);
        }
    };

    try TestHelper.checkTransformEqualsReference(world, test_entity, transform);

    // Modify position
    {
        transform.position = zm.f32x4(5, -123.556, 213, 0);
        _ = ecs.set(world, test_entity, Position, .{ .value = transform.position });
        try TestHelper.checkTransformEqualsReference(world, test_entity, transform);
    }

    // Modify Rotation
    {
        transform.rotation = zm.quatFromAxisAngle(zm.f32x4(1.0, 0.0, 0.0, 0.0), 0.25 * std.math.pi);
        _ = ecs.set(world, test_entity, Rotation, .{ .value = transform.rotation });
        try TestHelper.checkTransformEqualsReference(world, test_entity, transform);
    }

    // // Modify Scale
    // {
    //     transform.scale = zm.f32x4(3, -1, 2, 0);
    //     _ = ecs.set(world, test_entity, Scale, .{ .value = transform.scale });

    //     try TestHelper.checkTransformEqualsReference(world, test_entity, transform);
    // }

    // // ecs.set(world,)
}
