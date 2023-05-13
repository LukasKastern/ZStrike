const std = @import("std");
const ecs = @import("zflecs");

const Self = @This();

pub const FileHandle = struct {
    slot: usize,
    version: usize,
};

const FileLoadData = struct {
    path_backing_buffer: ?[]u8,

    version: usize,
    path: []const u8,
    allocator: std.mem.Allocator,
    in_use: bool,

    load_status: LoadStatus,
    out_data: ?[]u8,

    cancel: bool,
};

files: std.ArrayList(FileLoadData),
available_slots: std.ArrayList(usize),
loading_slots: std.ArrayList(usize),

allocator: std.mem.Allocator,

const DefaultFileLoadSlots = 2048;

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .files = try std.ArrayList(FileLoadData).initCapacity(allocator, DefaultFileLoadSlots),
        .available_slots = try std.ArrayList(usize).initCapacity(allocator, DefaultFileLoadSlots),
        .loading_slots = try std.ArrayList(usize).initCapacity(allocator, DefaultFileLoadSlots),
        .allocator = allocator,
    };
}

pub fn deinit(self: Self) void {
    // Make sure all files have been unloaded.
    std.debug.assert(self.available_slots.items.len == self.files.items.len);

    for (self.files.items) |file| {
        self.allocator.free(file.path_backing_buffer.?);
    }

    self.loading_slots.deinit();
    self.available_slots.deinit();
    self.files.deinit();
}

pub fn loadFile(self: *Self, path: []const u8, allocator: std.mem.Allocator) !FileHandle {
    var slot_idx: usize = undefined;
    if (self.available_slots.items.len > 0) {
        slot_idx = self.available_slots.pop();
        std.debug.assert(!self.files.items[slot_idx].in_use);
    } else {
        slot_idx = self.files.items.len;
        _ = try self.files.addOne();
        self.files.items[slot_idx].path_backing_buffer = null;
    }

    var slot = &self.files.items[slot_idx];
    slot.in_use = true;

    if (slot.path_backing_buffer == null or slot.path_backing_buffer.?.len < path.len) {
        if (slot.path_backing_buffer) |old_backing_buffer| {
            slot.path_backing_buffer = try self.allocator.realloc(old_backing_buffer, path.len);
        } else {
            slot.path_backing_buffer = try self.allocator.alloc(u8, path.len);
        }
    }

    std.mem.copy(u8, slot.path_backing_buffer.?, path);
    slot.path = slot.path_backing_buffer.?[0..path.len];
    slot.version += 1;
    slot.allocator = allocator;
    slot.load_status = .Loading;

    try self.loading_slots.append(slot_idx);

    return .{ .slot = slot_idx, .version = slot.version };
}

pub fn freeHandle(self: *Self, handle: FileHandle) void {
    var slot_maybe = self.getFileFromHandle(handle);
    if (slot_maybe == null) {
        @panic("Trying to free an invalid file handle");
    }

    var slot = slot_maybe.?;

    if (slot.load_status == .Loading) {
        slot.cancel = true;
    } else {
        slot.in_use = false;
        slot.out_data = null;
        slot.load_status = .Success;
        slot.version += 1;
        self.available_slots.append(handle.slot) catch @panic("OOM");
    }
}

pub const LoadStatus = enum {
    Loading,
    InvalidHandle,
    FileNotFound,
    OutOfMemory,
    Success,
};

fn getFileFromHandle(self: Self, file_handle: FileHandle) ?*FileLoadData {
    if (file_handle.slot >= self.files.items.len) {
        return null;
    }

    if (self.files.items[file_handle.slot].version != file_handle.version) {
        return null;
    }

    return &self.files.items[file_handle.slot];
}

// Returns the current load status of the operation associated with the handle.
pub fn getLoadStatus(self: Self, handle: FileHandle, out_file_data: *[]u8) LoadStatus {
    var slot_maybe = self.getFileFromHandle(handle);

    if (slot_maybe == null) {
        return .InvalidHandle;
    }

    var slot = slot_maybe.?;

    if (slot.load_status == .Success) {
        out_file_data.* = slot.out_data.?;
    }

    return slot.load_status;
}

pub fn tickFileStreaming(self: *Self) void {
    var i: isize = 0;
    while (i < self.loading_slots.items.len) : (i += 1) {
        var slot_idx = self.loading_slots.items[@intCast(usize, i)];
        var slot = &self.files.items[slot_idx];

        std.debug.assert(slot.in_use);

        defer {
            // If the file finished loading remove it from the loading_slots collection.
            if (slot.load_status != .Loading) {
                _ = self.loading_slots.swapRemove(@intCast(usize, i));
                i -= 1;

                if (slot.cancel) {
                    // If the loading operation got cancelled we have to free the slot now.
                    slot.in_use = false;
                    slot.out_data = null;
                    slot.load_status = .Success;
                    slot.version += 1;
                    self.available_slots.append(slot_idx) catch @panic("OOM");
                }
            }
        }

        var file = std.fs.cwd().openFile(slot.path, .{}) catch {
            slot.load_status = .FileNotFound;
            continue;
        };
        defer file.close();

        slot.out_data = file.readToEndAlloc(slot.allocator, 1024 * 1024 * 1024) catch {
            slot.load_status = .OutOfMemory;
            continue;
        };

        slot.load_status = .Success;
    }
}
