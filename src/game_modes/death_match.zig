const GameMode = @import("GameMode.zig");
const ecs = @import("zflecs");

pub const DeathMatchConfig = struct {
    // After what time do killed player spawn back in?
    respawn_interval: f32,

    // Once this time elapsed the player with the most points wins.
    match_duration: f32,

    // When a player reaches this amount of points they win.
    points_to_win: u32,
};

pub const DeathMatchPlayerState = struct {
    _: u8,
};

pub fn init(world: *ecs.world_t) void {
    ecs.COMPONENT(world, DeathMatchConfig);
    ecs.COMPONENT(world, DeathMatchPlayerState);
}
