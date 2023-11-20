const std = @import("std");
const engine = @import("src/engine/build.zig");
const enet_build = @import("src/engine/third_party/enet/build.zig");

const content_dir = "assets/";

const WorldType = @import("src/engine/system_collection.zig").WorldType;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
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

    // Enet
    var enet_lib = enet_build.buildLibrary(b, optimize, target);
    comptime var enet_dir = enet_build.thisDir();
    var enet = b.addModule("enet", .{ .source_file = .{ .path = enet_dir ++ "/enet.zig" } });

    const client_exe = b.addExecutable(.{
        .name = "ZStrike",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    {
        client_exe.addModule("enet", enet);
        client_exe.linkLibrary(enet_lib);

        var client_options = b.addOptions();
        client_options.addOption(WorldType, "WorldType", .Client);
        client_exe.addOptions("game_options", client_options);
    }

    const server_exe = b.addExecutable(.{
        .name = "ZStrike-Server",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    {
        server_exe.addModule("enet", enet);
        server_exe.linkLibrary(enet_lib);

        var server_options = b.addOptions();
        server_options.addOption(WorldType, "WorldType", .Server);
        server_exe.addOptions("game_options", server_options);
    }

    var engine_pkg = engine.package(b, target, optimize, .{
        .options = .{
            .game_content_dir = thisDir() ++ "/assets/",
            .shaders = &[_]engine.ShaderToCompile{},
        },
    });
    engine_pkg.link(client_exe);
    engine_pkg.link(server_exe);

    var client_install_artifact = b.addInstallArtifact(client_exe, .{});
    var server_install_artifact = b.addInstallArtifact(server_exe, .{});
    engine_pkg.install(client_install_artifact);

    var build_client_exe_step = b.step("client", "Build Client Exe");
    build_client_exe_step.dependOn(&client_install_artifact.step);
    build_client_exe_step.dependOn(&server_install_artifact.step);

    var run_exe_step = b.addRunArtifact(client_exe);
    run_exe_step.step.dependOn(build_client_exe_step);

    var run_client_step = b.step("run-client", "Run Client");
    run_client_step.dependOn(&run_exe_step.step);
}

fn buildShaders(b: *std.Build) *std.Build.Step {
    const dxc_step = b.step("minimal_d3d12-dxc", "Build shaders for 'minimal d3d12' demo");

    makeDxcCmd(b, dxc_step, "assets/shaders/minimal_d3d12.hlsl", "vsMain", "minimal_d3d12.vs.cso", "vs", "");
    makeDxcCmd(b, dxc_step, "assets/shaders/minimal_d3d12.hlsl", "psMain", "minimal_d3d12.ps.cso", "ps", "");

    makeDxcCmd(
        b,
        dxc_step,
        "assets/shaders/common.hlsl",
        "vsImGui",
        "imgui.vs.cso",
        "vs",
        "PSO__IMGUI",
    );
    makeDxcCmd(
        b,
        dxc_step,
        "assets/shaders/common.hlsl",
        "psImGui",
        "imgui.ps.cso",
        "ps",
        "PSO__IMGUI",
    );

    makeDxcCmd(
        b,
        dxc_step,
        "assets/shaders/bindless.hlsl",
        "vsMeshPbr",
        "mesh_pbr.vs.cso",
        "vs",
        "PSO__MESH_PBR",
    );
    makeDxcCmd(
        b,
        dxc_step,
        "assets/shaders/bindless.hlsl",
        "psMeshPbr",
        "mesh_pbr.ps.cso",
        "ps",
        "PSO__MESH_PBR",
    );
    makeDxcCmd(
        b,
        dxc_step,
        "assets/shaders/bindless.hlsl",
        "psMeshPbrPrototype",
        "mesh_pbr_prototype.ps.cso",
        "ps",
        "PSO__MESH_PBR",
    );

    makeDxcCmd(
        b,
        dxc_step,
        "assets/shaders/bindless.hlsl",
        "vsMeshPbrPrototype",
        "mesh_pbr_prototype.vs.cso",
        "vs",
        "PSO__MESH_PBR",
    );

    return dxc_step;
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
    const shader_dir = thisDir() ++ "/" ++ content_dir ++ "shaders/";

    const dxc_command = [9][]const u8{
        if (@import("builtin").target.os.tag == .windows)
            thisDir() ++ "/libs/zig-gamedev/libs/zwin32/bin/x64/dxc.exe"
        else if (@import("builtin").target.os.tag == .linux)
            thisDir() ++ "/libs/zig-gamedev/libs/zwin32/bin/x64/dxc",
        thisDir() ++ "/" ++ input_path,
        "/E " ++ entry_point,
        "/Fo " ++ shader_dir ++ output_filename,
        "/T " ++ profile ++ "_" ++ shader_ver,
        if (define.len == 0) "" else "/D " ++ define,
        "/WX",
        "/Ges",
        "/O3",
    };

    const cmd_step = b.addSystemCommand(&dxc_command);
    if (@import("builtin").target.os.tag == .linux)
        cmd_step.setEnvironmentVariable("LD_LIBRARY_PATH", thisDir() ++ "/../../libs/zwin32/bin/x64");
    dxc_step.dependOn(&cmd_step.step);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
