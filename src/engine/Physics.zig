const zphy = @import("zphysics");
const std = @import("std");

const Engine = @import("Engine.zig");
const Core = Engine.Core;
const Transform = Core.Transform;
const zm = Engine.zm;

const ecs = Engine.ecs;

pub const BoxShapeSettings = zphy.BoxShapeSettings;

pub const PhysicsShape = struct {
    shape_settings: union(enum) {
        Box: struct {
            extents: [3]f32,
        },
    },
};

pub const PhysicsBody = struct {
    dummy: u8 = 0,
};

const PhysicsBodyState = struct {
    body: *zphy.Body,
    shape: *zphy.Shape,
};

pub const PhysicsWorld = struct {
    allocator: std.mem.Allocator,
    broad_phase_layer_interface: *BroadPhaseLayerInterface,
    object_layer_pair_filter: *ObjectLayerPairFilter,
    object_vs_broad_phase_layer_filter: *ObjectVsBroadPhaseLayerFilter,
    physics_system: *zphy.PhysicsSystem,

    pre_physics: ecs.entity_t,
    post_physics: ecs.entity_t,

    dynamic_body_query: *ecs.query_t,

    create_physics_body_query: *ecs.query_t,
    destroy_physics_body_query: *ecs.query_t,
};

pub fn preInitializeModule(world: *ecs.world_t) void {
    ecs.COMPONENT(world, PhysicsBody);
    ecs.COMPONENT(world, PhysicsShape);
    ecs.COMPONENT(world, PhysicsBodyState);
}

pub fn initializeModule(world: *ecs.world_t) void {
    var allocator = ecs.getSingleton(world, Core.PersistentAllocator).?.value;

    var broad_phase_layer_interface = allocator.create(BroadPhaseLayerInterface) catch @panic("OOM");
    var object_vs_broad_phase_layer_filter = allocator.create(ObjectVsBroadPhaseLayerFilter) catch @panic("OOM");
    var object_layer_pair_filter = allocator.create(ObjectLayerPairFilter) catch @panic("OOM");

    broad_phase_layer_interface.* = .{};
    object_vs_broad_phase_layer_filter.* = .{};
    object_layer_pair_filter.* = .{};

    try zphy.init(allocator, .{});

    var physics_system = zphy.PhysicsSystem.create(
        @ptrCast(*const zphy.BroadPhaseLayerInterface, broad_phase_layer_interface),
        @ptrCast(*const zphy.ObjectVsBroadPhaseLayerFilter, object_vs_broad_phase_layer_filter),
        @ptrCast(*const zphy.ObjectLayerPairFilter, object_layer_pair_filter),
        .{
            .max_bodies = 1024,
            .num_body_mutexes = 0,
            .max_body_pairs = 1024,
            .max_contact_constraints = 1024,
        },
    ) catch @panic("Failed to intialize physics system");

    var pre_physics = ecs.new_w_id(world, ecs.Phase);
    var post_physics = ecs.new_w_id(world, ecs.Phase);

    ecs.add_pair(world, pre_physics, ecs.DependsOn, ecs.OnUpdate);
    ecs.add_pair(world, post_physics, ecs.DependsOn, pre_physics);

    var create_physics_body_desc = ecs.query_desc_t{};
    create_physics_body_desc.filter.terms[0] = .{
        .id = ecs.id(world, PhysicsShape),
    };
    create_physics_body_desc.filter.terms[1] = .{
        .id = ecs.id(world, PhysicsBodyState),
        .oper = .Not,
    };
    create_physics_body_desc.filter.terms[2] = .{
        .id = ecs.id(world, Transform.Position),
    };
    create_physics_body_desc.filter.terms[3] = .{
        .id = ecs.id(world, Transform.Rotation),
    };

    var create_physics_body_query = ecs.query_init(
        world,
        &create_physics_body_desc,
    ) catch @panic("OOM");

    var destroy_physics_body_desc = ecs.query_desc_t{};
    destroy_physics_body_desc.filter.terms[0] = .{
        .id = ecs.id(world, PhysicsBodyState),
    };
    destroy_physics_body_desc.filter.terms[1] = .{
        .id = ecs.id(world, PhysicsShape),
        .oper = .Not,
    };

    var destroy_physics_body_query = ecs.query_init(
        world,
        &destroy_physics_body_desc,
    ) catch @panic("OOM");

    var dynamic_body_query_desc = ecs.query_desc_t{};
    dynamic_body_query_desc.filter.terms[0] = .{
        .id = ecs.id(world, PhysicsBody),
    };
    dynamic_body_query_desc.filter.terms[1] = .{
        .id = ecs.id(world, PhysicsBodyState),
    };
    dynamic_body_query_desc.filter.terms[2] = .{
        .id = ecs.id(world, Transform.Position),
    };
    dynamic_body_query_desc.filter.terms[3] = .{
        .id = ecs.id(world, Transform.Rotation),
    };

    var dynamic_body_query = ecs.query_init(
        world,
        &dynamic_body_query_desc,
    ) catch @panic("OOM");

    ecs.setSingleton(
        world,
        PhysicsWorld,
        .{
            .allocator = allocator,
            .broad_phase_layer_interface = broad_phase_layer_interface,
            .object_vs_broad_phase_layer_filter = object_vs_broad_phase_layer_filter,
            .object_layer_pair_filter = object_layer_pair_filter,
            .physics_system = physics_system,
            .pre_physics = pre_physics,
            .post_physics = post_physics,

            .dynamic_body_query = dynamic_body_query,
            .create_physics_body_query = create_physics_body_query,
            .destroy_physics_body_query = destroy_physics_body_query,
        },
    );

    var tick_physics_desc = ecs.system_desc_t{ .callback = tickPhysics };
    ecs.SYSTEM(world, "Step Physics", post_physics, &tick_physics_desc);
}

