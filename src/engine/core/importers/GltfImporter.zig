const std = @import("std");
const ecs = @import("zflecs");

const Renderer = @import("../../renderer.zig");
const Core = @import("../../core.zig");

const zmesh = @import("zmesh");

const AssetImporting = Core.AssetImporting;

const Self = @This();

importer: AssetImporting.Importer,
allocator: std.mem.Allocator,
world: *ecs.world_t,

pub fn init(persistent_allocator: std.mem.Allocator, world: *ecs.world_t) !*Self {
    var self = try persistent_allocator.create(Self);
    self.* = .{
        .importer = .{
            .import_asset = import,
            .step_import = stepImport,
            .deinit = deinit,
            .finish_import = finishImport,
        },
        .allocator = persistent_allocator,
        .world = world,
    };
    return self;
}

pub fn deinit(importer: *AssetImporting.Importer) void {
    var self = @fieldParentPtr(Self, "importer", importer);
    self.allocator.destroy(self);
}

const OperationData = struct {
    importer: *Self,
    file_handle: Core.FileStreaming.FileHandle,
};

fn import(self: *AssetImporting.Importer, operation: *AssetImporting.Operation, file_path: []const u8) bool {
    var operation_data = operation.allocator.create(OperationData) catch {
        return false;
    };

    var file_streaming = ecs.get_mut(operation.world, ecs.id(operation.world, Core.FileStreaming), Core.FileStreaming).?;
    operation_data.file_handle = file_streaming.loadFile(file_path, operation.allocator) catch {
        return false;
    };

    operation_data.importer = @fieldParentPtr(Self, "importer", self);

    operation.importer_data = @as(*anyopaque, @ptrCast(operation_data));
    return true;
}

fn finishImport(importer: *AssetImporting.Importer, operation: *AssetImporting.Operation) void {
    _ = @fieldParentPtr(Self, "importer", importer);

    var file_streaming = ecs.get_mut(operation.world, ecs.id(operation.world, Core.FileStreaming), Core.FileStreaming).?;
    var operation_data = @as(*OperationData, @ptrCast(@alignCast(operation.importer_data)));

    file_streaming.freeHandle(operation_data.file_handle);
}

fn stepImport(importer: *AssetImporting.Importer, operation: *AssetImporting.Operation) ?AssetImporting.ImportResult {
    var self = @fieldParentPtr(Self, "importer", importer);

    var file_streaming = ecs.get_mut(operation.world, ecs.id(operation.world, Core.FileStreaming), Core.FileStreaming).?;
    var operation_data = @as(*OperationData, @ptrCast(@alignCast(operation.importer_data)));

    var file_data: []u8 = undefined;
    var result = file_streaming.getLoadStatus(operation_data.file_handle, &file_data);

    switch (result) {
        .Loading => {
            return null;
        },
        .Success => {},
        else => {
            return .ImportFailed;
        },
    }

    var gltf_data = zmesh.io.parseFromMemory(file_data) catch @panic("Failed to parse gltf asset");
    defer zmesh.io.freeData(gltf_data);

    const mesh = &gltf_data.meshes.?[0];
    const prim = &mesh.primitives[0];

    const num_vertices: u32 = @as(u32, @intCast(prim.attributes[0].data.count));
    const num_indices: u32 = @as(u32, @intCast(prim.indices.?.count));

    var temp_indices = std.ArrayList(u32).init(operation.allocator);
    var positions = std.ArrayList([3]f32).init(operation.allocator);
    var normals = std.ArrayList([3]f32).init(operation.allocator);
    var texcoords0 = std.ArrayList([2]f32).init(operation.allocator);

    zmesh.io.appendMeshPrimitive(
        gltf_data,
        0,
        0,
        &temp_indices,
        &positions,
        &normals,
        &texcoords0,
        null,
    ) catch @panic("Failed to append mesh primitives");

    std.debug.assert(positions.items.len == normals.items.len);
    std.debug.assert(texcoords0.items.len == texcoords0.items.len);

    var vertices = self.allocator.alloc(Renderer.Mesh.Vertex, num_vertices) catch @panic("OOM");
    var indices = self.allocator.alloc(u32, num_indices) catch @panic("OOM");
    std.mem.copy(u32, indices, temp_indices.items);

    for (vertices, normals.items, positions.items, texcoords0.items) |*vertex, normal, pos, tex_coord| {
        vertex.* = .{ .pos = pos, .normal = normal, .uv = tex_coord };
    }

    _ = ecs.set(operation.world, operation.entity, Renderer.Mesh, .{
        .vertices = vertices,
        .indices = indices,
        .allocator = self.allocator,
    });

    _ = ecs.set(
        operation.world,
        operation.entity,
        Renderer.UploadResource,
        .{
            .resource_data = .{ .Mesh = {} },
        },
    );

    return .Success;
}
