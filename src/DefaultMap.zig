const Engine = @import("Engine");

const zm = Engine.zm;
const ecs = Engine.ecs;
const Core = Engine.Core;
const Renderer = Engine.Renderer;
const Physics = Engine.Physics;

const Main = @import("main.zig");

pub fn SpawnEntites(world: *ecs.world_t) !void {
    _ = ecs.defer_begin(world);
    defer _ = ecs.defer_end(world);

    var prototype_content = ecs.getSingleton(world, Main.PrototypeContent).?;

    var prototype_black = prototype_content.prototype_tex_black;
    var prototype_red = prototype_content.prototype_tex_red;
    var prototype_green = prototype_content.prototype_tex_green;

    var prototype_shader = prototype_content.prototype_shader;

    var primitives = ecs.get(world, ecs.id(world, Renderer.RenderPrimitives), Renderer.RenderPrimitives).?;

    const SpawnEntityHelper = struct {
        primitives: Renderer.RenderPrimitives,
        shader: ecs.entity_t,
        world: *ecs.world_t,

        const Helper = @This();

        fn spawn(self: Helper, transform: Core.Transform.TransformInit, base_color: ecs.entity_t) !void {
            var ent = ecs.new_entity(self.world, "");

            Core.Transform.addTransformToEntity(self.world, ent, transform);
            _ = ecs.set(self.world, ent, Physics.PhysicsShape, .{
                .shape_settings = .{
                    .Box = .{
                        .extents = [3]f32{
                            transform.scale[0] * 0.5,
                            transform.scale[1] * 0.5,
                            transform.scale[2] * 0.5,
                        },
                    },
                },
            });

            _ = ecs.set(self.world, ent, Renderer.RenderTransform, undefined);

            _ = ecs.set(
                self.world,
                ent,
                Renderer.Material,
                .{
                    .textures = .{ .base_color = base_color },
                },
            );

            ecs.add_pair(self.world, ent, ecs.id(self.world, Renderer.RenderMeshRef), self.primitives.cube);
            ecs.add_pair(self.world, ent, ecs.id(self.world, Renderer.ShaderRef), self.shader);
        }
    };

    var helper = SpawnEntityHelper{
        .world = world,
        .primitives = primitives.*,
        .shader = prototype_shader,
    };

    try helper.spawn(.{
        .scale = zm.f32x4(35, 1, 50, 0),
    }, prototype_black);

    try helper.spawn(.{
        .scale = zm.f32x4(18, 5, 0.5, 0),
        .position = zm.f32x4(0.0, 3.05, 17, 0),
    }, prototype_green);

    try helper.spawn(.{
        .scale = zm.f32x4(18, 5, 0.5, 0),
        .position = zm.f32x4(0.0, 3.05, -17, 0),
    }, prototype_red);

    try helper.spawn(.{
        .scale = zm.f32x4(3, 3, 3, 0),
        .position = zm.f32x4(-11, 2.02, 10, 0),
    }, prototype_green);

    try helper.spawn(.{
        .scale = zm.f32x4(3, 3, 3, 0),
        .position = zm.f32x4(11, 2.02, 10, 0),
    }, prototype_green);

    try helper.spawn(.{
        .scale = zm.f32x4(3, 3, 3, 0),
        .position = zm.f32x4(-11, 2.02, -10, 0),
    }, prototype_red);

    try helper.spawn(.{
        .scale = zm.f32x4(3, 3, 3, 0),
        .position = zm.f32x4(11, 2.02, -10, 0),
    }, prototype_red);
}
