const std = @import("std");
const Engine = @import("Engine");
const Physics = Engine.Physics;
const Transform = Engine.Core.Transform;
const Application = Engine.Application;
const Renderer = Engine.Renderer;
const GuiRendererDX12 = Renderer.GuiRendererDX12;

const ecs = Engine.ecs;

const MainMenuState = struct {
    window_query: *ecs.query_t,
};

fn drawMainMenu(it: *ecs.iter_t) callconv(.C) void {
    var main_menu_state_arr = ecs.field(it, MainMenuState, 1).?;
    var main_menu_state = main_menu_state_arr[0];

    //TODO: Ehhh we maybe should make the main window just a singleton. (lukas)
    var window_maybe: ?Application.Window = null;
    var window_it = ecs.query_iter(it.world, main_menu_state.window_query);
    while (ecs.query_next(&window_it)) {
        var window_array = ecs.field(&window_it, Application.Window, 1).?;

        for (window_array) |win| {
            window_maybe = win;
        }
    }

    if (window_maybe == null) {
        return;
    }

    var window = window_maybe.?;

    const draw_data = GuiRendererDX12.c.igGetDrawData();

    GuiRendererDX12.c.igSetNextWindowPos(
        GuiRendererDX12.c.ImVec2{ .x = window.size[0] / 2.0, .y = window.size[1] / 2.0 },
        GuiRendererDX12.c.ImGuiCond_FirstUseEver,
        GuiRendererDX12.c.ImVec2{ .x = 0.5, .y = 0.5 },
    );

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

    if (GuiRendererDX12.c.igButton("Play", .{ .x = 200, .y = 30 })) {
        std.log.info("Play clicked", .{});
    }
    if (GuiRendererDX12.c.igButton("Quit", .{ .x = 200, .y = 30 })) {
        std.log.info("Quit clicked", .{});
    }

    defer GuiRendererDX12.c.igEnd();
}

pub fn init(world: *ecs.world_t) void {
    ecs.COMPONENT(world, MainMenuState);

    var window_query_desc: ecs.query_desc_t = .{};
    window_query_desc.filter.terms[0] = .{ .id = ecs.id(world, Application.Window) };
    var window_query = ecs.query_init(world, &window_query_desc) catch @panic("Failed to create window query");

    ecs.setSingleton(world, MainMenuState, .{
        .window_query = window_query,
    });

    {
        var main_menu_query = ecs.system_desc_t{
            .callback = drawMainMenu,
        };

        main_menu_query.query.filter.terms[0] = .{ .id = ecs.id(world, MainMenuState) };

        ecs.SYSTEM(world, "MainMenuRender", ecs.OnUpdate, &main_menu_query);
    }
}
