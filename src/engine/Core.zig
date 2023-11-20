const std = @import("std");
const ecs = @import("zflecs");

pub const SystemCollection = @import("system_collection.zig");

pub const Transform = @import("core/Transform.zig");
pub const Gameplay = @import("core/Gameplay.zig");

pub const AssetImporting = @import("core/AssetImporting.zig");
pub const FileStreaming = @import("core/FileStreaming.zig");
pub const QuitApplication = @import("core/QuitApplication.zig");

pub const PersistentAllocator = struct { value: std.mem.Allocator };
pub const FrameAllocator = struct { value: std.mem.Allocator };

const GltfImporter = @import("core/importers/GltfImporter.zig");
const DDSImporter = @import("core/importers/DDSTextureImporter.zig");
const ShaderImporter = @import("core/importers/ShaderImporter.zig");

pub fn preInitializeModule(world: *ecs.world_t) void {
    _ = world;
}

const NumArenas = 2;

const AllocationState = struct {
    arena_seq: u64,
    arena_array: [NumArenas]std.heap.ArenaAllocator,
};

const AllocationStatePtr = struct { value: *AllocationState };

pub fn resetFrameAllocator(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;

    var state_ptr = ecs.get_mut(it.world, ecs.id(world, AllocationStatePtr), AllocationStatePtr).?;

    state_ptr.value.arena_seq += 1;
    var arena = &state_ptr.value.arena_array[state_ptr.value.arena_seq % NumArenas];
    _ = arena.reset(.retain_capacity);

    _ = ecs.set(it.world, ecs.id(world, FrameAllocator), FrameAllocator, .{ .value = arena.allocator() });
}

pub fn freeAllocatorState(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;

    var allocator = ecs.get(it.world, ecs.id(world, AllocationStatePtr), AllocationStatePtr).?;
    var persistent_allocator = ecs.get(it.world, ecs.id(world, PersistentAllocator), PersistentAllocator).?;
    for (allocator.value.arena_array) |arena| {
        arena.deinit();
    }

    persistent_allocator.value.destroy(allocator.value);
}

fn tickFileStreaming(iter: *ecs.iter_t) callconv(.C) void {
    var file_streaming = ecs.get_mut(iter.world, ecs.id(iter.world, FileStreaming), FileStreaming).?;
    file_streaming.tickFileStreaming();
}

fn tickAssetImporting(iter: *ecs.iter_t) callconv(.C) void {
    var asset_importing = ecs.get_mut(iter.world, ecs.id(iter.world, AssetImporting), AssetImporting).?;
    asset_importing.tickOperations();
}

pub fn initializeAllocators(world: *ecs.world_t, comptime world_type: SystemCollection.WorldType, persistent_allocator: std.mem.Allocator) !void {
    ecs.COMPONENT(world, PersistentAllocator);
    ecs.COMPONENT(world, FrameAllocator);
    ecs.COMPONENT(world, AllocationStatePtr);
    ecs.COMPONENT(world, AssetImporting.ImportStatus);

    Transform.init(world);
    try Gameplay.init(world);

    ecs.setSingleton(
        world,
        FileStreaming,
        FileStreaming.init(persistent_allocator) catch @panic("Failed to initialize filestreaming"),
    );

    var asset_importing = AssetImporting.init(persistent_allocator, world) catch @panic("Failed to initialize assetimporting");
    var gltfImporter = GltfImporter.init(persistent_allocator, world) catch @panic("Failed to initialize gltf importer");
    var ddsImporter = DDSImporter.init(persistent_allocator, world) catch @panic("Failed to initialize dds importer");
    var shaderImporter = ShaderImporter.init(persistent_allocator, world) catch @panic("Failed to initialize shader importer");

    if (world_type == .Client) {
        asset_importing.importer_collection.addImporter(&gltfImporter.importer, &[_][]const u8{ ".gltf", ".glb" });
        asset_importing.importer_collection.addImporter(&ddsImporter.importer, &[_][]const u8{".dds"});
        asset_importing.importer_collection.addImporter(&shaderImporter.importer, &[_][]const u8{".shader"});
    }

    ecs.setSingleton(
        world,
        AssetImporting,
        asset_importing,
    );

    ecs.setSingleton(world, PersistentAllocator, .{ .value = persistent_allocator });

    var allocation_state = persistent_allocator.create(AllocationState) catch @panic("OOM");
    allocation_state.* = .{ .arena_seq = 0, .arena_array = undefined };

    for (&allocation_state.arena_array) |*arena| {
        arena.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    }

    ecs.setSingleton(
        world,
        FrameAllocator,
        .{ .value = allocation_state.arena_array[0].allocator() },
    );
    ecs.setSingleton(
        world,
        AllocationStatePtr,
        .{ .value = allocation_state },
    );

    {
        var free_arena_allocators_desc = ecs.observer_desc_t{
            .callback = freeAllocatorState,
            .filter = .{
                .terms = [_]ecs.term_t{.{
                    .id = ecs.id(world, AllocationStatePtr),
                }} ++ [_]ecs.term_t{.{}} ** (ecs.TERM_DESC_CACHE_SIZE - 1),
            },
            .events = [_]ecs.entity_t{ecs.OnRemove} ++ [_]ecs.entity_t{0} ** (ecs.OBSERVER_DESC_EVENT_COUNT_MAX - 1),
        };

        ecs.OBSERVER(world, "Free Allocator State", &free_arena_allocators_desc);
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = tickFileStreaming;
        ecs.SYSTEM(world, "Tick File Streaming", ecs.PreFrame, &system_desc);
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = tickAssetImporting;
        ecs.SYSTEM(world, "Tick Asset Importing", ecs.PreFrame, &system_desc);
    }
}

pub fn initializeModule(world: *ecs.world_t) void {
    ecs.COMPONENT(world, QuitApplication);

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = resetFrameAllocator;
        ecs.SYSTEM(world, "Reset Frame Allocator", ecs.PreFrame, &system_desc);
    }
}

pub fn deinitModule(world: *ecs.world_t) void {
    var asset_importing = ecs.get_mut(world, ecs.id(world, AssetImporting), AssetImporting).?;
    var file_streaming = ecs.get_mut(world, ecs.id(world, FileStreaming), FileStreaming).?;

    asset_importing.deinit();
    file_streaming.deinit();
}
