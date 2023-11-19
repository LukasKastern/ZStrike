const std = @import("std");
const windows = std.os.windows;

const Application = @import("../application.zig");
const ApplicationError = Application.ApplicationError;
const CreateWindowError = Application.CreateWindowError;

const WindowMode = Application.WindowMode;
const WindowConfig = Application.WindowConfig;
const WindowEvent = Application.WindowEvent;

const Core = @import("../Core.zig");
const SystemCollection = @import("../system_collection.zig");

const Self = @This();

const ecs = @import("zflecs");

const WindowClassName = "default";

const Platform = struct {
    pub fn isIconic(hwnd: windows.HWND) bool {
        return IsIconic(hwnd) != 0;
    }

    pub extern "user32" fn IsIconic(hwnd: Handle) callconv(windows.WINAPI) windows.BOOL;

    pub const SUBCLASSPROC = *const fn (hwnd: windows.HWND, uMsg: windows.UINT, wParam: windows.WPARAM, lParam: windows.LPARAM, uIdSubClass: *windows.UINT, dwRefData: *windows.DWORD) callconv(windows.WINAPI) windows.LRESULT;

    pub extern "Comctl32" fn SetWindowSubclass(hwnd: windows.HWND, pfnSubclass: SUBCLASSPROC, uIdSubclass: windows.UINT, wdRefData: *windows.DWORD) callconv(windows.WINAPI) windows.BOOL;

    pub extern "Winmm" fn timeBeginPeriod(uPeriod: windows.UINT) callconv(windows.WINAPI) windows.LRESULT;

    pub extern "Ole32" fn CoInitialize(reserved: ?windows.LPVOID) callconv(windows.WINAPI) windows.HRESULT;

    pub extern "User32" fn GetWindowRect(hwnd: windows.HWND, outRect: *windows.RECT) callconv(windows.WINAPI) windows.BOOL;
    pub extern "User32" fn SetCursorPos(x: c_int, y: c_int) callconv(windows.WINAPI) windows.BOOL;
    pub extern "User32" fn GetCursorPos(point: *windows.POINT) callconv(windows.WINAPI) windows.BOOL;
    pub extern "User32" fn ScreenToClient(hwnd: windows.HWND, point: *windows.POINT) callconv(windows.WINAPI) windows.BOOL;

    pub extern "User32" fn ClipCursor(rect: ?*windows.RECT) callconv(windows.WINAPI) windows.BOOL;

    pub extern "User32" fn ShowCursor(value: windows.BOOL) callconv(windows.WINAPI) c_int;

    pub const RAWINPUTDEVICE = extern struct {
        usUsagePage: windows.USHORT,
        usUsage: windows.USHORT,
        dwFlags: windows.DWORD,
        hwndTarget: windows.HWND,
    };

    pub const RIDEV_INPUTSINK = 0x00000100;
    pub const HID_USAGE_PAGE_GENERIC = 0x01;
    pub const HID_USAGE_GENERIC_MOUSE = 0x02;
    pub const RID_INPUT = 0x10000003;
    pub const RIM_TYPEMOUSE = 0;
    pub const RIM_TYPEKEYBOARD = 1;
    pub const RIM_TYPEHID = 2;

    pub extern "User32" fn RegisterRawInputDevices(inputDevices: [*c]RAWINPUTDEVICE, uiNumDevices: windows.UINT, cbSize: windows.UINT) callconv(windows.WINAPI) windows.BOOL;

    pub const RAWINPUTHEADER = extern struct {
        dwType: windows.DWORD,
        dwSize: windows.DWORD,
        hDevice: windows.HANDLE,
        wParam: windows.WPARAM,
    };

    pub const RAWMOUSE = extern struct {
        usFlags: windows.USHORT,
        DUMMYUNIONNAME: extern union {
            ulButtons: windows.ULONG,
            DUMMYSTRUCTNAME: extern struct {
                usButtonFlags: windows.USHORT,
                usButtonData: windows.USHORT,
            },
        },
        ulRawButtons: windows.ULONG,
        lLastX: windows.LONG,
        lLastY: windows.LONG,
        ulExtraInformation: windows.ULONG,
    };

    pub const RAWKEYBOARD = extern struct {
        MakeCode: windows.USHORT,
        Flags: windows.USHORT,
        Reserved: windows.USHORT,
        VKey: windows.USHORT,
        Message: windows.UINT,
        ExtraInformation: windows.ULONG,
    };

    pub const RAWHID = extern struct {
        dwSizeHid: windows.DWORD,
        dwCount: windows.DWORD,
        bRawData: [1]windows.BYTE,
    };

    pub const RAWINPUT = extern struct {
        header: RAWINPUTHEADER,
        data: extern union {
            mouse: RAWMOUSE,
            keyboard: RAWKEYBOARD,
            hid: RAWHID,
        },
    };

    pub extern "User32" fn GetRawInputData(
        hRawInput: windows.LPARAM,
        uiCommand: windows.UINT,
        pData: windows.PVOID,
        pcbSize: *windows.UINT,
        cbSizeHeader: windows.UINT,
    ) callconv(windows.WINAPI) windows.UINT;

    pub extern "Kernel32" fn SetThreadPriority(hThread: Handle, priority: c_int) callconv(windows.WINAPI) windows.BOOL;
    pub extern "Kernel32" fn GetCurrentThread() callconv(windows.WINAPI) Handle;

    pub const registerClass = windows.user32.registerClassExA;
    pub const createWindow = windows.user32.createWindowExA;
    pub const showWindow = windows.user32.showWindow;
    pub const getModuleHandle = windows.kernel32.GetModuleHandleW;
    pub const defWindowProcA = windows.user32.DefWindowProcA;
    pub const peekMessage = windows.user32.PeekMessageA;
    pub const translateMessage = windows.user32.translateMessage;
    pub const dispatchMessage = windows.user32.dispatchMessageA;
    pub const updateWindow = windows.user32.updateWindow;
    pub const destroyWindow = windows.user32.destroyWindow;
    pub const getLastError = windows.kernel32.GetLastError;

    pub const setCursorPos = SetCursorPos;
    pub const getWindowRect = GetWindowRect;
    pub const showCursor = ShowCursor;
    pub const setThreadPriority = SetThreadPriority;
    pub const getCurrentThread = GetCurrentThread;

    pub const WindowClass = windows.user32.WNDCLASSEXA;
    pub const Handle = windows.HWND;
    pub const HInstance = windows.HINSTANCE;
    pub const Message = windows.user32.MSG;

    pub const WS_OVERLAPPEDWINDOW = windows.user32.WS_OVERLAPPEDWINDOW;

    pub const SW_MAXIMIZE = windows.user32.SW_MAXIMIZE;
    pub const SW_SHOWMINIMIZED = windows.user32.SW_SHOWMINIMIZED;

    pub const WM_SETFOCUS = windows.user32.WM_SETFOCUS;
    pub const WM_KILLFOCUS = windows.user32.WM_KILLFOCUS;

    pub const WM_INPUT = windows.user32.WM_INPUT;
    pub const WM_MOUSEMOVE = windows.user32.WM_MOUSEMOVE;
    pub const WM_LBUTTONDOWN = windows.user32.WM_LBUTTONDOWN;
    pub const WM_RBUTTONDOWN = windows.user32.WM_RBUTTONDOWN;

    pub const WM_LBUTTONUP = windows.user32.WM_LBUTTONUP;
    pub const WM_RBUTTONUP = windows.user32.WM_RBUTTONUP;

    pub const WM_KEYUP = windows.user32.WM_KEYUP;
    pub const WM_KEYDOWN = windows.user32.WM_KEYDOWN;
    pub const WM_DESTROY = windows.user32.WM_DESTROY;
    pub const WM_CLOSE = windows.user32.WM_CLOSE;
    pub const WM_QUIT = windows.user32.WM_QUIT;
};

