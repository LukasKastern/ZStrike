const std = @import("std");
const ecs = @import("zflecs");

pub const ImportResult = enum {
    Success,
    ImportFailed,
};

pub const Importer = struct {
    // Invoked by the AssetStorage when a new asset should be imported.
    // Use the attached Operation ptr to report the status of the import.
    import_asset: *const fn (self: *Importer, operation: *Operation, file_path: []const u8) bool,

    // Called every time the AssetStorage ticks. During this time it's safe to invoke methods on the Operations.
    step_import: *const fn (self: *Importer, operation: *Operation) ?ImportResult,

    // Invoked once an operation returns a valid ImportResult via step_import
    finish_import: *const fn (self: *Importer, operation: *Operation) void,

    deinit: *const fn (self: *Importer) void,
};

pub const ImporterCollection = struct {
    const Importers = [8]?*Importer;

    extension_to_importers: std.array_hash_map.StringArrayHashMap(Importers),
    all_importers: [128]?*Importer,

    pub fn addImporter(collection: *ImporterCollection, importer: *Importer, extensions: []const []const u8) void {
        for (&collection.all_importers) |*importer_slot| {
            if (importer_slot.* == null) {
                importer_slot.* = importer;
                break;
            }
        }

        next_ext: for (extensions) |extension| {
            var importers = collection.extension_to_importers.getOrPut(extension) catch @panic("OOM");

            if (!importers.found_existing) {
                for (importers.value_ptr) |*importer_slot| {
                    importer_slot.* = null;
                }
            }

            for (importers.value_ptr) |*importer_slot| {
                if (importer_slot.* == null) {
                    importer_slot.* = importer;
                    continue :next_ext;
                }
            }

            @panic("Out of importer slots");
        }
    }
};

pub const ImportStatus = enum {
    Loading,
    Loaded,
    Failed,
};

pub const Operation = struct {

    // Field that can be used by the importer to attach custom data to the operation.
    importer_data: *anyopaque,

    // Arena allocator that is valid while the operation is running.
    // TODO: Make this an actual arena (lukas).
    allocator: std.mem.Allocator,

    entity: ecs.entity_t,

    world: *ecs.world_t,

    error_string: []const u8,
};

const OperationSlot = struct {
    version: usize,
    in_use: bool,
    importer: *Importer,
    operation: Operation,
    path: []const u8,

    arena: std.heap.ArenaAllocator,
};

operation_slots: std.ArrayList(OperationSlot),
active_operations: std.ArrayList(usize),
available_operation_slots: std.ArrayList(usize),
importer_collection: ImporterCollection,

allocator: std.mem.Allocator,
world: *ecs.world_t,

const Self = @This();

const MaxNumOperations = 1024;

pub fn init(allocator: std.mem.Allocator, world: *ecs.world_t) !Self {
    return .{
        .allocator = allocator,
        .world = world,
        .operation_slots = try std.ArrayList(OperationSlot).initCapacity(allocator, MaxNumOperations),
        .active_operations = try std.ArrayList(usize).initCapacity(allocator, MaxNumOperations),
        .available_operation_slots = try std.ArrayList(usize).initCapacity(allocator, MaxNumOperations),
        .importer_collection = .{ .extension_to_importers = std.array_hash_map.StringArrayHashMap(ImporterCollection.Importers).init(allocator), .all_importers = [_]?*Importer{null} ** 128 },
    };
}

pub fn deinit(self: *Self) void {
    self.flushActiveOperations();
    std.debug.assert(self.active_operations.items.len == 0);

    for (self.importer_collection.all_importers) |importer_maybe| {
        if (importer_maybe) |importer| {
            importer.deinit(importer);
        }
    }

    for (self.operation_slots.items) |slot| {
        slot.arena.deinit();
    }

    self.operation_slots.deinit();
    self.active_operations.deinit();
    self.available_operation_slots.deinit();
    self.importer_collection.extension_to_importers.deinit();
}

