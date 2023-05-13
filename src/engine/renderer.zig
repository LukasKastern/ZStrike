const builtin = @import("builtin");
const std = @import("std");
const ecs = @import("zflecs");
const zm = @import("zmath");
const zmesh = @import("zmesh");

const Application = @import("application.zig");
const Core = @import("Core.zig");

const CubePrimitive = @import("renderer/CubePrimitive.zig");

const tinyobj = @import("tinyobj");

const Self = @This();

pub usingnamespace switch (builtin.target.os.tag) {
    .windows => @import("renderer/renderer_dx12.zig"),
    else => @compileError("Renderer is not supported on selected platform"),
};

// Camera used to specify the rendering perspective.
pub const Camera = struct {
    priority: isize,
};

pub const RendererInitializationError = error{};

pub fn initializeModule(world: *ecs.world_t) void {
    @This().initializePlatformModule(world);

    {
        var free_mesh_assets_desc = ecs.observer_desc_t{
            .callback = freeMeshAssets,
            .filter = .{
                .terms = [_]ecs.term_t{.{
                    .id = ecs.id(world, Mesh),
                }} ++ [_]ecs.term_t{.{}} ** (ecs.TERM_DESC_CACHE_SIZE - 1),
            },
            .events = [_]ecs.entity_t{ecs.OnRemove} ++ [_]ecs.entity_t{0} ** (ecs.OBSERVER_DESC_EVENT_COUNT_MAX - 1),
        };

        ecs.OBSERVER(world, "Free Mesh Assets", &free_mesh_assets_desc);
    }
}

pub fn preInitializeModule(world: *ecs.world_t) void {
    ecs.COMPONENT(world, Camera);
    ecs.COMPONENT(world, Mesh);
    ecs.COMPONENT(world, RenderTransform);
    ecs.COMPONENT(world, RenderPrimitives);
    ecs.COMPONENT(world, Material);
    ecs.COMPONENT(world, Renderer);
    ecs.TAG(world, RenderMeshRef);
    ecs.TAG(world, ShaderRef);

    @This().preInitializePlatformModule(world);

    var cube = ecs.new_entity(world, "Standard Cube Mesh");

    var persistent_allocator = ecs.get(world, ecs.id(world, Core.PersistentAllocator), Core.PersistentAllocator).?;

    var vertices = persistent_allocator.*.value.alloc(Mesh.Vertex, CubePrimitive.positions.len) catch @panic("OOM");
    var indices = persistent_allocator.*.value.alloc(u32, CubePrimitive.indices.len) catch @panic("OOM");
    std.mem.copy(u32, indices, &CubePrimitive.indices);

    for (vertices, CubePrimitive.positions, CubePrimitive.normals, CubePrimitive.uvs) |*vertex, pos, normal, uv| {
        vertex.* = .{
            .pos = pos,
            .uv = uv,
            .normal = normal,
        };
    }

    var cube_mesh = Mesh{
        .vertices = vertices,
        .indices = indices,
        .allocator = persistent_allocator.value,
    };

    _ = ecs.set(world, cube, Mesh, cube_mesh);
    _ = ecs.set(
        world,
        cube,
        @This().UploadResource,
        .{
            .resource_data = .{ .Mesh = {} },
        },
    );

    _ = ecs.set(
        world,
        ecs.id(world, RenderPrimitives),
        RenderPrimitives,
        .{
            .cube = cube,
        },
    );

    var build_render_transform_desc: ecs.observer_desc_t = .{ .callback = buildRenderTransform };
    build_render_transform_desc.filter.terms[0] = .{ .id = ecs.id(world, Core.Transform.LocalToWorld) };
    build_render_transform_desc.filter.terms[1] = .{ .id = ecs.id(world, RenderTransform) };
    build_render_transform_desc.events[0] = ecs.OnSet;
    build_render_transform_desc.events[1] = ecs.OnAdd;

    ecs.OBSERVER(world, "Build Render Transform", &build_render_transform_desc);
}

// Relationship used to specify the mesh an entity should be renderered with.
pub const RenderMeshRef = struct {};

pub const ShaderRef = struct {};

pub const Material = struct {
    pub const TextureSlots = struct {
        base_color: ecs.entity_t = 0,
    };

    textures: TextureSlots = .{},
};

pub const Mesh = struct {
    pub const Vertex = struct {
        pos: [3]f32,
        normal: [3]f32,
        uv: [2]f32,
    };

    allocator: std.mem.Allocator,
    vertices: []Vertex,
    indices: []u32,
};

pub const RenderPrimitives = struct {
    cube: ecs.entity_t,
};

pub const Renderer = struct { dummy: u8 };

pub const RenderTransform = zm.Mat;

fn freeMeshAssets(it: *ecs.iter_t) callconv(.C) void {
    var meshes = ecs.field(it, Mesh, 1).?;
    for (meshes) |mesh| {
        mesh.allocator.free(mesh.indices);
        mesh.allocator.free(mesh.vertices);
    }
}

pub fn buildRenderTransform(it: *ecs.iter_t) callconv(.C) void {
    var local_to_world_array = ecs.field(it, Core.Transform.LocalToWorld, 1).?;
    var out_render_transform_array = ecs.field(it, RenderTransform, 2).?;

    for (local_to_world_array, out_render_transform_array) |local_to_world, *render_transform| {
        render_transform.* = zm.transpose(local_to_world.value);
    }
}