pub const PlatformKeyCodes = enum(u8) {
    LButton = 0x1,
    RButton = 0x2,

    A = 65,
    D = 68,
    W = 87,
    S = 83,
    G = 0x47,
    Q = 0x51,
    E = 0x45,
    Shift = 0x10,
    Space = 0x20,

    _,
};

fn DefWindowProcA(hWnd: windows.HWND, Msg: windows.UINT, wParam: windows.WPARAM, lParam: windows.LPARAM, uIdOfSubclass: *windows.UINT, dwRefData: *windows.DWORD) callconv(windows.WINAPI) windows.LRESULT {
    _ = uIdOfSubclass;

    var event_queue = @as(*std.ArrayList(WindowEvent), @ptrCast(@alignCast(dwRefData)));

    var raw_input_buffer: [512]u8 = undefined;

    switch (Msg) {
        Platform.WM_DESTROY => {
            std.log.info("WM_DESTROY", .{});
        },
        Platform.WM_CLOSE => {
            event_queue.append(.{
                .CloseRequested = {},
            }) catch @panic("OOM");

            std.log.info("WM_CLOSE", .{});
        },
        Platform.WM_QUIT => {
            std.log.info("WM_QUIT", .{});
        },
        Platform.WM_KEYDOWN => {
            event_queue.append(.{
                .KeyDown = .{
                    .key = @enumFromInt(@as(u8, @intCast(wParam))),
                },
            }) catch @panic("OOM");
        },
        Platform.WM_KEYUP => {
            event_queue.append(.{
                .KeyUp = .{
                    .key = @enumFromInt(@as(u8, @intCast(wParam))),
                },
            }) catch @panic("OOM");
        },
        Platform.WM_RBUTTONUP => {
            event_queue.append(.{
                .KeyUp = .{
                    .key = PlatformKeyCodes.RButton,
                },
            }) catch @panic("OOM");
        },
        Platform.WM_LBUTTONUP => {
            event_queue.append(.{
                .KeyUp = .{
                    .key = PlatformKeyCodes.LButton,
                },
            }) catch @panic("OOM");
        },
        Platform.WM_RBUTTONDOWN => {
            event_queue.append(.{
                .KeyDown = .{
                    .key = PlatformKeyCodes.RButton,
                },
            }) catch @panic("OOM");
        },
        Platform.WM_LBUTTONDOWN => {
            event_queue.append(.{
                .KeyDown = .{
                    .key = PlatformKeyCodes.LButton,
                },
            }) catch @panic("OOM");
        },
        Platform.WM_MOUSEMOVE => {},
        Platform.WM_SETFOCUS => {
            event_queue.append(.{
                .FocusChanged = .{
                    .has_focus = true,
                },
            }) catch @panic("OOM");
        },
        Platform.WM_KILLFOCUS => {
            event_queue.append(.{
                .FocusChanged = .{
                    .has_focus = false,
                },
            }) catch @panic("OOM");
        },
        Platform.WM_INPUT => {
            var data_size: windows.UINT = raw_input_buffer.len;
            var num_bytes_out = Platform.GetRawInputData(lParam, Platform.RID_INPUT, &raw_input_buffer, &data_size, @sizeOf(Platform.RAWINPUTHEADER));

            if (num_bytes_out != 0) {
                var raw_input: *Platform.RAWINPUT = @as(*Platform.RAWINPUT, @ptrCast(@alignCast(&raw_input_buffer)));
                if (raw_input.header.dwType == Platform.RIM_TYPEMOUSE) {
                    event_queue.append(.{
                        .MouseMove = .{
                            .move_x = raw_input.data.mouse.lLastX,
                            .move_y = raw_input.data.mouse.lLastY,
                        },
                    }) catch @panic("OOM");
                }
            }

            // std.log.info("RAW_INPUT", .{});
        },
        else => {
            return Platform.defWindowProcA(hWnd, Msg, wParam, lParam);
        },
    }

    return 0;
}

