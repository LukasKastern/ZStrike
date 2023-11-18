const ecs = @import("zflecs");

pub const GameStartTick = struct {
    value: u32,
};

pub const GameEndTick = struct {
    value: u32,
};

pub const PlayerStats = struct {
    points: u32,
    kills: u32,
    deaths: u32,
};

pub fn init(world: *ecs.world_t) void {
    _ = world;
}
