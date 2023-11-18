const RendererInitializationError = @import("../renderer.zig").RendererInitializationError;
const Renderer = @import("../renderer.zig");

const std = @import("std");

const zwin32 = @import("zwin32");
const w32 = zwin32.w32;
const d3d12 = zwin32.d3d12;
const zd3d12 = @import("zd3d12");
const zmesh = @import("zmesh");
const zm = @import("zmath");
const ecs = @import("zflecs");

const Application = @import("../application.zig");
const Core = @import("../Core.zig");

const GuiRendererDX12 = @import("GuiRendererDX12.zig");

const hrPanic = zwin32.hrPanic;
const hrPanicOnFail = zwin32.hrPanicOnFail;

const content_dir = @import("build_options").content_dir;

// Symbols needed by agility SDK
pub export const D3D12SDKVersion: u32 = 608;
pub export const D3D12SDKPath: [*:0]const u8 = ".\\d3d12\\";

const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    texcoords0: [2]f32,
    tangent: [4]f32,
};

const GPUMaterial = extern struct {
    base_color: u32,
    unused_: [3]u32 = [_]u32{
        0,
        0,
        0,
    },
};

const Self = @This();

const ResourceView = struct {
    resource: zd3d12.ResourceHandle,
    view: d3d12.CPU_DESCRIPTOR_HANDLE,
};

const Scene_Const = extern struct {
    world_to_clip: zm.Mat,
    camera_position: zm.F32x4,
    draw_mode: i32,
};

const Draw_Const = extern struct {
    object_to_world: zm.Mat,
    base_color_index: u32,
    ao_index: u32,
    metallic_roughness_index: u32,
    normal_index: u32,
};

const MaxNumInstances = 1200;

fn uploadTexture(render_state: *DX12RenderState, texture_to_upload: *UploadResource.UploadTextureData) !zd3d12.ResourceHandle {
    std.debug.assert(render_state.gctx.is_cmdlist_opened);

    var texture_desc = blk: {
        break :blk d3d12.RESOURCE_DESC.initTex2d(
            texture_to_upload.format,
            texture_to_upload.width,
            texture_to_upload.height,
            texture_to_upload.num_mip_level,
        );
    };

    const texture = try render_state.gctx.createCommittedResource(
        .DEFAULT,
        .{},
        &texture_desc,
        .{ .COPY_DEST = true },
        null,
    );
    texture_desc = render_state.gctx.lookupResource(texture).?.GetDesc();

    for (0..texture_to_upload.sub_resources.items.len) |index| {
        const subresource_index = @as(u32, @intCast(index));

        var layout: [1]d3d12.PLACED_SUBRESOURCE_FOOTPRINT = undefined;
        var num_rows: [1]u32 = undefined;
        var row_size_in_bytes: [1]u64 = undefined;
        var required_size: u64 = undefined;
        render_state.gctx.device.GetCopyableFootprints(
            &texture_desc,
            subresource_index,
            layout.len,
            0,
            &layout,
            &num_rows,
            &row_size_in_bytes,
            &required_size,
        );

        const upload = render_state.gctx.allocateUploadBufferRegion(u8, @as(u32, @intCast(required_size)));
        layout[0].Offset = upload.buffer_offset;

        var subresource = &texture_to_upload.sub_resources.items[subresource_index];
        var row: u32 = 0;

        const row_size_in_bytes_fixed = row_size_in_bytes[0];
        var cpu_slice_as_bytes = std.mem.sliceAsBytes(upload.cpu_slice);
        const subresource_slice = subresource.pData.?;
        while (row < num_rows[0]) : (row += 1) {
            const cpu_slice_begin = layout[0].Footprint.RowPitch * row;
            const cpu_slice_end = cpu_slice_begin + row_size_in_bytes_fixed;
            const subresource_slice_begin = row_size_in_bytes[0] * row;
            const subresource_slice_end = subresource_slice_begin + row_size_in_bytes_fixed;
            @memcpy(
                cpu_slice_as_bytes[cpu_slice_begin..cpu_slice_end],
                subresource_slice[subresource_slice_begin..subresource_slice_end],
            );
        }

        render_state.gctx.cmdlist.CopyTextureRegion(&.{
            .pResource = render_state.gctx.lookupResource(texture).?,
            .Type = .SUBRESOURCE_INDEX,
            .u = .{ .SubresourceIndex = subresource_index },
        }, 0, 0, 0, &.{
            .pResource = upload.buffer,
            .Type = .PLACED_FOOTPRINT,
            .u = .{ .PlacedFootprint = layout[0] },
        }, null);
    }

    return texture;
}