pub const NativeWindow = struct {
    handle: Platform.Handle,
    did_show_window: bool = false,
};

const WindowsApplicationState = struct {};

fn pumpMessages(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;
    var message: Platform.Message = undefined;

    while (Platform.peekMessage(&message, null, 0, 0, 1) != 0) {
        _ = Platform.translateMessage(&message);
        _ = Platform.dispatchMessage(&message);
    }

    var native_application_data = ecs.get(it.world, ecs.id(world, NativeApplicationData), NativeApplicationData).?;

    var window_iter = ecs.query_iter(it.world, native_application_data.window_query);
    var window_with_focus: ?*NativeWindow = null;
    var app_window_with_focus: ?Application.Window = null;

    var win_cursor: windows.POINT = undefined;
    _ = Platform.GetCursorPos(&win_cursor);

    while (ecs.query_next(&window_iter)) {
        var window_array = ecs.field(&window_iter, Application.Window, 1).?;
        var native_window_array = ecs.field(&window_iter, NativeWindow, 2).?;

        for (window_array, native_window_array) |*window, *native_window| {
            var win_rect: windows.RECT = undefined;
            _ = Platform.GetWindowRect(native_window.handle, &win_rect);

            window.size[0] = @floatFromInt(win_rect.right - win_rect.left);
            window.size[1] = @floatFromInt(win_rect.bottom - win_rect.top);

            // This remaps the world space cursor accounting for the titlebar and border.
            var cursor_rel_to_native = win_cursor;
            _ = Platform.ScreenToClient(native_window.handle, &cursor_rel_to_native);

            window.cursor_pos[0] = @floatFromInt(cursor_rel_to_native.x);
            window.cursor_pos[1] = @floatFromInt(cursor_rel_to_native.y);

            if (window.has_focus) {
                window_with_focus = native_window;
                app_window_with_focus = window.*;
            }
        }
    }

    if (window_with_focus) |window| {
        var app_window = app_window_with_focus.?;

        _ = Platform.ShowCursor(if (app_window.cursor_visible) windows.TRUE else windows.FALSE);

        var rect: windows.RECT = undefined;
        if (Platform.GetWindowRect(window.handle, &rect) != 0) {
            const clip_cursor_rect = if (app_window.cursor_mode == .Constrained) &rect else null;
            _ = Platform.ClipCursor(clip_cursor_rect);

            if (app_window.cursor_mode == .Locked) {
                var rect_width = rect.right - rect.left;
                var rect_height = rect.top - rect.bottom;

                _ = Platform.SetCursorPos(rect.left + @divTrunc(rect_width, 2), rect.bottom + @divTrunc(rect_height, 2));
            }
        }
    } else {
        // TODO: Do we even need to do this? Shouldn't windows handle this for us? (lukas)
        _ = Platform.ClipCursor(null);
        _ = Platform.ShowCursor(windows.TRUE);
    }
}

