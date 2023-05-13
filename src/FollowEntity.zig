const std = @import("std");

const Engine = @import("Engine");
const Transform = Engine.Core.Transform;
const ecs = Engine.ecs;
const zm = Engine.zm;

// The follow component can be used to "attach" an entity to another with a specified offset.
const Self = @This();

target: ecs.entity_t,
pos_offset: zm.Vec,
rot_offset: zm.Quat,

pub fn init(world: *ecs.world_t) void {
    ecs.COMPONENT(world, Self);

    var system_desc = ecs.system_desc_t{
        .callback = followUpdate,
    };
    system_desc.query.filter.terms[0] = .{
        .id = ecs.id(world, Self),
    };
    system_desc.query.filter.terms[1] = .{
        .id = ecs.id(world, Transform.Position),
    };
    system_desc.query.filter.terms[2] = .{
        .id = ecs.id(world, Transform.Rotation),
    };

    ecs.SYSTEM(world, "Update Follower Components", ecs.PostUpdate, &system_desc);
}

pub fn followUpdate(it: *ecs.iter_t) callconv(.C) void {
    var entity_array = ecs.field(it, ecs.entity_t, 0).?;
    var follow_entity_array = ecs.field(it, Self, 1).?;
    var position_array = ecs.field(it, Transform.Position, 2).?;
    var rotation_array = ecs.field(it, Transform.Rotation, 3).?;

    for (entity_array, follow_entity_array, position_array, rotation_array) |entity, follow_entity, *position, *rotation| {
        var other_pos_maybe = ecs.get(it.world, follow_entity.target, Transform.Position);
        var other_rot_maybe = ecs.get(it.world, follow_entity.target, Transform.Rotation);

        if (other_pos_maybe == null or other_rot_maybe == null) {
            std.log.info("Follow Entity Invalid: {}", .{follow_entity.target});
            return;
        }

        var other_pos = other_pos_maybe.?;
        var other_rot = other_rot_maybe.?;

        position.value = other_pos.value + follow_entity.pos_offset;
        rotation.value = zm.qmul(other_rot.value, follow_entity.rot_offset);

        ecs.modified_id(it.world, entity, ecs.id(it.world, Transform.Position));
        ecs.modified_id(it.world, entity, ecs.id(it.world, Transform.Rotation));
    }
}