pub fn draw(it: *ecs.iter_t) callconv(.C) void {
    var render_state_array = ecs.field(it, DX12RenderState, 1).?;

    var frame_allocator = ecs.get(it.world, ecs.id(it.world, Core.FrameAllocator), Core.FrameAllocator).?;

    for (render_state_array) |*self| {
        const CameraData = struct { priority: isize, transform: zm.Mat };

        var camera_data: CameraData = .{
            .transform = zm.identity(),
            .priority = -1000,
        };
        // Find camera to use
        {
            var camera_it = ecs.query_iter(it.world, self.camera_query);
            while (ecs.query_next(&camera_it)) {
                var camera_array = ecs.field(&camera_it, Renderer.Camera, 1).?;
                var transform_array = ecs.field(&camera_it, Core.Transform.LocalToWorld, 2).?;

                for (camera_array, transform_array) |camera, transform| {
                    if (camera_data.priority < camera.priority) {
                        camera_data = .{
                            .priority = camera.priority,
                            .transform = transform.value,
                        };
                    }
                }
            }
        }

        self.gctx.beginFrame();

        // Upload resources
        {
            _ = ecs.defer_begin(it.world);
            defer _ = ecs.defer_end(it.world);

            var upload_query_it = ecs.query_iter(it.world, self.upload_resource_query);
            while (ecs.query_next(&upload_query_it)) {
                var entity_array = ecs.field(&upload_query_it, ecs.entity_t, 0).?;
                var upload_resource_array = ecs.field(&upload_query_it, UploadResource, 1).?;
                for (entity_array, upload_resource_array) |entity, *upload_resource| {
                    defer ecs.remove(it.world, entity, UploadResource);

                    switch (upload_resource.resource_data) {
                        .Texture => |*texture| {
                            var resource = uploadTexture(self, texture) catch {
                                std.log.err("Failed to upload texture format={}, x={}, y={}", .{ texture.format, texture.width, texture.height });
                                continue;
                            };

                            var dx12_gpu_texture = blk: {
                                const srv_allocation = self.gctx.allocatePersistentGpuDescriptors(1);
                                self.gctx.device.CreateShaderResourceView(
                                    self.gctx.lookupResource(resource).?,
                                    null,
                                    srv_allocation.cpu_handle,
                                );

                                self.gctx.addTransitionBarrier(resource, .{ .PIXEL_SHADER_RESOURCE = true });
                                self.gctx.flushResourceBarriers();

                                const t = DX12GPUTexture{
                                    .handle = resource,
                                    .persistent_descriptor = srv_allocation,
                                };

                                break :blk t;
                            };

                            _ = ecs.set(it.world, entity, DX12GPUTexture, dx12_gpu_texture);
                        },
                        .Mesh => {
                            var mesh = ecs.get(it.world, entity, Renderer.Mesh).?;
                            var gpu_mesh: DX12GPUMesh = undefined;

                            // var normals = cube.normals;
                            var all_vertices = std.ArrayList(Vertex).initCapacity(frame_allocator.value, mesh.vertices.len) catch @panic("OOM");
                            defer all_vertices.deinit();

                            for (mesh.vertices) |in_vertex| {
                                var vertex = Vertex{
                                    .position = in_vertex.pos,
                                    .normal = in_vertex.normal,
                                    .texcoords0 = in_vertex.uv,
                                    .tangent = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
                                };

                                all_vertices.appendAssumeCapacity(vertex);
                            }

                            gpu_mesh.vertices = blk: {
                                var vertex_buffer = self.gctx.createCommittedResource(
                                    .DEFAULT,
                                    .{},
                                    &d3d12.RESOURCE_DESC.initBuffer(all_vertices.items.len * @sizeOf(Vertex)),
                                    .{ .COPY_DEST = true },
                                    null,
                                ) catch |err| hrPanic(err);
                                const upload = self.gctx.allocateUploadBufferRegion(Vertex, @as(u32, @intCast(all_vertices.items.len)));
                                for (all_vertices.items, 0..) |vertex, i| {
                                    upload.cpu_slice[i] = vertex;
                                }
                                self.gctx.cmdlist.CopyBufferRegion(
                                    self.gctx.lookupResource(vertex_buffer).?,
                                    0,
                                    upload.buffer,
                                    upload.buffer_offset,
                                    upload.cpu_slice.len * @sizeOf(@TypeOf(upload.cpu_slice[0])),
                                );
                                self.gctx.addTransitionBarrier(vertex_buffer, .{ .VERTEX_AND_CONSTANT_BUFFER = true });
                                break :blk vertex_buffer;
                            };

                            gpu_mesh.num_indices = mesh.indices.len;
                            gpu_mesh.num_vertices = all_vertices.items.len;

                            gpu_mesh.indices = blk: {
                                var index_buffer = self.gctx.createCommittedResource(
                                    .DEFAULT,
                                    .{},
                                    &d3d12.RESOURCE_DESC.initBuffer(mesh.indices.len * @sizeOf(u32)),
                                    .{ .COPY_DEST = true },
                                    null,
                                ) catch |err| hrPanic(err);
                                const upload = self.gctx.allocateUploadBufferRegion(u32, @as(u32, @intCast(mesh.indices.len)));
                                for (mesh.indices, 0..) |index, i| {
                                    upload.cpu_slice[i] = index;
                                }
                                self.gctx.cmdlist.CopyBufferRegion(
                                    self.gctx.lookupResource(index_buffer).?,
                                    0,
                                    upload.buffer,
                                    upload.buffer_offset,
                                    upload.cpu_slice.len * @sizeOf(@TypeOf(upload.cpu_slice[0])),
                                );
                                self.gctx.addTransitionBarrier(index_buffer, .{ .INDEX_BUFFER = true });
                                break :blk index_buffer;
                            };

                            _ = ecs.set(it.world, entity, DX12GPUMesh, gpu_mesh);
                        },
                        .Shader => |*shader| {
                            var pso = blk: {
                                const input_layout_desc = [_]d3d12.INPUT_ELEMENT_DESC{
                                    d3d12.INPUT_ELEMENT_DESC.init("POSITION", 0, .R32G32B32_FLOAT, 0, 0, .PER_VERTEX_DATA, 0),
                                    d3d12.INPUT_ELEMENT_DESC.init("_Normal", 0, .R32G32B32_FLOAT, 0, 12, .PER_VERTEX_DATA, 0),
                                    d3d12.INPUT_ELEMENT_DESC.init("_Texcoords", 0, .R32G32_FLOAT, 0, 24, .PER_VERTEX_DATA, 0),
                                    d3d12.INPUT_ELEMENT_DESC.init("_Tangent", 0, .R32G32B32A32_FLOAT, 0, 32, .PER_VERTEX_DATA, 0),

                                    d3d12.INPUT_ELEMENT_DESC.init("_InstanceObjectToWorld", 0, .R32G32B32A32_FLOAT, 1, 0, .PER_INSTANCE_DATA, 1),
                                    d3d12.INPUT_ELEMENT_DESC.init("_InstanceObjectToWorld", 1, .R32G32B32A32_FLOAT, 1, 16, .PER_INSTANCE_DATA, 1),
                                    d3d12.INPUT_ELEMENT_DESC.init("_InstanceObjectToWorld", 2, .R32G32B32A32_FLOAT, 1, 32, .PER_INSTANCE_DATA, 1),
                                    d3d12.INPUT_ELEMENT_DESC.init("_InstanceObjectToWorld", 3, .R32G32B32A32_FLOAT, 1, 48, .PER_INSTANCE_DATA, 1),

                                    d3d12.INPUT_ELEMENT_DESC.init("_TextureSlots", 0, .R32G32_UINT, 2, 0, .PER_INSTANCE_DATA, 1),
                                    d3d12.INPUT_ELEMENT_DESC.init("_TextureSlots", 1, .R32G32_UINT, 2, 8, .PER_INSTANCE_DATA, 1),
                                };
                                var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
                                pso_desc.DSVFormat = .D32_FLOAT;
                                pso_desc.InputLayout = .{
                                    .pInputElementDescs = &input_layout_desc,
                                    .NumElements = input_layout_desc.len,
                                };
                                pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
                                pso_desc.NumRenderTargets = 1;
                                pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
                                pso_desc.PrimitiveTopologyType = .TRIANGLE;

                                break :blk self.gctx.createGraphicsShaderPipelineRsVsGsPsFromMemory(
                                    &pso_desc,
                                    shader.vs,
                                    shader.ps,
                                );
                            };

                            _ = ecs.set(it.world, entity, DX12GPUShader, .{
                                .pipeline = pso,
                            });
                        },
                    }

                    _ = ecs.set(it.world, entity, ResourceReady, .{ .dummy = 0 });
                }
            }
        }

        const back_buffer = self.gctx.getBackBuffer();
        self.gctx.addTransitionBarrier(back_buffer.resource_handle, .{ .RENDER_TARGET = true });
        self.gctx.flushResourceBarriers();

        self.gctx.cmdlist.OMSetRenderTargets(
            1,
            &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
            1,
            &self.depth_texture.view,
        );

        self.gctx.cmdlist.ClearRenderTargetView(back_buffer.descriptor_handle, &.{ 0.0, 0.0, 0.0, 0.0 }, 0, null);
        self.gctx.cmdlist.ClearDepthStencilView(self.depth_texture.view, .{ .DEPTH = true }, 1.0, 0, 0, null);

        // Draw
        {
            var draw_it = ecs.query_iter(it.world, self.mesh_draw_query);

            _ = ecs.defer_begin(it.world);
            defer _ = ecs.defer_end(it.world);

            var camera_pos = zm.util.getTranslationVec(camera_data.transform);
            var camera_rot = zm.util.getRotationQuat(camera_data.transform);

            var forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 0), zm.matFromQuat(camera_rot)));

            const cam_world_to_view = zm.lookToLh(
                camera_pos,
                forward,
                zm.f32x4(0.0, 1.0, 0.0, 0.0),
            );
            const cam_view_to_clip = zm.perspectiveFovLh(
                std.math.pi / 3.0,
                @as(f32, @floatFromInt(self.gctx.viewport_width)) / @as(f32, @floatFromInt(self.gctx.viewport_height)),
                0.1,
                100.0,
            );
            const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);

            while (ecs.query_next(&draw_it)) {
                var mesh_pair_id = ecs.field_id(&draw_it, 1);
                var shader_pair_id = ecs.field_id(&draw_it, 2);

                var render_transforms = ecs.field(&draw_it, Renderer.RenderTransform, 3).?;
                var material_array = ecs.field(&draw_it, Renderer.Material, 4).?;

                var gpu_mesh_ent = ecs.pair_second(mesh_pair_id);
                var gpu_shader_ent = ecs.pair_second(shader_pair_id);

                var maybe_gpu_mesh = ecs.get(it.world, gpu_mesh_ent, DX12GPUMesh);
                var maybe_gpu_shader = ecs.get(it.world, gpu_shader_ent, DX12GPUShader);

                if (maybe_gpu_mesh == null or maybe_gpu_shader == null) {
                    continue;
                }

                var gpu_mesh = maybe_gpu_mesh.?;
                var gpu_shader = maybe_gpu_shader.?;

                var instance_count = draw_it.count();

                self.gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
                self.gctx.cmdlist.IASetVertexBuffers(0, 1, &[_]d3d12.VERTEX_BUFFER_VIEW{.{
                    .BufferLocation = self.gctx.lookupResource(gpu_mesh.vertices).?.GetGPUVirtualAddress(),
                    .SizeInBytes = @as(u32, @intCast(self.gctx.getResourceSize(gpu_mesh.vertices))),
                    .StrideInBytes = @sizeOf(Vertex),
                }});

                // Set InstanceData
                {
                    const mem = self.gctx.allocateUploadMemory(Renderer.RenderTransform, @as(u32, @intCast(instance_count)));
                    std.mem.copy(Renderer.RenderTransform, mem.cpu_slice, render_transforms);

                    self.gctx.cmdlist.IASetVertexBuffers(1, 1, &[_]d3d12.VERTEX_BUFFER_VIEW{.{
                        .BufferLocation = mem.gpu_base,
                        .SizeInBytes = @as(u32, @intCast(@sizeOf(Renderer.RenderTransform) * instance_count)),
                        .StrideInBytes = @sizeOf(Renderer.RenderTransform),
                    }});
                }

                // Upload materials
                {
                    const mem = self.gctx.allocateUploadMemory(GPUMaterial, @as(u32, @intCast(instance_count)));

                    for (mem.cpu_slice, material_array) |*gpu_material, input_mat| {
                        if (input_mat.textures.base_color != 0) {
                            var texture_maybe = ecs.get(it.world, input_mat.textures.base_color, DX12GPUTexture);

                            if (texture_maybe) |texture| {
                                gpu_material.base_color = texture.persistent_descriptor.index;
                            } else {
                                gpu_material.base_color = 0;
                            }
                        }
                    }

                    // std.mem.copy(GPUMaterial, mem.cpu_slice, material_array);

                    self.gctx.cmdlist.IASetVertexBuffers(2, 1, &[_]d3d12.VERTEX_BUFFER_VIEW{.{
                        .BufferLocation = mem.gpu_base,
                        .SizeInBytes = @as(u32, @intCast(@sizeOf(GPUMaterial) * instance_count)),
                        .StrideInBytes = @sizeOf(GPUMaterial),
                    }});
                }

                self.gctx.cmdlist.IASetIndexBuffer(&.{
                    .BufferLocation = self.gctx.lookupResource(gpu_mesh.indices).?.GetGPUVirtualAddress(),
                    .SizeInBytes = @as(u32, @intCast(self.gctx.getResourceSize(gpu_mesh.indices))),
                    .Format = .R32_UINT,
                });

                self.gctx.setCurrentPipeline(gpu_shader.pipeline);

                // Set scene constants
                {
                    const mem = self.gctx.allocateUploadMemory(Scene_Const, 1);
                    mem.cpu_slice[0] = .{
                        .world_to_clip = zm.transpose(cam_world_to_clip),
                        .camera_position = camera_pos,
                        .draw_mode = 0,
                    };

                    self.gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);
                }

                // Draw cube.
                {
                    const object_to_world = zm.translation(@as(f32, @floatFromInt(1)) * 1.0, 0.0, 0.0); // zm.identity(); //zm.rotationY(@floatCast(f32, 0.25 * 5.0));

                    const mem = self.gctx.allocateUploadMemory(Draw_Const, 1);
                    mem.cpu_slice[0] = .{
                        .object_to_world = zm.transpose(object_to_world),
                        .base_color_index = 0, //self.mesh_textures[texture_base_color].persistent_descriptor.index,
                        .ao_index = 0, //demo.mesh_textures[texture_ao].persistent_descriptor.index,
                        .metallic_roughness_index = 0, // demo.mesh_textures[texture_metallic_roughness].persistent_descriptor.index,
                        .normal_index = 0, //demo.mesh_textures[texture_normal].persistent_descriptor.index,
                    };

                    self.gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);

                    // self.gctx.cmdlist.SetGraphicsRootDescriptorTable(2, blk: {
                    // const table = self.gctx.copyDescriptorsToGpuHeap(1, demo.irradiance_texture.view);
                    // _ = self.gctx.copyDescriptorsToGpuHeap(1, demo.prefiltered_env_texture.view);
                    // _ = self.gctx.copyDescriptorsToGpuHeap(1, demo.brdf_integration_texture.view);
                    // break :blk table;
                    // });

                    self.gctx.cmdlist.DrawIndexedInstanced(
                        @as(c_uint, @intCast(gpu_mesh.num_indices)),
                        @as(c_uint, @intCast(instance_count)),
                        0,
                        0,
                        0,
                    );
                }
            }
        }

        self.gui_renderer.draw(&self.gctx);

        self.gctx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATES.PRESENT);
        self.gctx.flushResourceBarriers();

        self.gctx.endFrame();
    }
}

