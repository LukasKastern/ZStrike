const Engine = @import("Engine");
const Application = Engine.Application;
const Core = Engine.Core;
const ecs = Engine.ecs;

const Game = @import("Game.zig");

pub const MainMenu = @import("ui/MainMenu.zig");

pub const UIStates = packed struct(u32) {
    main_menu: bool = false,
    connecting: bool = false,
    in_game: bool = false,

    _: u29 = 0,
};

const UIControlState = struct {
    network_component_query: *ecs.query_t,
};

fn updateUI(it: *ecs.iter_t) callconv(.C) void {
    var control_state = ecs.getSingleton(it.world, UIControlState).?;

    var ui_state = UIStates{};

    var network_it = ecs.query_iter(it.world, control_state.network_component_query);
    while (ecs.query_next(&network_it)) {
        var state_array = ecs.field(&network_it, Game.Network.State, 2).?;

        for (state_array) |state| {
            switch (state) {
                .Connecting => {
                    ui_state.connecting = true;
                },
                .InGame => {
                    ui_state.in_game = true;
                },
                else => {},
            }
        }
    }

    if (ui_state.connecting or @as(u32, @bitCast(ui_state)) == 0) {
        ui_state.main_menu = true;
    }

    ecs.setSingleton(it.world, UIStates, ui_state);

    if (ui_state.main_menu) {
        MainMenu.drawMainMenu(it.world);
    }
}

pub fn init(world: *ecs.world_t) void {
    MainMenu.init(world);

    var network_query_desc: ecs.query_desc_t = .{};
    network_query_desc.filter.terms[0] = .{ .id = ecs.id(world, Game.Network.ConnectionComponent) };
    network_query_desc.filter.terms[1] = .{ .id = ecs.id(world, Game.Network.State) };
    var network_query = ecs.query_init(world, &network_query_desc) catch @panic("Failed to create network query");

    ecs.setSingleton(world, UIControlState, .{
        .network_component_query = network_query,
    });

    ecs.setSingleton(world, UIStates, .{});

    {
        var main_menu_query = ecs.system_desc_t{
            .callback = updateUI,
        };

        ecs.SYSTEM(world, "UpdateUI", ecs.OnUpdate, &main_menu_query);
    }
}
