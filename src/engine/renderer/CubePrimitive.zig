const zmath = @import("zmath");

const cube_front_face = [_][3]f32{

    // Bottom Right
    [_]f32{ -0.500, -0.500, 0.500 },

    // Bottom Left
    [_]f32{ 0.500, -0.500, 0.500 },

    // Top Right
    [_]f32{ -0.500, 0.500, 0.500 },

    // Top Left
    [_]f32{ 0.500, 0.500, 0.500 },
};

const cube_left_face = [_][3]f32{
    // Front Bottom
    [_]f32{ 0.500, -0.500, 0.500 },

    // Back Bottom
    [_]f32{ 0.500, -0.500, -0.500 },

    // Front Top
    [_]f32{ 0.500, 0.500, 0.500 },

    // Back Top
    [_]f32{ 0.500, 0.500, -0.500 },
};

const cube_right_face = [_][3]f32{
    // Back Bottom
    [_]f32{ -0.500, -0.500, -0.500 },

    // Front Bottom
    [_]f32{ -0.500, -0.500, 0.500 },

    // Back Top
    [_]f32{ -0.500, 0.500, -0.500 },

    // Front Top
    [_]f32{ -0.500, 0.500, 0.500 },
};

const cube_back_face = [_][3]f32{

    // Bottom Left
    [_]f32{ 0.500, -0.500, -0.500 },

    // Bottom Right
    [_]f32{ -0.500, -0.500, -0.500 },

    // Top Left
    [_]f32{ 0.500, 0.500, -0.500 },

    // Top Right
    [_]f32{ -0.500, 0.500, -0.500 },
};

const cube_top_face = [_][3]f32{

    // Bottom Right
    [_]f32{ -0.500, 0.500, 0.500 },

    // Bottom Left
    [_]f32{ 0.500, 0.500, 0.500 },

    // Top Right
    [_]f32{ -0.500, 0.500, -0.500 },

    // Top Left
    [_]f32{ 0.500, 0.500, -0.500 },
};

const cube_bottom_face = [_][3]f32{

    // Bottom Left
    [_]f32{ 0.500, -0.500, 0.500 },

    // Bottom Right
    [_]f32{ -0.500, -0.500, 0.500 },

    // Top Left
    [_]f32{ 0.500, -0.500, -0.500 },

    // Top Right
    [_]f32{ -0.500, -0.500, -0.500 },
};

const cube_front_indices = [_]u32{
    0, 3, 2,
    0, 1, 3,
};

const cube_left_indices = [_]u32{
    4, 7, 6,
    4, 5, 7,
};

const cube_right_indices = [_]u32{
    8, 11, 10,
    8, 9,  11,
};

const cube_back_indices = [_]u32{
    12, 15, 14,
    12, 13, 15,
};

const cube_top_indices = [_]u32{
    16, 19, 18,
    16, 17, 19,
};

const cube_bottom_indices = [_]u32{
    20, 23, 22,
    20, 21, 23,
};

const cube_front_uvs = [_][2]f32{
    [_]f32{ 1.000, 1.000 },
    [_]f32{ 0.000, 1.000 },
    [_]f32{ 1.000, 0.000 },
    [_]f32{ 0.000, 0.000 },
};

pub const uvs = cube_front_uvs ** 6;

pub const positions = [_][3]f32{} ++
    cube_front_face ++
    cube_left_face ++
    cube_right_face ++
    cube_back_face ++
    cube_top_face ++
    cube_bottom_face;

pub const indices = [_]u32{} ++
    cube_front_indices ++
    cube_left_indices ++
    cube_right_indices ++
    cube_back_indices ++
    cube_top_indices ++
    cube_bottom_indices;

const cube_front_normals = [_][3]f32{
    // Bottom Right
    [_]f32{ 0, 0, -1.000 },
    [_]f32{ 0, 0, -1.000 },
    [_]f32{ 0, 0, -1.000 },
    [_]f32{ 0, 0, -1.000 },
};

const cube_left_normals = [_][3]f32{
    [_]f32{ 1, 0, 0.000 },
    [_]f32{ 1, 0, 0.000 },
    [_]f32{ 1, 0, 0.000 },
    [_]f32{ 1, 0, 0.000 },
};

const cube_right_normals = [_][3]f32{
    [_]f32{ -1, 0, 0.000 },
    [_]f32{ -1, 0, 0.000 },
    [_]f32{ -1, 0, 0.000 },
    [_]f32{ -1, 0, 0.000 },
};

const cube_back_normals = [_][3]f32{
    // Bottom Right
    [_]f32{ 0, 0, 1.000 },
    [_]f32{ 0, 0, 1.000 },
    [_]f32{ 0, 0, 1.000 },
    [_]f32{ 0, 0, 1.000 },
};

const cube_top_normals = [_][3]f32{
    // Bottom Right
    [_]f32{ 0, -1, -0.000 },
    [_]f32{ 0, -1, -0.000 },
    [_]f32{ 0, -1, -0.000 },
    [_]f32{ 0, -1, -0.000 },
};

const cube_bottom_normals = [_][3]f32{
    [_]f32{ 0, 1, -0.000 },
    [_]f32{ 0, 1, -0.000 },
    [_]f32{ 0, 1, -0.000 },
    [_]f32{ 0, 1, -0.000 },
};

pub const normals = [_][3]f32{} ++
    cube_front_normals ++
    cube_left_normals ++
    cube_right_normals ++
    cube_back_normals ++
    cube_top_normals ++
    cube_bottom_normals;