pub const UploadResource = struct {
    const UploadTextureData = struct {
        format: zwin32.dxgi.FORMAT,
        width: u32,
        height: u32,
        num_mip_level: u32,
        texture_memory: []const u8,
        sub_resources: std.ArrayList(d3d12.SUBRESOURCE_DATA),
    };

    resource_data: union(enum) {
        Texture: UploadTextureData,
        Mesh: void,
        Shader: struct {
            vs: []const u8,
            ps: []const u8,
        },
    },
};

pub const ResourceReady = struct {
    dummy: u8,
};

pub const DX12RenderState = struct {
    start_time: i128,

    gctx: zd3d12.GraphicsContext,
    allocator: std.mem.Allocator,

    depth_texture: ResourceView,

    gui_renderer: GuiRendererDX12,

    mesh_upload_query: *ecs.query_t,
    // texture_upload_query: *ecs.query_t,

    mesh_draw_query: *ecs.query_t,

    upload_resource_query: *ecs.query_t,

    camera_query: *ecs.query_t,
};

fn initializeWindowsRenderStats(it: *ecs.iter_t) callconv(.C) void {
    var world = it.world;

    var mesh_upload_query_desc: ecs.query_desc_t = .{};
    mesh_upload_query_desc.filter.terms[0] = .{ .id = ecs.id(world, Renderer.Mesh) };
    mesh_upload_query_desc.filter.terms[1] = .{
        .id = ecs.id(world, DX12GPUMesh),
        .oper = .Not,
    };

    var mesh_upload_query = ecs.query_init(it.world, &mesh_upload_query_desc) catch @panic("Failed to create mesh upload query");

    var upload_resource_query_desc: ecs.query_desc_t = .{};
    upload_resource_query_desc.filter.terms[0] = .{ .id = ecs.id(world, Renderer.UploadResource) };

    var upload_resource_query = ecs.query_init(it.world, &upload_resource_query_desc) catch @panic("Failed to create resource upload query");

    var mesh_draw_query_desc: ecs.query_desc_t = .{};

    mesh_draw_query_desc.filter.terms[0] = .{
        .id = ecs.pair(ecs.id(world, Renderer.RenderMeshRef), ecs.Wildcard),
    };

    mesh_draw_query_desc.filter.terms[1] = .{
        .id = ecs.pair(ecs.id(world, Renderer.ShaderRef), ecs.Wildcard),
    };

    mesh_draw_query_desc.filter.terms[2] = .{
        .id = ecs.id(world, Renderer.RenderTransform),
    };

    mesh_draw_query_desc.filter.terms[3] = .{
        .id = ecs.id(world, Renderer.Material),
    };

    var mesh_draw_query = ecs.query_init(it.world, &mesh_draw_query_desc) catch @panic("Failed to create draw query");

    var camera_query_desc = ecs.query_desc_t{};
    camera_query_desc.filter.terms[0] = .{ .id = ecs.id(world, Renderer.Camera) };
    camera_query_desc.filter.terms[1] = .{ .id = ecs.id(world, Core.Transform.LocalToWorld) };

    var camera_query = ecs.query_init(it.world, &camera_query_desc) catch @panic("Failed to create resource upload query");

    var entities = ecs.field(it, ecs.entity_t, 0).?;
    var native_windows = ecs.field(it, Application.NativeWindow, 1).?;

    const allocator = ecs.get(it.world, ecs.id(world, Core.PersistentAllocator), Core.PersistentAllocator).?.value;

    var alloc_buffer: [2048 * 16]u8 = undefined;
    var alloc_state = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);
    var temp_alloc = alloc_state.allocator();

    for (entities, native_windows) |entity, window| {
        var render_state = DX12RenderState{
            .allocator = allocator,
            .gctx = zd3d12.GraphicsContext.init(allocator, @as(w32.HWND, @ptrCast(window.handle))),
            .depth_texture = undefined,
            .gui_renderer = undefined,
            .mesh_upload_query = mesh_upload_query,
            .mesh_draw_query = mesh_draw_query,
            .upload_resource_query = upload_resource_query,
            .camera_query = camera_query,
            // .texture_upload_query = texture_upload_query,
            .start_time = std.time.nanoTimestamp(),
        };

        {
            render_state.gctx.beginFrame();
            defer {
                render_state.gctx.endFrame();
                render_state.gctx.finishGpuCommands();
            }

            render_state.depth_texture = .{
                .resource = render_state.gctx.createCommittedResource(
                    .DEFAULT,
                    .{},
                    &blk: {
                        var desc = d3d12.RESOURCE_DESC.initTex2d(.D32_FLOAT, render_state.gctx.viewport_width, render_state.gctx.viewport_height, 1);
                        desc.Flags = .{ .ALLOW_DEPTH_STENCIL = true, .DENY_SHADER_RESOURCE = true };
                        break :blk desc;
                    },
                    .{ .DEPTH_WRITE = true },
                    &d3d12.CLEAR_VALUE.initDepthStencil(.D32_FLOAT, 1.0, 0),
                ) catch |err| hrPanic(err),
                .view = render_state.gctx.allocateCpuDescriptors(.DSV, 1),
            };

            render_state.gctx.device.CreateDepthStencilView(
                render_state.gctx.lookupResource(render_state.depth_texture.resource).?,
                null,
                render_state.depth_texture.view,
            );

            render_state.gctx.flushResourceBarriers();

            std.debug.assert(GuiRendererDX12.c.igGetCurrentContext() == null);
            _ = GuiRendererDX12.c.igCreateContext(null);

            var ui = GuiRendererDX12.c.igGetIO().?;
            std.debug.assert(ui.*.BackendPlatformUserData == null);
            GuiRendererDX12.c.igGetStyle().?.*.WindowRounding = 0.0;

            render_state.gui_renderer = GuiRendererDX12.init(temp_alloc, &render_state.gctx, 1, content_dir);
        }

        // Defer setting this value so that is happens after the previous defer statements completed.
        _ = ecs.defer_begin(it.world);
        _ = ecs.set(it.world, entity, DX12RenderState, render_state);
        _ = ecs.set(it.world, ecs.id(world, Renderer.Renderer), Renderer.Renderer, .{
            .dummy = 0,
        });
        _ = ecs.defer_end(it.world);
    }
}

