const std = @import("std");
const assert = std.debug.assert;
const mem = @import("memory.zig");
pub const zcgltf = @import("zcgltf.zig");

pub fn parseAndLoadFile(pathname: [:0]const u8) zcgltf.Error!*zcgltf.Data {
    const options = zcgltf.Options{
        .memory = .{
            .alloc_func = mem.zmeshAllocUser,
            .free_func = mem.zmeshFreeUser,
        },
    };

    const data = try zcgltf.parseFile(options, pathname);
    errdefer zcgltf.free(data);

    try zcgltf.loadBuffers(options, data, pathname);

    return data;
}

pub fn parseFromMemory(data: []const u8) zcgltf.Error!*zcgltf.Data {
    const options = zcgltf.Options{
        .memory = .{
            .alloc_func = mem.zmeshAllocUser,
            .free_func = mem.zmeshFreeUser,
        },
    };

    const parsed_data = try zcgltf.parse(options, data);
    errdefer zcgltf.free(parsed_data);

    if (parsed_data.buffers_count > 0 and parsed_data.buffers.?[0].data == null and parsed_data.buffers.?[0].uri == null and parsed_data.bin != null) {
        if (parsed_data.bin_size < parsed_data.buffers.?[0].size) {
            return error.DataTooShort;
        }

        parsed_data.buffers.?[0].data = @constCast(parsed_data.bin);
        parsed_data.buffers.?[0].data_free_method = zcgltf.DataFreeMethod.none;
    }

    for (parsed_data.buffers.?[0..parsed_data.buffers_count]) |*buffer| {
        if (buffer.data != null) {
            continue;
        }

        if (buffer.uri == null) {
            continue;
        }

        var uri = std.mem.span(buffer.uri.?);

        if (std.mem.startsWith(u8, uri, "data:")) {
            std.log.info("URI: {s}", .{uri});

            var comma = std.mem.indexOf(u8, uri, ",") orelse return error.InvalidGltf;
            var result = zcgltf.cgltf_load_buffer_base64(&options, buffer.size, uri[comma + 1 ..], @ptrCast(?*?*zcgltf.Data, &buffer.data));

            if (result != zcgltf.Result.success) {
                std.log.err("Failed to load buffers from uri={s}, base64, error={}", .{ uri, result });
                return error.InvalidGltf;
            }

            buffer.data_free_method = .memory_free;
        } else {
            std.log.err("Only single file gltfs is supported when parsing from an in memory buffer.", .{});
            return error.InvalidGltf;
        }
    }

    return parsed_data;
}

pub fn freeData(data: *zcgltf.Data) void {
    zcgltf.free(data);
}

pub fn appendMeshPrimitive(
    data: *zcgltf.Data,
    mesh_index: u32,
    prim_index: u32,
    indices: *std.ArrayList(u32),
    positions: *std.ArrayList([3]f32),
    normals: ?*std.ArrayList([3]f32),
    texcoords0: ?*std.ArrayList([2]f32),
    tangents: ?*std.ArrayList([4]f32),
) !void {
    assert(mesh_index < data.meshes_count);
    assert(prim_index < data.meshes.?[mesh_index].primitives_count);

    const mesh = &data.meshes.?[mesh_index];
    const prim = &mesh.primitives[prim_index];

    const num_vertices: u32 = @intCast(u32, prim.attributes[0].data.count);
    const num_indices: u32 = @intCast(u32, prim.indices.?.count);

    // Indices.
    {
        try indices.ensureTotalCapacity(indices.items.len + num_indices);

        const accessor = prim.indices.?;
        const buffer_view = accessor.buffer_view.?;

        assert(accessor.stride == buffer_view.stride or buffer_view.stride == 0);
        // assert(accessor.stride * accessor.count == buffer_view.size);
        assert(buffer_view.buffer.data != null);

        const data_addr = @alignCast(4, @ptrCast([*]const u8, buffer_view.buffer.data) +
            accessor.offset + buffer_view.offset);

        if (accessor.stride == 1) {
            assert(accessor.component_type == .r_8u);
            const src = @ptrCast([*]const u8, data_addr);
            var i: u32 = 0;
            while (i < num_indices) : (i += 1) {
                indices.appendAssumeCapacity(src[i]);
            }
        } else if (accessor.stride == 2) {
            assert(accessor.component_type == .r_16u);
            const src = @ptrCast([*]const u16, data_addr);
            var i: u32 = 0;
            while (i < num_indices) : (i += 1) {
                indices.appendAssumeCapacity(src[i]);
            }
        } else if (accessor.stride == 4) {
            assert(accessor.component_type == .r_32u);
            const src = @ptrCast([*]const u32, data_addr);
            var i: u32 = 0;
            while (i < num_indices) : (i += 1) {
                indices.appendAssumeCapacity(src[i]);
            }
        } else {
            unreachable;
        }
    }

    // Attributes.
    {
        const attributes = prim.attributes[0..prim.attributes_count];
        for (attributes) |attrib| {
            const accessor = attrib.data;
            assert(accessor.component_type == .r_32f);

            const buffer_view = accessor.buffer_view.?;
            assert(buffer_view.buffer.data != null);

            assert(accessor.stride == buffer_view.stride or buffer_view.stride == 0);
            // assert(accessor.stride * accessor.count == buffer_view.size);

            const data_addr = @ptrCast([*]const u8, buffer_view.buffer.data) +
                accessor.offset + buffer_view.offset;

            if (attrib.type == .position) {
                assert(accessor.type == .vec3);
                const slice = @ptrCast([*]const [3]f32, @alignCast(4, data_addr))[0..num_vertices];
                try positions.appendSlice(slice);
            } else if (attrib.type == .normal) {
                if (normals) |n| {
                    assert(accessor.type == .vec3);
                    const slice = @ptrCast([*]const [3]f32, @alignCast(4, data_addr))[0..num_vertices];
                    try n.appendSlice(slice);
                }
            } else if (attrib.type == .texcoord) {
                if (texcoords0) |tc| {
                    assert(accessor.type == .vec2);
                    const slice = @ptrCast([*]const [2]f32, @alignCast(4, data_addr))[0..num_vertices];
                    try tc.appendSlice(slice);
                }
            } else if (attrib.type == .tangent) {
                if (tangents) |tan| {
                    assert(accessor.type == .vec4);
                    const slice = @ptrCast([*]const [4]f32, @alignCast(4, data_addr))[0..num_vertices];
                    try tan.appendSlice(slice);
                }
            }
        }
    }
}
