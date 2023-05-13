const std = @import("std");
const zwin32 = @import("third_party/zwin32/build.zig");
const zd3d12 = @import("third_party/zd3d12/build.zig");
const zmesh = @import("third_party/zmesh/build.zig");
const zmath = @import("third_party/zmath/build.zig");
const zflecs = @import("third_party/zflecs/build.zig");
const zphysics = @import("third_party/zphysics/build.zig");

pub const ShaderToCompile = struct {
    source_file: []const u8,

    output_name: []const u8,

    define: []const u8,

    vs_entry_point: []const u8,

    ps_entry_point: []const u8,
};

pub const Config = struct {
    // Directory that will be copied into the binaries content_dir.
    game_content_dir: []const u8,

    shaders: []const ShaderToCompile,
};

const content_dir = "assets/";

pub const Package = struct {
    config: Config,

    engine: *std.Build.Module,
    imgui: *std.Build.CompileStep,
    zd3d12: zd3d12.Package,
    zwin32: zwin32.Package,
    zmesh: zmesh.Package,
    zflecs: zflecs.Package,
    zmath: zmath.Package,
    zphysics: zphysics.Package,
    options: *std.Build.Step.Options,
    install_content_step: *std.Build.Step.InstallDir,

    pub fn link(pkg: Package, exe: *std.Build.CompileStep) void {
        exe.linkLibrary(pkg.imgui);
        exe.addIncludePath(thisDir() ++ "/third_party/imgui/");

        pkg.zd3d12.link(exe);
        pkg.zwin32.link(
            exe,
            .{
                .d3d12 = true,
            },
        );
        pkg.zmesh.link(exe);
        pkg.zflecs.link(exe);
        pkg.zmath.link(exe);
        pkg.zphysics.link(exe);
        exe.linkLibC();

        exe.addModule("Engine", pkg.engine);
        exe.addOptions("build_options", pkg.options);
    }

    pub fn install(pkg: Package, install_step: *std.build.Step.InstallArtifact) void {
        install_step.step.dependOn(&pkg.install_content_step.step);
    }

    fn makeDxcCmd(
        b: *std.Build,
        dxc_step: *std.Build.Step,
        comptime input_path: []const u8,
        comptime entry_point: []const u8,
        comptime output_filename: []const u8,
        comptime profile: []const u8,
        comptime define: []const u8,
    ) void {
        const shader_ver = "6_6";
        // const shader_dir = thisDir() ++ "/" ++ content_dir ++ "";

        comptime var shader_dir = std.fs.path.dirname(input_path).?;

        const dxc_command = [9][]const u8{
            if (@import("builtin").target.os.tag == .windows)
                thisDir() ++ "/third_party/zwin32/bin/x64/dxc.exe"
            else if (@import("builtin").target.os.tag == .linux)
                thisDir() ++ "/third_party/zwin32/bin/x64/dxc",
            input_path,
            "/E " ++ entry_point,
            "/Fo " ++ shader_dir ++ "/" ++ output_filename,
            "/T " ++ profile ++ "_" ++ shader_ver,
            if (define.len == 0) "" else "/D " ++ define,
            "/WX",
            "/Ges",
            "/O3",
        };

        const cmd_step = b.addSystemCommand(&dxc_command);
        if (@import("builtin").target.os.tag == .linux)
            cmd_step.setEnvironmentVariable("LD_LIBRARY_PATH", thisDir() ++ "/../../zwin32/bin/x64");
        dxc_step.dependOn(&cmd_step.step);

        // @compileLog("Writing to: " ++ shader_dir ++ "/" ++ output_filename);
    }
};