pub fn flushActiveOperations(self: *Self) void {
    while (self.active_operations.items.len > 0) {
        self.tickOperations();
    }
}

pub fn tickOperations(self: *Self) void {
    var operation_idx: isize = 0;
    while (operation_idx < self.active_operations.items.len) : (operation_idx += 1) {
        var active_operation_idx = self.active_operations.items[@as(usize, @intCast(operation_idx))];
        var operation_slot = &self.operation_slots.items[active_operation_idx];
        std.debug.assert(operation_slot.in_use);

        var result_maybe = operation_slot.importer.step_import(operation_slot.importer, &operation_slot.operation);

        if (result_maybe) |result| {
            operation_slot.importer.finish_import(operation_slot.importer, &operation_slot.operation);

            var status: ImportStatus = if (result == .Success) .Loaded else .Failed;
            _ = ecs.set(
                self.world,
                operation_slot.operation.entity,
                ImportStatus,
                status,
            );

            operation_slot.version += 1;
            operation_slot.in_use = false;

            self.available_operation_slots.appendAssumeCapacity(active_operation_idx);
            _ = self.active_operations.swapRemove(@as(usize, @intCast(operation_idx)));

            operation_idx -= 1;

            if (status == .Loaded) {
                std.log.info("[AssetImporting] Imported {s} successfully", .{operation_slot.path});
            } else {
                if (operation_slot.operation.error_string.len > 0) {
                    std.log.info("[AssetImporting] Failed to import {s}. Error={s}", .{ operation_slot.path, operation_slot.operation.error_string });
                } else {
                    std.log.info("[AssetImporting] Failed to import {s}.", .{operation_slot.path});
                }
            }
        }
    }
}

pub fn import(self: *Self, entity: ecs.entity_t, path: []const u8) !void {
    var operation_slot_idx: usize = undefined;
    if (self.available_operation_slots.items.len > 0) {
        operation_slot_idx = self.available_operation_slots.pop();
    } else {
        operation_slot_idx = self.operation_slots.items.len;
        var slot = try self.operation_slots.addOne();

        slot.in_use = false;
        slot.version = 1;
        slot.arena = std.heap.ArenaAllocator.init(self.allocator);
    }

    var operation_slot = &self.operation_slots.items[operation_slot_idx];
    std.debug.assert(!operation_slot.in_use);

    operation_slot.in_use = true;
    operation_slot.version += 1;

    _ = operation_slot.arena.reset(.retain_capacity);

    operation_slot.operation = .{
        .world = self.world,
        .entity = entity,
        .allocator = operation_slot.arena.allocator(),
        .importer_data = undefined,
        .error_string = "",
    };

    var ext = std.fs.path.extension(path);
    var importers_maybe = self.importer_collection.extension_to_importers.get(ext);

    var importer = blk: {
        if (importers_maybe) |importers| {
            for (importers) |importer_maybe| {
                if (importer_maybe) |importer| {
                    if (importer.import_asset(importer, &operation_slot.operation, path)) {
                        break :blk importer;
                    }
                }
            }
        } else {
            return error.AssetTypeNotSupported;
        }

        return error.AssetTypeNotSupported;
    };
    operation_slot.path = path;

    operation_slot.importer = importer;
    self.active_operations.appendAssumeCapacity(operation_slot_idx);
    std.log.info("[AssetImporting] Start Importing {s}", .{path});
}

pub fn loadAsset(world: *ecs.world_t, path: []const u8) ecs.entity_t {
    var asset_streaming = ecs.get_mut(world, ecs.id(world, Self), Self).?;

    var asset = ecs.new_entity(world, "");
    _ = ecs.set(world, asset, ImportStatus, .Loading);

    asset_streaming.import(asset, path) catch {
        std.log.err("[AssetImporting] Failed to import {s}", .{path});
        _ = ecs.set(world, asset, ImportStatus, .Failed);
    };

    return asset;
}