pub fn tickPhysics(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;

    _ = ecs.defer_begin(it.world);
    defer _ = ecs.defer_end(it.world);

    var physics_world = ecs.get_mut(world, ecs.id(world, PhysicsWorld), PhysicsWorld).?;

    {
        var body_interface_mut = physics_world.physics_system.getBodyInterfaceMut();

        var create_body_it = ecs.query_iter(it.world, physics_world.create_physics_body_query);
        while (ecs.query_next(&create_body_it)) {
            var entity_array = ecs.field(&create_body_it, ecs.entity_t, 0).?;
            var physics_shape_array = ecs.field(&create_body_it, PhysicsShape, 1).?;
            var position_array = ecs.field(&create_body_it, Transform.Position, 3).?;
            var rotation_array = ecs.field(&create_body_it, Transform.Rotation, 4).?;

            var has_physics_body = ecs.has_id(
                create_body_it.world,
                entity_array[0],
                ecs.id(create_body_it.world, PhysicsBody),
            );

            for (entity_array, physics_shape_array, position_array, rotation_array) |entity, physics_shape, position, rotation| {
                var shape = blk: {
                    switch (physics_shape.shape_settings) {
                        .Box => |box| {
                            //TODO: Fix the error handling up (lukas)
                            var shape_settings = BoxShapeSettings.create(box.extents) catch unreachable;
                            var shape = shape_settings.createShape() catch unreachable;
                            shape_settings.release();

                            break :blk shape;
                        },
                    }
                };

                var body = body_interface_mut.createBody(.{
                    .position = position.value,
                    .rotation = rotation.value,
                    .shape = shape,
                    .object_layer = if (has_physics_body) object_layers.moving else object_layers.non_moving,
                    .motion_type = if (has_physics_body) .dynamic else .static,
                }) catch @panic("Failed to create and add body");

                body_interface_mut.addBody(body.id, .activate);

                _ = ecs.set(world, entity, PhysicsBodyState, .{
                    .body = body,
                    .shape = @ptrCast(*zphy.Shape, shape),
                });
            }
        }
    }

    physics_world.physics_system.update(it.delta_time, .{});

    // Sync bodies out of the physics system.
    {
        // var body_interface = physics_world.physics_system.getBodyInterface();

        var dynamic_body_it = ecs.query_iter(it.world, physics_world.dynamic_body_query);

        while (ecs.query_next(&dynamic_body_it)) {
            var entity_array = ecs.field(&dynamic_body_it, ecs.entity_t, 0).?;
            var physics_body_state_array = ecs.field(&dynamic_body_it, PhysicsBodyState, 2).?;
            var position_array = ecs.field(&dynamic_body_it, Transform.Position, 3).?;
            var rotation_array = ecs.field(&dynamic_body_it, Transform.Rotation, 4).?;

            for (entity_array, physics_body_state_array, position_array, rotation_array) |entity, physics_body_state, *position, *rotation| {
                var physics_pos = physics_body_state.body.getPosition();
                var physics_rot = physics_body_state.body.getRotation();

                position.value = zm.f32x4(physics_pos[0], physics_pos[1], physics_pos[2], 0.0);
                rotation.value = physics_rot;

                _ = ecs.modified_id(world, entity, ecs.id(world, Transform.Position));
                _ = ecs.modified_id(world, entity, ecs.id(world, Transform.Rotation));
            }
        }
    }

    {
        var body_interface_mut = physics_world.physics_system.getBodyInterfaceMut();

        var destroy_body_it = ecs.query_iter(it.world, physics_world.destroy_physics_body_query);
        while (ecs.query_next(&destroy_body_it)) {
            var entity_array = ecs.field(&destroy_body_it, ecs.entity_t, 0).?;
            var physics_body_array = ecs.field(&destroy_body_it, PhysicsBodyState, 1).?;

            for (entity_array, physics_body_array) |entity, physics_body| {
                body_interface_mut.removeBody(physics_body.body.id);
                body_interface_mut.destroyBody(physics_body.body.id);

                physics_body.shape.release();

                ecs.remove(world, entity, PhysicsBodyState);
            }
        }
    }
}

