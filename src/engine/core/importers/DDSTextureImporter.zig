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
render_state_query: *ecs.query_t,

pub fn init(persistent_allocator: std.mem.Allocator, world: *ecs.world_t) !*Self {
    ecs.COMPONENT(world, Renderer.DX12RenderState);

    var render_state_query_desc: ecs.query_desc_t = .{};
    render_state_query_desc.filter.terms[0] = .{
        .id = ecs.id(world, Renderer.DX12RenderState),
    };

    var render_state_query = ecs.query_init(world, &render_state_query_desc) catch @panic("Failed to create mesh upload query");

    var self = try persistent_allocator.create(Self);
    self.* = .{
        .importer = .{
            .import_asset = import,
            .step_import = stepImport,
            .deinit = deinit,
            .finish_import = finishImport,
        },
        .allocator = persistent_allocator,
        .render_state_query = render_state_query,
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

    state: enum {
        LoadingFile,
        UploadingResource,
    },
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
    operation_data.state = .LoadingFile;

    return true;
}

fn finishImport(self: *AssetImporting.Importer, operation: *AssetImporting.Operation) void {
    _ = @fieldParentPtr(Self, "importer", self);

    var file_streaming = ecs.get_mut(operation.world, ecs.id(operation.world, Core.FileStreaming), Core.FileStreaming).?;
    var operation_data = @as(*OperationData, @ptrCast(@alignCast(operation.importer_data)));
    file_streaming.freeHandle(operation_data.file_handle);
}

fn stepImport(self: *AssetImporting.Importer, operation: *AssetImporting.Operation) ?AssetImporting.ImportResult {
    var importer = @fieldParentPtr(Self, "importer", self);

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
            operation.error_string = "reading file failed";
            return .ImportFailed;
        },
    }

    if (operation_data.state == .LoadingFile) {
        var iter = ecs.query_iter(importer.world, importer.render_state_query);

        var render_state_maybe: ?*Renderer.DX12RenderState = null;
        while (ecs.query_next(&iter)) {
            var render_state_array = ecs.field(&iter, Renderer.DX12RenderState, 1).?;
            if (render_state_array.len > 0) {
                render_state_maybe = &render_state_array[0];
            }
        }

        // Wait for render state to be ready.
        if (render_state_maybe == null) {
            return null;
        }

        operation_data.state = .UploadingResource;

        var device = render_state_maybe.?.gctx.device;

        var sub_resources = std.ArrayList(zwin32.d3d12.SUBRESOURCE_DATA).init(operation.allocator);
        var image_info = zwin32.dds_loader.loadTextureFromMemory(file_data, operation.allocator, device, 0, &sub_resources) catch {
            operation.error_string = "parsing dds info failed";
            return .ImportFailed;
        };

        _ = ecs.set(operation.world, operation.entity, Renderer.UploadResource, .{
            .resource_data = .{
                .Texture = .{
                    .format = image_info.format,
                    .width = image_info.width,
                    .height = image_info.height,
                    .num_mip_level = image_info.mip_map_count,
                    .texture_memory = file_data,
                    .sub_resources = sub_resources,
                },
            },
        });

        return null;
    } else {
        var resource_ready_component = ecs.get(operation.world, operation.entity, Renderer.ResourceReady);
        var is_still_uploading = ecs.get(operation.world, operation.entity, Renderer.UploadResource);

        if (resource_ready_component != null) {
            return .Success;
        } else if (is_still_uploading == null) {
            operation.error_string = "uploading texture failed";
            return .ImportFailed;
        } else {
            return null;
        }
    }
}