fn cleanupRenderStates(it: *ecs.iter_t) callconv(.C) void {
    var entity_array = ecs.field(it, ecs.entity_t, 0).?;
    var render_state_array = ecs.field(it, DX12RenderState, 1).?;

    for (entity_array, render_state_array) |entity, *render_state| {
        // render_state.gctx.destroyPipeline(render_state.mesh_pbr_pso);

        render_state.gctx.deinit(render_state.allocator);
        ecs.remove(it.world, entity, DX12RenderState);
    }
}

const DX12GPUTexture = struct {
    handle: zd3d12.ResourceHandle,
    persistent_descriptor: zd3d12.PersistentDescriptor,
};

const DX12GPUMesh = struct {
    vertices: zd3d12.ResourceHandle,
    indices: zd3d12.ResourceHandle,
    num_indices: usize,
    num_vertices: usize,
};

const DX12GPUShader = struct {
    pipeline: zd3d12.PipelineHandle,
};

pub fn preInitializePlatformModule(world: *ecs.world_t) void {
    ecs.COMPONENT(world, DX12RenderState);
    ecs.COMPONENT(world, DX12GPUMesh);
    ecs.COMPONENT(world, DX12GPUTexture);
    ecs.COMPONENT(world, DX12GPUShader);

    ecs.COMPONENT(world, ResourceReady);
    ecs.COMPONENT(world, UploadResource);
}

