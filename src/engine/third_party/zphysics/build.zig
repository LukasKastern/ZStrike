const std = @import("std");

pub const Options = struct {
    use_double_precision: bool = false,
    enable_asserts: bool = false,
    enable_cross_platform_determinism: bool = true,
};

pub const Package = struct {
    options: Options,
    zphysics: *std.Build.Module,
    zphysics_options: *std.Build.Module,
    zphysics_c_cpp: *std.Build.CompileStep,

    pub fn link(pkg: Package, exe: *std.Build.CompileStep) void {
        exe.addIncludePath(.{ .path = thisDir() ++ "/libs/JoltC" });
        exe.linkLibrary(pkg.zphysics_c_cpp);
        exe.addModule("zphysics", pkg.zphysics);
        exe.addModule("zphysics_options", pkg.zphysics_options);
    }
};

pub fn package(
    b: *std.Build,
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,
    args: struct {
        options: Options = .{},
    },
) Package {
    const step = b.addOptions();
    step.addOption(bool, "use_double_precision", args.options.use_double_precision);
    step.addOption(bool, "enable_asserts", args.options.enable_asserts);
    step.addOption(bool, "enable_cross_platform_determinism", args.options.enable_cross_platform_determinism);

    const zphysics_options = step.createModule();

    const zphysics = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/src/zphysics.zig" },
        .dependencies = &.{
            .{ .name = "zphysics_options", .module = zphysics_options },
        },
    });

    const zphysics_c_cpp = b.addStaticLibrary(.{
        .name = "zphysics",
        .target = target,
        .optimize = optimize,
    });

    const abi = (std.zig.system.NativeTargetInfo.detect(target) catch unreachable).target.abi;

    zphysics_c_cpp.addIncludePath(.{ .path = thisDir() ++ "/libs" });
    zphysics_c_cpp.addIncludePath(.{ .path = thisDir() ++ "/libs/JoltC" });
    zphysics_c_cpp.linkLibC();
    if (abi != .msvc)
        zphysics_c_cpp.linkLibCpp();

    const flags = &.{
        "-std=c++17",
        if (abi != .msvc) "-DJPH_COMPILER_MINGW" else "",
        if (args.options.enable_cross_platform_determinism) "-DJPH_CROSS_PLATFORM_DETERMINISTIC" else "",
        if (args.options.use_double_precision) "-DJPH_DOUBLE_PRECISION" else "",
        if (args.options.enable_asserts or zphysics_c_cpp.optimize == .Debug) "-DJPH_ENABLE_ASSERTS" else "",
        "-fno-sanitize=undefined",
    };

    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/libs/JoltC/JoltPhysicsC.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/libs/JoltC/JoltPhysicsC_Extensions.cpp" }, .flags = flags });

    const src_dir = thisDir() ++ "/libs/Jolt";
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/AABBTree/AABBTreeBuilder.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/Color.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/Factory.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/IssueReporting.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/JobSystemThreadPool.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/JobSystemWithBarrier.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/LinearCurve.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/Memory.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/Profiler.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/RTTI.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/Semaphore.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/StringTools.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Core/TickCounter.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Geometry/ConvexHullBuilder.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Geometry/ConvexHullBuilder2D.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Geometry/Indexify.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Geometry/OrientedBox.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Math/UVec4.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Math/Vec3.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/ObjectStream/ObjectStream.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/ObjectStream/ObjectStreamBinaryIn.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/ObjectStream/ObjectStreamBinaryOut.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/ObjectStream/ObjectStreamIn.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/ObjectStream/ObjectStreamOut.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/ObjectStream/ObjectStreamTextIn.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/ObjectStream/ObjectStreamTextOut.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/ObjectStream/SerializableObject.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/ObjectStream/TypeDeclarations.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Body/Body.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Body/BodyAccess.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Body/BodyCreationSettings.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Body/BodyInterface.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Body/BodyManager.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Body/MassProperties.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Body/MotionProperties.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Character/Character.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Character/CharacterBase.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Character/CharacterVirtual.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/BroadPhase/BroadPhase.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/BroadPhase/BroadPhaseBruteForce.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/BroadPhase/BroadPhaseQuadTree.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/BroadPhase/QuadTree.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/CastConvexVsTriangles.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/CastSphereVsTriangles.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/CollideConvexVsTriangles.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/CollideSphereVsTriangles.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/CollisionDispatch.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/CollisionGroup.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/GroupFilter.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/GroupFilterTable.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/ManifoldBetweenTwoFaces.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/NarrowPhaseQuery.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/NarrowPhaseStats.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/PhysicsMaterial.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/PhysicsMaterialSimple.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/BoxShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/CapsuleShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/CompoundShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/ConvexHullShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/ConvexShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/CylinderShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/DecoratedShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/HeightFieldShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/MeshShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/MutableCompoundShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/OffsetCenterOfMassShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/RotatedTranslatedShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/ScaledShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/Shape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/SphereShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/StaticCompoundShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/TaperedCapsuleShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/Shape/TriangleShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Collision/TransformedShape.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/ConeConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/Constraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/ConstraintManager.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/ContactConstraintManager.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/DistanceConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/FixedConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/GearConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/HingeConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/MotorSettings.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/PathConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/PathConstraintPath.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/PathConstraintPathHermite.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/PointConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/RackAndPinionConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/SixDOFConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/SliderConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/SwingTwistConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/TwoBodyConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Constraints/PulleyConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/DeterminismLog.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/IslandBuilder.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/LargeIslandSplitter.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/PhysicsScene.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/PhysicsSystem.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/PhysicsUpdateContext.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/PhysicsLock.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Ragdoll/Ragdoll.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/StateRecorderImpl.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/TrackedVehicleController.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/VehicleAntiRollBar.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/VehicleCollisionTester.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/VehicleConstraint.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/VehicleController.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/VehicleDifferential.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/VehicleEngine.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/VehicleTrack.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/VehicleTransmission.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/Wheel.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/WheeledVehicleController.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Physics/Vehicle/MotorcycleController.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/RegisterTypes.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Renderer/DebugRenderer.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Renderer/DebugRendererPlayback.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Renderer/DebugRendererRecorder.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Skeleton/SkeletalAnimation.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Skeleton/Skeleton.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Skeleton/SkeletonMapper.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/Skeleton/SkeletonPose.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/TriangleGrouper/TriangleGrouperClosestCentroid.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/TriangleGrouper/TriangleGrouperMorton.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/TriangleSplitter/TriangleSplitter.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/TriangleSplitter/TriangleSplitterBinning.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/TriangleSplitter/TriangleSplitterFixedLeafSize.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/TriangleSplitter/TriangleSplitterLongestAxis.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/TriangleSplitter/TriangleSplitterMean.cpp" }, .flags = flags });
    zphysics_c_cpp.addCSourceFile(.{ .file = .{ .path = src_dir ++ "/TriangleSplitter/TriangleSplitterMorton.cpp" }, .flags = flags });

    return .{
        .options = args.options,
        .zphysics = zphysics,
        .zphysics_options = zphysics_options,
        .zphysics_c_cpp = zphysics_c_cpp,
    };
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const test_step = b.step("test", "Run zphysics tests");
    test_step.dependOn(runTests(b, optimize, target));
}

