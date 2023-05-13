const std = @import("std");

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

/// Creates a named section in the binary, mapping concrete types to
/// monotonically increasing keys of integer or enum type.
/// The value associated with a type may be assigned at runtime, and queried
/// with the key assigned to that concrete type at `comptime`.
pub fn TypeMap(comptime name: []const u8, comptime TKey: type, comptime Value: type) type {
    const index_info = @typeInfo(TKey);
    const TInt = switch (index_info) {
        .Int => TKey,
        .Enum => |t| if (t.is_exhaustive)
            @compileError("TKey enum must be non-exhaustive")
        else
            t.tag_type,
        else => @compileError("TKey must be an enum or integer type"),
    };
    return struct {
        const Int = TInt;
        const Key = TKey;
        const Head = TypeMapPair(name, Value, void);
        const Tail = TypeMapTail(name, Value);
        const Ptr = TPtr(Value);
        const ptr_size = @sizeOf(Ptr);

        /// Returns the unique Key bound to type `T`.
        pub fn key(comptime T: type) Key {
            const Pair = TypeMapPair(name, Value, T);
            return ptrToKey(Pair.ptr());
        }

        /// Returns the value associated with type `T` for which `k == key(T)`.
        pub fn get(k: Key) Value {
            return (keyToPtr(k).*)();
        }

        /// Sets the value associated with type `T`, and
        /// returns the unique Key bound to type `T`.
        pub fn set(comptime Type: type, value: Value) Key {
            const Pair = TypeMapPair(name, Value, Type);
            Pair.set(value);
            return ptrToKey(Pair.ptr());
        }

        /// Returns the number of types/keys/values stored in the map.
        pub fn len() usize {
            return ptrToInt(Tail.ptr());
        }

        fn intToKey(i: Int) Key {
            return switch (index_info) {
                .Int => i,
                .Enum => @intToEnum(Key, i),
                else => unreachable,
            };
        }

        fn intToPtr(i: Int) Ptr {
            std.debug.assert(i < len());
            return Head.ptr() + i;
        }

        fn keyToInt(k: Key) Int {
            return switch (index_info) {
                .Int => k,
                .Enum => @enumToInt(k),
                else => unreachable,
            };
        }

        pub fn keyToPtr(k: Key) Ptr {
            return intToPtr(keyToInt(k));
        }

        fn ptrToIndex(p: Ptr) usize {
            return (@ptrToInt(p) - @ptrToInt(Head.ptr())) / ptr_size;
        }

        fn ptrToInt(p: Ptr) Int {
            return @truncate(Int, ptrToIndex(p));
        }

        fn ptrToKey(p: Ptr) Key {
            return intToKey(ptrToInt(p));
        }
    };
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

fn TGet(comptime Value: type) type {
    return fn () callconv(.C) Value;
}

fn TPtr(comptime Value: type) type {
    return *const TGet(Value);
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

// TODO: other platforms may require a different section name format
const section_prefix = "__DATA,";

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

fn TypeMapPair(
    comptime map_name: []const u8,
    comptime Value: type,
    comptime Type: type,
) type {
    const comptimePrint = std.fmt.comptimePrint;
    const Hash = std.hash.Fnv1a_64;
    const type_name = @typeName(Type);
    const type_hash = Hash.hash(type_name);
    const type_id = comptimePrint("{X}", .{type_hash});
    const export_name = map_name ++ type_id;
    @compileLog(export_name);
    // const type_id = type_name;
    return struct {
        const Ptr = TPtr(Value);
        comptime {
            @export(get, .{
                .name = export_name,
                .linkage = .Strong,
                .section = section_prefix ++ map_name ++ "$a",
            });
        }
        var _value: Value = undefined;
        fn get() callconv(.C) Value {
            return _value;
        }
        fn set(value: Value) void {
            _value = value;
        }
        fn ptr() Ptr {
            return &get;
        }
    };
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

fn TypeMapTail(
    comptime map_name: []const u8,
    comptime Value: type,
) type {
    return struct {
        const Ptr = TPtr(Value);
        comptime {
            @export(get, .{
                .name = map_name ++ ".tail",
                .linkage = .Strong,
                .section = section_prefix ++ map_name ++ "$z",
            });
        }
        fn get() callconv(.C) Value {
            unreachable;
        }
        fn ptr() Ptr {
            return &get;
        }
    };
}

////////////////////////////////////////////////////////////////////////////////

test "TypeMap(usize, u32)" {
    const print = std.debug.print;
    const Type = std.builtin.Type;
    const Map = TypeMap("coolness", usize, u32);

    print("\n", .{});
    print("    Map.key(void): {}\n", .{Map.key(void)});
    print("    Map.key(void): {}\n", .{Map.key(void)});
    print("    Map.key(bool): {}\n", .{Map.key(bool)});
    print("    Map.key(Type): {}\n", .{Map.key(Type)});
    print("    Map.len(): {}\n", .{Map.len()});

    print("\n", .{});
    print("    Map.set(void, 0): {}\n", .{Map.set(void, 10)});
    print("    Map.set(void, 0): {}\n", .{Map.set(void, 10)});
    print("    Map.set(bool, 1): {}\n", .{Map.set(bool, 11)});
    print("    Map.set(Type, 2): {}\n", .{Map.set(Type, 12)});
    print("    Map.len(): {}\n", .{Map.len()});

    print("\n", .{});
    print("    Map.get(0): {}\n", .{Map.get(0)});
    print("    Map.get(0): {}\n", .{Map.get(0)});
    print("    Map.get(1): {}\n", .{Map.get(1)});
    print("    Map.get(2): {}\n", .{Map.get(2)});
    print("    Map.len(): {}\n", .{Map.len()});

    const expectEqual = std.testing.expectEqual;
    try expectEqual(@as(usize, 0), Map.key(void));
    try expectEqual(@as(usize, 0), Map.key(void));
    try expectEqual(@as(usize, 1), Map.key(bool));
    try expectEqual(@as(usize, 1), Map.key(bool));
    try expectEqual(@as(usize, 2), Map.key(Type));
    try expectEqual(@as(usize, 2), Map.key(Type));
    try expectEqual(@as(usize, 3), Map.len());

    try expectEqual(@as(u32, 10), Map.get(0));
    try expectEqual(@as(u32, 10), Map.get(0));
    try expectEqual(@as(u32, 11), Map.get(1));
    try expectEqual(@as(u32, 11), Map.get(1));
    try expectEqual(@as(u32, 12), Map.get(2));
    try expectEqual(@as(u32, 12), Map.get(2));
    try expectEqual(@as(usize, 3), Map.len());
}
