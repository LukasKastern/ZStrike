const Engine = @import("Engine");
const Application = Engine.Application;
const Core = Engine.Core;
const Renderer = Engine.Renderer;
const Physics = Engine.Physics;
const zm = Engine.zm;
const ecs = Engine.ecs;
const std = @import("std");
const gm = @import("game_modes.zig");

const Character = @import("Character.zig");
const DefaultMap = @import("DefaultMap.zig");
const MainMenu = @import("MainMenu.zig");

pub const PrototypeContent = struct {
    prototype_shader: ecs.entity_t,

    prototype_tex_black: ecs.entity_t,
    prototype_tex_red: ecs.entity_t,
    prototype_tex_green: ecs.entity_t,
};

fn spawnCube(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;
    var input = ecs.getSingleton(world, Application.PlatformInput).?;

    if (!input.has_focus) {
        return;
    }

    if (!input.isKeyPressedThisFrame(.Space)) {
        return;
    }

    std.log.info("Spawning Cube", .{});

    var cube_ent = ecs.new_entity(world, "");
    Core.Transform.addTransformToEntity(world, cube_ent, .{
        .position = zm.f32x4(0, 5, 0, 0),
    });

    _ = ecs.set(world, cube_ent, Physics.PhysicsShape, .{
        .shape_settings = .{
            .Box = .{
                .extents = [_]f32{ 0.5, 0.5, 0.5 },
            },
        },
    });

    _ = ecs.set(world, cube_ent, Physics.PhysicsBody, .{});

    ecs.add(world, cube_ent, Renderer.RenderTransform);

    var prototype_content = ecs.getSingleton(it.world, PrototypeContent).?;
    var primitives = ecs.getSingleton(it.world, Renderer.RenderPrimitives).?;

    ecs.add_pair(world, cube_ent, ecs.id(world, Renderer.RenderMeshRef), primitives.cube);
    _ = ecs.set(world, cube_ent, Renderer.Material, .{
        .textures = .{
            .base_color = prototype_content.prototype_tex_green,
        },
    });

    ecs.add_pair(world, cube_ent, ecs.id(world, Renderer.ShaderRef), prototype_content.prototype_shader);
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 16 }){};
    defer _ = general_purpose_allocator.deinit();

    const gpa = general_purpose_allocator.allocator();

    var engine = try Engine.init(
        gpa,
        .{
            .with_developer_content = true,
        },
    );
    defer engine.deinit();

    var world = engine.world;

    // Initialize prototype content.
    {
        var prototype_black = Core.AssetImporting.loadAsset(world, "assets/prototype/Prototype1x1Black.dds");
        var prototype_red = Core.AssetImporting.loadAsset(world, "assets/prototype/Prototype1x1Red.dds");
        var prototype_green = Core.AssetImporting.loadAsset(world, "assets/prototype/Prototype1x1Green.dds");

        var prototype_shader = Core.AssetImporting.loadAsset(world, "assets/shaders/mesh_pbr_prototype.shader");

        ecs.setSingleton(world, PrototypeContent, .{
            .prototype_shader = prototype_shader,
            .prototype_tex_black = prototype_black,
            .prototype_tex_red = prototype_red,
            .prototype_tex_green = prototype_green,
        });
    }

    try DefaultMap.SpawnEntites(world);
    Character.init(world);
    MainMenu.init(world);

    gm.init(world);

    {
        var spawn_cube_system_desc = ecs.system_desc_t{ .callback = spawnCube };

        ecs.SYSTEM(world, "Spawn Cube", ecs.OnUpdate, &spawn_cube_system_desc);
    }

    // Spawn test player
    var player_model = Core.AssetImporting.loadAsset(world, "assets/prototype/military_RTS_character_90180.glb");
    defer ecs.delete(world, player_model);

    var player_model_texture = Core.AssetImporting.loadAsset(world, "assets/prototype/textures/soldier1_diff.dds");
    defer ecs.delete(world, player_model_texture);

    var pbr_shader = Core.AssetImporting.loadAsset(world, "assets/shaders/mesh_pbr.shader");
    defer ecs.delete(world, pbr_shader);

    var player = ecs.new_entity(world, "Test Player");
    {
        Core.Transform.addTransformToEntity(world, player, .{
            .scale = zm.f32x4s(2.75),
            .position = zm.f32x4(0.0, 2.0, 0.0, 0),
        });

        ecs.add(world, player, Renderer.RenderTransform);

        ecs.add_pair(world, player, ecs.id(world, Renderer.RenderMeshRef), player_model);
        _ = ecs.set(world, player, Renderer.Material, .{
            .textures = .{
                .base_color = player_model_texture,
            },
        });

        ecs.add_pair(world, player, ecs.id(world, Renderer.ShaderRef), pbr_shader);

        Character.addCharacterComponent(world, player, .{
            .third_person_model = player_model,
        });
        _ = ecs.set(world, player, Core.Gameplay.ControlEntity, .{ .priority = 0 });
    }
    defer ecs.delete(world, player);

    var camera = ecs.new_entity(world, "First Person Camera");
    {
        Core.Transform.addTransformToEntity(world, camera, .{});
        _ = ecs.set(
            world,
            camera,
            Character.FirstPersonCamera,
            .{
                .pos_offset = zm.f32x4(0.0, 0.4, 0.0, 0.0),
                .rot_offset = zm.quatFromRollPitchYaw(
                    0,
                    0,
                    0,
                    // std.math.degreesToRadians(f32, -90),
                    // std.math.degreesToRadians(f32, 0),
                    // std.math.degreesToRadians(f32, 180),
                ),
                .target = player,
            },
        );

        _ = ecs.set(world, camera, Renderer.Camera, .{ .priority = 0 });
    }

    while (true) {
        engine.tick() catch |e| {
            switch (e) {
                error.ExitRequested => {
                    return;
                },
            }
        };
    }
}