pub fn beginGuiFrame(it: *ecs.iter_t) callconv(.C) void {
    var render_state_array = ecs.field(it, DX12RenderState, 1).?;

    var render_state = render_state_array[0];

    var ui = GuiRendererDX12.c.igGetIO().?;

    ui.*.DisplaySize = GuiRendererDX12.c.ImVec2{
        .x = @as(f32, @floatFromInt(render_state.gctx.viewport_width)),
        .y = @as(f32, @floatFromInt(render_state.gctx.viewport_height)),
    };
    ui.*.DeltaTime = it.delta_time;

    GuiRendererDX12.c.igNewFrame();
}

pub fn initializePlatformModule(world: *ecs.world_t) void {
    var initialize_windows_description = ecs.observer_desc_t{
        .callback = initializeWindowsRenderStats,
        .filter = .{
            .terms = [_]ecs.term_t{
                .{
                    .id = ecs.id(world, Application.NativeWindow),
                },
                .{
                    .id = ecs.id(world, DX12RenderState),
                    .oper = .Not,
                },
            } ++ [_]ecs.term_t{.{}} ** (ecs.TERM_DESC_CACHE_SIZE - 2),
        },
        .events = [_]ecs.entity_t{ecs.OnSet} ++ [_]ecs.entity_t{0} ** (ecs.OBSERVER_DESC_EVENT_COUNT_MAX - 1),
    };

    ecs.OBSERVER(world, "Initialize Window Render States", &initialize_windows_description);

    var cleanup_render_states = ecs.observer_desc_t{
        .callback = cleanupRenderStates,
        .filter = .{
            .terms = [_]ecs.term_t{
                .{
                    .id = ecs.id(world, DX12RenderState),
                },
                .{
                    .id = ecs.id(world, Application.Window),
                },
            } ++ [_]ecs.term_t{.{}} ** (ecs.TERM_DESC_CACHE_SIZE - 2),
        },
        .events = [_]ecs.entity_t{ecs.OnRemove} ++ [_]ecs.entity_t{0} ** (ecs.OBSERVER_DESC_EVENT_COUNT_MAX - 1),
    };

    ecs.OBSERVER(world, "Cleanup Window Render States", &cleanup_render_states);

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(world, DX12RenderState) };
        system_desc.callback = beginGuiFrame;
        ecs.SYSTEM(world, "BeginGUIFrame", ecs.PreFrame, &system_desc);
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.query.filter.terms[0] = .{ .id = ecs.id(world, DX12RenderState) };
        system_desc.callback = draw;
        ecs.SYSTEM(world, "Draw", ecs.PostFrame, &system_desc);
    }
}