pub fn package(
    b: *std.Build,
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,
    comptime args: struct {
        options: Config,
        deps: struct {} = .{},
    },
) Package {
    const options = b.addOptions();
    options.addOption([]const u8, "content_dir", content_dir);

    const zwin32_pkg = zwin32.package(b, target, optimize, .{});
    const zd3d12_pkg = zd3d12.package(b, target, optimize, .{
        .options = .{
            .enable_debug_layer = false,
            .enable_gbv = false,
        },
        .deps = .{ .zwin32 = zwin32_pkg.zwin32 },
    });
    const zmesh_pkg = zmesh.package(b, target, optimize, .{});
    const zmath_pkg = zmath.package(b, target, optimize, .{});
    const zflecs_pkg = zflecs.package(b, target, optimize, .{});
    const zphysics_pkg = zphysics.package(b, target, optimize, .{});

    const imgui = b.addStaticLibrary(.{
        .name = "imgui",
        .target = target,
        .optimize = optimize,
    });

    imgui.linkLibC();
    imgui.linkLibCpp();
    imgui.linkSystemLibraryName("imm32");

    imgui.addIncludePath(thisDir() ++ "/third_party/");
    imgui.addCSourceFile(thisDir() ++ "/third_party/imgui/imgui.cpp", &.{""});
    imgui.addCSourceFile(thisDir() ++ "/third_party/imgui/imgui_widgets.cpp", &.{""});
    imgui.addCSourceFile(thisDir() ++ "/third_party/imgui/imgui_tables.cpp", &.{""});
    imgui.addCSourceFile(thisDir() ++ "/third_party/imgui/imgui_draw.cpp", &.{""});
    imgui.addCSourceFile(thisDir() ++ "/third_party/imgui/imgui_demo.cpp", &.{""});
    imgui.addCSourceFile(thisDir() ++ "/third_party/imgui/cimgui.cpp", &.{""});

    var engine = b.addModule(
        "engine",
        .{
            .source_file = .{
                .path = thisDir() ++ "/Engine.zig",
            },
            .dependencies = &[_]std.Build.ModuleDependency{
                .{
                    .name = "zflecs",
                    .module = zflecs_pkg.zflecs,
                },
                .{
                    .name = "zmath",
                    .module = zmath_pkg.zmath,
                },
                .{
                    .name = "zmesh",
                    .module = zmesh_pkg.zmesh,
                },
                .{
                    .name = "zwin32",
                    .module = zwin32_pkg.zwin32,
                },
                .{
                    .name = "zd3d12",
                    .module = zd3d12_pkg.zd3d12,
                },
                .{
                    .name = "build_options",
                    .module = options.createModule(),
                },
                .{ .name = "zphysics", .module = zphysics_pkg.zphysics },
            },
        },
    );

    // Install game content.
    const install_content_step = b.addInstallDirectory(.{
        .source_dir = args.options.game_content_dir,
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/" ++ content_dir,
    });

    const install_engine_content_step = b.addInstallDirectory(.{
        .source_dir = thisDir() ++ "/engine_content",
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/" ++ content_dir,
    });

    install_content_step.step.dependOn(&install_engine_content_step.step);

    const dxc_step = b.step("minimal_d3d12-dxc", "Build shaders for 'minimal d3d12' demo");

    const all_shaders = args.options.shaders ++ [_]ShaderToCompile{
        .{
            .source_file = thisDir() ++ "/engine_content/common.hlsl",
            .output_name = "imgui",
            .define = "PSO__IMGUI",
            .vs_entry_point = "vsImGui",
            .ps_entry_point = "psImGui",
        },
    };

    inline for (all_shaders) |shader| {
        Package.makeDxcCmd(
            b,
            dxc_step,
            shader.source_file,
            shader.vs_entry_point,
            shader.output_name ++ ".vs.cso",
            "vs",
            shader.define,
        );

        Package.makeDxcCmd(
            b,
            dxc_step,
            shader.source_file,
            shader.ps_entry_point,
            shader.output_name ++ ".ps.cso",
            "ps",
            shader.define,
        );
    }

    install_content_step.step.dependOn(dxc_step);

    return .{
        .config = args.options,
        .imgui = imgui,
        .zd3d12 = zd3d12_pkg,
        .zwin32 = zwin32_pkg,
        .zmesh = zmesh_pkg,
        .zflecs = zflecs_pkg,
        .zmath = zmath_pkg,
        .engine = engine,
        .zphysics = zphysics_pkg,
        .options = options,
        .install_content_step = install_content_step,
    };
}

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    var engine_pkg = package(b, target, optimize, .{
        .options = .{
            .game_content_dir = thisDir() ++ "/assets/",
            .shaders = &[_]ShaderToCompile{},
        },
    });

    var tests = b.addTest(.{
        .name = "test-engine",
        .root_source_file = .{ .path = thisDir() ++ "/Engine.zig" },
        .target = target,
        .optimize = optimize,
    });

    engine_pkg.link(tests);

    var install_artifact = b.addInstallArtifact(tests);
    engine_pkg.install(install_artifact);

    // tests.addOptionss("build_options")

    var run_step = b.addRunArtifact(tests);
    run_step.step.dependOn(&install_artifact.step);

    const test_step = b.step("test", "Run engine tests");
    test_step.dependOn(&run_step.step);

    const build_step = b.step("build-engine", "Build engine");
    build_step.dependOn(&install_artifact.step);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