pub fn deinitModule(world: *ecs.world_t) void {
    var physics_world = ecs.get_mut(world, ecs.id(world, PhysicsWorld), PhysicsWorld).?;

    _ = ecs.remove_all(world, ecs.id(world, PhysicsShape));

    // Manually tick physics system once so that all shapes are cleaned up.
    {
        var tick_physics_it: ecs.iter_t = undefined;
        tick_physics_it.world = world;
        tick_physics_it.delta_time = 1.0 / 60.0;
        tickPhysics(&tick_physics_it);
    }

    physics_world.physics_system.destroy();
    physics_world.allocator.destroy(physics_world.broad_phase_layer_interface);
    physics_world.allocator.destroy(physics_world.object_vs_broad_phase_layer_filter);
    physics_world.allocator.destroy(physics_world.object_layer_pair_filter);

    zphy.deinit();
}

const object_layers = struct {
    const non_moving: zphy.ObjectLayer = 0;
    const moving: zphy.ObjectLayer = 1;
    const len: u32 = 2;
};

const broad_phase_layers = struct {
    const non_moving: zphy.BroadPhaseLayer = 0;
    const moving: zphy.BroadPhaseLayer = 1;
    const len: u32 = 2;
};

const BroadPhaseLayerInterface = extern struct {
    usingnamespace zphy.BroadPhaseLayerInterface.Methods(@This());
    __v: *const zphy.BroadPhaseLayerInterface.VTable = &vtable,

    object_to_broad_phase: [object_layers.len]zphy.BroadPhaseLayer = undefined,

    const vtable = zphy.BroadPhaseLayerInterface.VTable{
        .getNumBroadPhaseLayers = _getNumBroadPhaseLayers,
        .getBroadPhaseLayer = _getBroadPhaseLayer,
    };

    fn init() BroadPhaseLayerInterface {
        var layer_interface: BroadPhaseLayerInterface = .{};
        layer_interface.object_to_broad_phase[object_layers.non_moving] = broad_phase_layers.non_moving;
        layer_interface.object_to_broad_phase[object_layers.moving] = broad_phase_layers.moving;
        return layer_interface;
    }

    fn _getNumBroadPhaseLayers(_: *const zphy.BroadPhaseLayerInterface) callconv(.C) u32 {
        return broad_phase_layers.len;
    }

    fn _getBroadPhaseLayer(
        iself: *const zphy.BroadPhaseLayerInterface,
        layer: zphy.ObjectLayer,
    ) callconv(.C) zphy.BroadPhaseLayer {
        const self = @ptrCast(*const BroadPhaseLayerInterface, iself);
        return self.object_to_broad_phase[layer];
    }
};

const ObjectVsBroadPhaseLayerFilter = extern struct {
    usingnamespace zphy.ObjectVsBroadPhaseLayerFilter.Methods(@This());
    __v: *const zphy.ObjectVsBroadPhaseLayerFilter.VTable = &vtable,

    const vtable = zphy.ObjectVsBroadPhaseLayerFilter.VTable{ .shouldCollide = _shouldCollide };

    fn _shouldCollide(
        _: *const zphy.ObjectVsBroadPhaseLayerFilter,
        layer1: zphy.ObjectLayer,
        layer2: zphy.BroadPhaseLayer,
    ) callconv(.C) bool {
        return switch (layer1) {
            object_layers.non_moving => layer2 == broad_phase_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const ObjectLayerPairFilter = extern struct {
    usingnamespace zphy.ObjectLayerPairFilter.Methods(@This());
    __v: *const zphy.ObjectLayerPairFilter.VTable = &vtable,

    const vtable = zphy.ObjectLayerPairFilter.VTable{ .shouldCollide = _shouldCollide };

    fn _shouldCollide(
        _: *const zphy.ObjectLayerPairFilter,
        object1: zphy.ObjectLayer,
        object2: zphy.ObjectLayer,
    ) callconv(.C) bool {
        return switch (object1) {
            object_layers.non_moving => object2 == object_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const ContactListener = extern struct {
    usingnamespace zphy.ContactListener.Methods(@This());
    __v: *const zphy.ContactListener.VTable = &vtable,

    const vtable = zphy.ContactListener.VTable{ .onContactValidate = _onContactValidate };

    fn _onContactValidate(
        self: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        base_offset: *const [3]zphy.Real,
        collision_result: *const zphy.CollideShapeResult,
    ) callconv(.C) zphy.ValidateResult {
        _ = self;
        _ = body1;
        _ = body2;
        _ = base_offset;
        _ = collision_result;
        return .accept_all_contacts;
    }
};
