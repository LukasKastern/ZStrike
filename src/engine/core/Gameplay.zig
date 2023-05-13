const ecs = @import("zflecs");
const std = @import("std");

// Tag used to identify the entity that is controlled by the local player.
pub const ControlledEntity = struct {};

// Component that can be attached to an entity to indicate that it should be "controlled".
// Only the entity with the highest priority is marked as controlled.
pub const ControlEntity = struct {
    priority: u32,
};

const Self = @This();

control_entity_query: *ecs.query_t,
controlled_entity_query: *ecs.query_t,

pub fn init(world: *ecs.world_t) !void {
    ecs.COMPONENT(world, ControlEntity);
    ecs.TAG(world, ControlledEntity);
    ecs.COMPONENT(world, Self);

    var determine_controlled_entity_system_desc = ecs.system_desc_t{
        .callback = determineControlledEntity,
    };
    ecs.SYSTEM(
        world,
        "Determine Controlled Entity",
        ecs.OnUpdate,
        &determine_controlled_entity_system_desc,
    );

    var control_entity_query = blk: {
        var control_entity_query_desc = ecs.query_desc_t{};
        control_entity_query_desc.filter.terms[0] = .{
            .id = ecs.id(world, ControlEntity),
        };
        var query = try ecs.query_init(world, &control_entity_query_desc);
        break :blk query;
    };

    var controlled_entity_query = blk: {
        var controlled_entity_query_desc = ecs.query_desc_t{};
        controlled_entity_query_desc.filter.terms[0] = .{
            .id = ecs.id(world, ControlledEntity),
        };
        var query = try ecs.query_init(world, &controlled_entity_query_desc);
        break :blk query;
    };

    _ = ecs.set(world, ecs.id(world, Self), Self, .{
        .control_entity_query = control_entity_query,
        .controlled_entity_query = controlled_entity_query,
    });
}

fn determineControlledEntity(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;

    var self = ecs.getSingleton(world, Self).?;

    var controlled_entity_it = ecs.query_iter(world, self.controlled_entity_query);
    var control_entity_it = ecs.query_iter(world, self.control_entity_query);

    var entity_to_control: ?struct {
        entity: ecs.entity_t,
        priority: u32,
    } = null;

    while (ecs.query_next(&control_entity_it)) {
        var entity_array = ecs.field(&control_entity_it, ecs.entity_t, 0).?;
        var control_entity_array = ecs.field(&control_entity_it, ControlEntity, 1).?;

        for (entity_array, control_entity_array) |entity, control_entity| {
            if (entity_to_control == null or control_entity.priority > entity_to_control.?.priority) {
                entity_to_control = .{
                    .entity = entity,
                    .priority = control_entity.priority,
                };
            }
        }
    }

    var currently_controlled_entity: ?ecs.entity_t = null;

    while (ecs.query_next(&controlled_entity_it)) {
        var entity_array = ecs.field(&controlled_entity_it, ecs.entity_t, 0).?;

        // We expect only one entity to be controlled at the same time.
        std.debug.assert(currently_controlled_entity == null);

        currently_controlled_entity = entity_array[0];
    }

    var controlled_entity: ecs.entity_t = currently_controlled_entity orelse 0;
    var entity_to_control_val: ecs.entity_t = if (entity_to_control) |ent| ent.entity else 0;

    if (controlled_entity != entity_to_control_val) {
        // Decontrol current entity
        if (controlled_entity != 0) {
            ecs.remove(world, controlled_entity, ControlledEntity);
        }

        // Control new one.
        if (entity_to_control_val != 0) {
            ecs.add(world, entity_to_control_val, ControlledEntity);
        }

        std.log.info("[Gameplay] Controlled Entity Changed", .{});
    }
}

test "Controlled entity should pick entity with highest priority" {}
