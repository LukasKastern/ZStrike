const std = @import("std");
const ecs = @import("zflecs");

const Renderer = @import("../../renderer.zig");

const Core = @import("../../core.zig");

const zmesh = @import("zmesh");
const zwin32 = @import("zwin32");

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
    ps_file_handle: Core.FileStreaming.FileHandle,
    vs_file_handle: Core.FileStreaming.FileHandle,

    did_start_uploading: bool,
};

fn import(self: *AssetImporting.Importer, operation: *AssetImporting.Operation, file_path: []const u8) bool {
    var operation_data = operation.allocator.create(OperationData) catch {
        return false;
    };

    operation_data.did_start_uploading = false;

    var file_streaming = ecs.get_mut(operation.world, ecs.id(operation.world, Core.FileStreaming), Core.FileStreaming).?;

    var extension = std.fs.path.extension(file_path);
    var path_without_extension = file_path[0..(file_path.len - extension.len)];

    var temp_path_buffer = operation.allocator.alloc(u8, path_without_extension.len + 7) catch {
        return false;
    };

    std.mem.copy(u8, temp_path_buffer, path_without_extension);

    {
        std.mem.copy(u8, temp_path_buffer[path_without_extension.len..], ".ps.cso");

        operation_data.ps_file_handle = file_streaming.loadFile(temp_path_buffer, operation.allocator) catch {
            return false;
        };
    }

    {
        std.mem.copy(u8, temp_path_buffer[path_without_extension.len..], ".vs.cso");

        operation_data.vs_file_handle = file_streaming.loadFile(temp_path_buffer, operation.allocator) catch {
            return false;
        };
    }

    operation_data.importer = @fieldParentPtr(Self, "importer", self);

    operation.importer_data = @as(*anyopaque, @ptrCast(operation_data));

    return true;
}

fn finishImport(self: *AssetImporting.Importer, operation: *AssetImporting.Operation) void {
    _ = @fieldParentPtr(Self, "importer", self);

    var file_streaming = ecs.get_mut(operation.world, ecs.id(operation.world, Core.FileStreaming), Core.FileStreaming).?;
    var operation_data = @as(*OperationData, @ptrCast(@alignCast(operation.importer_data)));
    file_streaming.freeHandle(operation_data.ps_file_handle);
    file_streaming.freeHandle(operation_data.vs_file_handle);
}

fn stepImport(self: *AssetImporting.Importer, operation: *AssetImporting.Operation) ?AssetImporting.ImportResult {
    _ = @fieldParentPtr(Self, "importer", self);

    var file_streaming = ecs.get_mut(operation.world, ecs.id(operation.world, Core.FileStreaming), Core.FileStreaming).?;
    var operation_data = @as(*OperationData, @ptrCast(@alignCast(operation.importer_data)));

    var vs_file_data: []u8 = undefined;
    var ps_file_data: []u8 = undefined;

    var vs_load_result = file_streaming.getLoadStatus(operation_data.vs_file_handle, &vs_file_data);
    var ps_load_result = file_streaming.getLoadStatus(operation_data.ps_file_handle, &ps_file_data);

    if (vs_load_result == .Loading or ps_load_result == .Loading) {
        return null;
    }

    if (vs_load_result != .Success) {
        operation.error_string = "failed to load vertex shader";
        return .ImportFailed;
    }

    if (vs_load_result != .Success) {
        operation.error_string = "failed to load pixexl shader";
        return .ImportFailed;
    }

    if (!operation_data.did_start_uploading) {
        operation_data.did_start_uploading = true;
        _ = ecs.set(operation.world, operation.entity, Renderer.UploadResource, .{
            .resource_data = .{
                .Shader = .{ .ps = ps_file_data, .vs = vs_file_data },
            },
        });
    } else {
        var resource_ready_component = ecs.get(operation.world, operation.entity, Renderer.ResourceReady);
        var is_still_uploading = ecs.get(operation.world, operation.entity, Renderer.UploadResource);

        if (resource_ready_component != null) {
            return .Success;
        } else if (is_still_uploading == null) {
            operation.error_string = "uploading shader failed";
            return .ImportFailed;
        }
    }

    return null;
}