fn createWindows(it: *ecs.iter_t) callconv(.C) void {
    std.log.info("Create Windows", .{});

    var world = it.world;

    const allocator = ecs.get(it.world, ecs.id(world, Core.PersistentAllocator), Core.PersistentAllocator).?.value;

    const entity_array = ecs.field(it, ecs.entity_t, 0).?;
    const window_array = ecs.field(it, Application.Window, 1).?;

    var module_handle = Platform.getModuleHandle(null);
    var hinstance = @as(Platform.HInstance, @ptrCast(@alignCast(module_handle.?)));

    const TempNameBufferLen = 1024;
    var temp_name: [TempNameBufferLen]u8 = undefined;

    loop: for (entity_array, window_array) |entity, *window| {
        std.mem.copy(u8, &temp_name, window.title);
        temp_name[window.title.len] = 0;

        var event_queue = allocator.create(std.ArrayList(WindowEvent)) catch @panic("OOM");
        event_queue.* = std.ArrayList(WindowEvent).init(allocator);

        var window_handle = Platform.createWindow(0, "default", @as([*:0]const u8, @ptrCast(&temp_name)), Platform.WS_OVERLAPPEDWINDOW, 0, 0, 2560, 1440, null, null, hinstance, null) catch |e| {
            switch (e) {
                else => {
                    std.log.err("Failed to create window. Error={s}", .{@errorName(e)});
                    continue :loop;
                },
            }
        };

        if (Platform.SetWindowSubclass(window_handle, DefWindowProcA, 1, @as(*u32, @ptrCast(event_queue))) == 0) {
            std.log.err("Failed to setup window proc. Error={}", .{Platform.getLastError()});
            continue :loop;
        }

        _ = ecs.set(
            it.world,
            entity,
            NativeWindow,
            .{
                .handle = window_handle,
            },
        );

        window.event_queue = event_queue;

        var device = Platform.RAWINPUTDEVICE{
            .usUsagePage = Platform.HID_USAGE_PAGE_GENERIC,
            .usUsage = Platform.HID_USAGE_GENERIC_MOUSE,
            .dwFlags = Platform.RIDEV_INPUTSINK,
            .hwndTarget = window_handle,
        };

        _ = Platform.RegisterRawInputDevices(&device, 1, @sizeOf(@TypeOf(device)));
    }
}

fn destroyWindows(it: *ecs.iter_t) callconv(.C) void {
    std.log.info("Destroy Windows", .{});

    const entity_array = ecs.field(it, ecs.entity_t, 0).?;
    const window_array = ecs.field(it, Application.Window, 1).?;
    const native_window_array = ecs.field(it, NativeWindow, 2).?;

    for (entity_array, window_array, native_window_array) |entity, *window, native_window| {
        var allocator = window.event_queue.?.allocator;

        Platform.destroyWindow(native_window.handle) catch unreachable;
        window.event_queue.?.deinit();
        allocator.destroy(window.event_queue.?);
        window.event_queue = null;
        ecs.remove(it.world, entity, NativeWindow);
    }
}

