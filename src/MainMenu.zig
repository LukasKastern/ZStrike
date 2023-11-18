const std = @import("std");
const Engine = @import("Engine");
const Physics = Engine.Physics;
const Transform = Engine.Core.Transform;
const Application = Engine.Application;
const Renderer = Engine.Renderer;
const GuiRendererDX12 = Renderer.GuiRendererDX12;

const ecs = Engine.ecs;

const MainMenuState = struct {
    smth: u8,
};

fn drawMainMenu(it: *ecs.iter_t) callconv(.C) void {
    _ = it;

    const draw_data = GuiRendererDX12.c.igGetDrawData();

    // GuiRendererDX12.c.igSetNextWindowPos(
    //     GuiRendererDX12.c.ImVec2{ .x = 300.0, .y = 0.0 },
    //     GuiRendererDX12.c.ImGuiCond_FirstUseEver,
    //     GuiRendererDX12.c.ImVec2{ .x = 0.0, .y = 0.0 },
    // );
    _ = draw_data;
    _ = GuiRendererDX12.c.igBegin(
        "MainMenu",
        null,
        GuiRendererDX12.c.ImGuiWindowFlags_NoTitleBar |
            GuiRendererDX12.c.ImGuiWindowFlags_NoMove |
            // GuiRendererDX12.c.ImGuiWindowFlags_NoBackground |
            GuiRendererDX12.c.ImGuiWindowFlags_NoResize |
            GuiRendererDX12.c.ImGuiWindowFlags_NoSavedSettings,
    );

    if (GuiRendererDX12.c.igButton("Play", .{ .x = 200, .y = 30 })) {}
    if (GuiRendererDX12.c.igButton("Quit", .{ .x = 200, .y = 30 })) {}

    defer GuiRendererDX12.c.igEnd();
}

pub fn init(world: *ecs.world_t) void {
    ecs.COMPONENT(world, MainMenuState);

    {
        var main_menu_query = ecs.system_desc_t{
            .callback = drawMainMenu,
        };

        ecs.SYSTEM(world, "MainMenuRender", ecs.OnUpdate, &main_menu_query);
    }
}