pub fn runTests(
    b: *std.Build,
    optimize: std.builtin.Mode,
    target: std.zig.CrossTarget,
) *std.Build.Step {
    const parent_step = b.allocator.create(std.Build.Step) catch @panic("OOM");
    parent_step.* = std.Build.Step.init(.{ .id = .custom, .name = "zphysics-tests", .owner = b });

    const test0 = testStep(b, "zphysics-tests-f32", optimize, target, .{ .use_double_precision = false });
    //const test1 = testStep(b, "zphysics-tests-f64", optimize, target, .{ .use_double_precision = true });

    parent_step.dependOn(&test0.step);
    //parent_step.dependOn(&test1.step);

    return parent_step;
}

fn testStep(
    b: *std.Build,
    name: []const u8,
    optimize: std.builtin.Mode,
    target: std.zig.CrossTarget,
    options: Options,
) *std.Build.RunStep {
    const test_exe = b.addTest(.{
        .name = name,
        .root_source_file = .{ .path = thisDir() ++ "/src/zphysics.zig" },
        .target = target,
        .optimize = optimize,
    });

    const abi = (std.zig.system.NativeTargetInfo.detect(target) catch unreachable).target.abi;

    test_exe.addCSourceFile(.{
        .file = .{ .path = thisDir() ++ "/libs/JoltC/JoltPhysicsC_Test}s..flags = c" },
        .flags = &.{
            "-std=c11",
            if (abi != .msvc) "-DJPH_COMPILER_MINGW" else "",
            if (options.use_double_precision) "-DJPH_DOUBLE_PRECISION" else "",
            if (options.enable_asserts or optimize == .Debug) "-DJPH_ENABLE_ASSERTS" else "",
            if (options.enable_cross_platform_determinism) "-DJPH_CROSS_PLATFORM_DETERMINISTIC" else "",
            "-fno-sanitize=undefined",
        },
    });

    const zphysics_pkg = package(b, target, optimize, .{ .options = options });
    zphysics_pkg.link(test_exe);

    test_exe.addModule("zphysics_options", zphysics_pkg.zphysics_options);

    return b.addRunArtifact(test_exe);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