const NativeApplicationData = struct {
    window_query: *ecs.query_t,
};

fn initPlatform() !void {
    if (Platform.CoInitialize(null) != 0) {
        @panic("CoInitialize failed");
    }

    _ = Platform.setThreadPriority(Platform.getCurrentThread(), 15);

    var module_handle = Platform.getModuleHandle(null);
    var hinstance = @as(Platform.HInstance, @ptrCast(@alignCast(module_handle.?)));

    // Initialize Window Class
    {
        var class = Platform.WindowClass{
            .style = 0,
            .lpfnWndProc = Platform.defWindowProcA,
            .hInstance = hinstance,
            .hIcon = null,
            .hCursor = null,
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = WindowClassName,
            .hIconSm = null,
        };

        _ = Platform.registerClass(&class) catch |e| {
            if (e != error.AlreadyExists) {
                std.log.err("Failed to register window class", .{});
                return error.InitializationFailed;
            }
        };
    }

    // Set highest available sleep precision
    {
        _ = Platform.timeBeginPeriod(1);
    }
}

pub fn preInitializePlatformModule(world: *ecs.world_t) void {
    initPlatform() catch @panic("Failed to initialize platform");
    ecs.COMPONENT(world, NativeWindow);
    ecs.COMPONENT(world, NativeApplicationData);
}

pub fn tickWindows(it: *ecs.iter_t) callconv(.C) void {
    var window_array = ecs.field(it, Application.Window, 1).?;
    var native_window_array = ecs.field(it, NativeWindow, 2).?;

    for (window_array, native_window_array) |window, *native_window| {
        if (!native_window.did_show_window) {
            native_window.did_show_window = true;
            var sw_mode: i32 = switch (window.startup_mode) {
                .FullScreen => Platform.SW_MAXIMIZE,
                .Minimized => Platform.SW_SHOWMINIMIZED,
            };

            _ = Platform.showWindow(native_window.handle, sw_mode);
        }
    }
}

pub fn initializePlatformModule(world: *ecs.world_t) void {
    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = pumpMessages;
        ecs.SYSTEM(world, "Pump Messages", ecs.OnUpdate, &system_desc);
    }

    var create_windows_description = ecs.observer_desc_t{
        .callback = createWindows,
        .filter = .{
            .terms = [_]ecs.term_t{
                .{
                    .id = ecs.id(world, Application.Window),
                },
                .{
                    .id = ecs.id(world, NativeWindow),
                    .oper = .Not,
                },
            } ++ [_]ecs.term_t{.{}} ** (ecs.TERM_DESC_CACHE_SIZE - 2),
        },
        .events = [_]ecs.entity_t{ecs.OnSet} ++ [_]ecs.entity_t{0} ** (ecs.OBSERVER_DESC_EVENT_COUNT_MAX - 1),
    };

    ecs.OBSERVER(world, "Create Native Windows", &create_windows_description);

    var destroy_windows_description = ecs.observer_desc_t{
        .callback = destroyWindows,
        .filter = .{
            .terms = [_]ecs.term_t{
                .{
                    .id = ecs.id(world, Application.Window),
                },
                .{
                    .id = ecs.id(world, NativeWindow),
                },
            } ++ [_]ecs.term_t{.{}} ** (ecs.TERM_DESC_CACHE_SIZE - 2),
        },
        .events = [_]ecs.entity_t{ecs.OnRemove} ++ [_]ecs.entity_t{0} ** (ecs.OBSERVER_DESC_EVENT_COUNT_MAX - 1),
    };

    ecs.OBSERVER(world, "Destroy Native Windows", &destroy_windows_description);

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(world, Application.Window) };
        system_desc.query.filter.terms[1] = .{ .id = ecs.id(world, Application.NativeWindow) };
        system_desc.callback = tickWindows;
        ecs.SYSTEM(world, "Tick Windows", ecs.PostFrame, &system_desc);
    }

    var window_query_desc: ecs.query_desc_t = .{};
    window_query_desc.filter.terms[0] = .{ .id = ecs.id(world, Application.Window) };
    window_query_desc.filter.terms[1] = .{ .id = ecs.id(world, Application.NativeWindow) };

    var window_query = ecs.query_init(world, &window_query_desc) catch @panic("Failed to create window query");

    ecs.setSingleton(world, NativeApplicationData, .{ .window_query = window_query });
}
