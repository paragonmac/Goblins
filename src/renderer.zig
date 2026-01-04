const std = @import("std");
const raylib = @import("raylib");
const root = @import("root.zig");

const frustum_mod = @import("render/frustum.zig");
const Frustum = frustum_mod.Frustum;
const calculateOrthoFrustum = frustum_mod.calculateOrthoFrustum;
const isChunkInFrustum = frustum_mod.isChunkInFrustum;

const WORLD_SIZE_CHUNKS_X = root.WORLD_SIZE_CHUNKS_X;
const WORLD_SIZE_CHUNKS_Y = root.WORLD_SIZE_CHUNKS_Y;
const WORLD_SIZE_CHUNKS_Z = root.WORLD_SIZE_CHUNKS_Z;

// we are going to adjust grid size on the fly
var userAdjustedMax_X: u32 = 100;
var userAdjustedMax_Y: u32 = 100;
var userAdjustedMax_Z: u32 = 100;

const Face = enum {
    top, // +Y
    bottom, // -Y
    front, // +Z
    back, // -Z
    right, // +X
    left, // -X
};

fn drawBlockFace(pos: raylib.Vector3, face: Face, color: raylib.Color) void {
    const h: f32 = 0.5;

    var v1: raylib.Vector3 = undefined;
    var v2: raylib.Vector3 = undefined;
    var v3: raylib.Vector3 = undefined;
    var v4: raylib.Vector3 = undefined;

    switch (face) {
        .top => {
            v1 = .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z - h };
            v2 = .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z + h };
            v3 = .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z + h };
            v4 = .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z - h };
        },
        .bottom => {
            v1 = .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z + h };
            v2 = .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z - h };
            v3 = .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z - h };
            v4 = .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z + h };
        },
        .front => {
            v1 = .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z + h };
            v2 = .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z + h };
            v3 = .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z + h };
            v4 = .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z + h };
        },
        .back => {
            v1 = .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z - h };
            v2 = .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z - h };
            v3 = .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z - h };
            v4 = .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z - h };
        },
        .right => {
            v1 = .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z + h };
            v2 = .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z - h };
            v3 = .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z - h };
            v4 = .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z + h };
        },
        .left => {
            v1 = .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z - h };
            v2 = .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z + h };
            v3 = .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z + h };
            v4 = .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z - h };
        },
    }

    // Draw quad as two triangles
    raylib.drawTriangle3D(v1, v2, v3, color);
    raylib.drawTriangle3D(v1, v3, v4, color);
}

// Frustum culling helpers live in src/render/frustum.zig

const IDENTITY_MATRIX = raylib.Matrix{
    .m0 = 1,
    .m1 = 0,
    .m2 = 0,
    .m3 = 0,
    .m4 = 0,
    .m5 = 1,
    .m6 = 0,
    .m7 = 0,
    .m8 = 0,
    .m9 = 0,
    .m10 = 1,
    .m11 = 0,
    .m12 = 0,
    .m13 = 0,
    .m14 = 0,
    .m15 = 1,
};

pub const RenderStats = struct {
    triangles_drawn: i32,
    chunks_drawn: i32,
    chunks_regenerated: i32,
    chunks_considered: i32,
    chunks_culled: i32,
    visible_blocks_drawn: i32,
    solid_blocks_drawn: i32,
};

pub const Renderer = struct {
    ortho_camera: raylib.Camera3D,
    material: raylib.Material,

    pub fn init() Renderer {
        const sea_y: f32 = @as(f32, @floatFromInt(root.World.seaLevelYIndexDefault()));
        // Keep the original camera defaults the project started with.
        // (Even if the world size grows, these defaults feel best for the current UX.)
        const orthoCameraTarget = raylib.Vector3{ .x = 52.0, .y = sea_y, .z = 52.0 };
        const orthoCameraPosition = raylib.Vector3{ .x = 80.0, .y = sea_y + 45.0, .z = 80.0 };

        return .{
            .ortho_camera = .{
                .position = orthoCameraPosition,
                .target = orthoCameraTarget,
                .up = raylib.Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 },
                .fovy = 45.0,
                .projection = raylib.CameraProjection.orthographic,
            },
            .material = raylib.loadMaterialDefault() catch unreachable,
        };
    }

    pub fn update(self: *Renderer, wheel: f32) void {
        // Right mouse drag to pan camera
        if (raylib.isMouseButtonDown(raylib.MouseButton.right)) {
            const delta = raylib.getMouseDelta();
            const pan_speed: f32 = 0.05;

            // Camera is at 45-degree angle (looking from corner)
            // Screen X maps to world diagonal (1, 0, -1)
            // Screen Y maps to world diagonal (1, 0, 1)
            const inv_sqrt2: f32 = 0.7071;

            const move_x = (delta.x * inv_sqrt2 + delta.y * inv_sqrt2) * pan_speed;
            const move_z = (-delta.x * inv_sqrt2 + delta.y * inv_sqrt2) * pan_speed;

            // Move camera and target together
            self.ortho_camera.position.x -= move_x;
            self.ortho_camera.position.z -= move_z;
            self.ortho_camera.target.x -= move_x;
            self.ortho_camera.target.z -= move_z;
        }

        // Mouse wheel zoom (adjust orthographic scale)
        if (wheel != 0.0) {
            const zoom_speed: f32 = 2.0;
            self.ortho_camera.fovy -= wheel * zoom_speed;

            // Clamp zoom to reasonable range
            if (self.ortho_camera.fovy < 5.0) self.ortho_camera.fovy = 5.0;
            if (self.ortho_camera.fovy > 200.0) self.ortho_camera.fovy = 200.0;
        }
    }

    pub fn render(self: *Renderer, world: anytype) RenderStats {
        raylib.beginMode3D(self.ortho_camera);
        defer raylib.endMode3D();

        raylib.drawGrid(20, 1.0);

        // Calculate frustum once per frame
        const screen_w: f32 = @floatFromInt(raylib.getScreenWidth());
        const screen_h: f32 = @floatFromInt(raylib.getScreenHeight());
        const world_wx: f32 = @floatFromInt(root.WORLD_SIZE_CHUNKS_X * root.CHUNK_SIZE);
        const world_wy: f32 = @floatFromInt(root.WORLD_SIZE_CHUNKS_Y * root.CHUNK_SIZE);
        const world_wz: f32 = @floatFromInt(root.WORLD_SIZE_CHUNKS_Z * root.CHUNK_SIZE);
        const scroll_y: f32 = @floatFromInt(world.vertical_scroll);
        const world_min = raylib.Vector3{ .x = 0.0, .y = scroll_y, .z = 0.0 };
        const world_max = raylib.Vector3{ .x = world_wx, .y = scroll_y + world_wy, .z = world_wz };
        const frustum = calculateOrthoFrustum(self.ortho_camera, screen_w, screen_h, world_min, world_max);

        var triangles_drawn: i32 = 0;
        var chunks_regenerated: i32 = 0;
        var chunks_drawn: i32 = 0;
        var chunks_considered: i32 = 0;
        var chunks_culled: i32 = 0;
        var visible_blocks_drawn: i32 = 0;
        var solid_blocks_drawn: i32 = 0;

        const model_pos = raylib.Vector3{ .x = 0, .y = scroll_y, .z = 0 };
        const model_scale: f32 = 1.0;
        const mesh_tint = raylib.Color.ray_white;

        const rlgl = raylib.gl;
        const RL_LINES: i32 = 0x0001;
        const grid_color = raylib.Color{ .r = 0, .g = 0, .b = 0, .a = 120 };

        const chunk_size_f: f32 = @floatFromInt(root.CHUNK_SIZE);
        const internal_y_min: f32 = frustum.aabb_min_y - scroll_y;
        const internal_y_max: f32 = frustum.aabb_max_y - scroll_y;

        const cx_min_i: i32 = @intFromFloat(@floor(frustum.aabb_min_x / chunk_size_f));
        const cx_max_i: i32 = @intFromFloat(@floor(frustum.aabb_max_x / chunk_size_f));
        const cy_min_i: i32 = @intFromFloat(@floor(internal_y_min / chunk_size_f));
        const cy_max_i: i32 = @intFromFloat(@floor(internal_y_max / chunk_size_f));
        const cz_min_i: i32 = @intFromFloat(@floor(frustum.aabb_min_z / chunk_size_f));
        const cz_max_i: i32 = @intFromFloat(@floor(frustum.aabb_max_z / chunk_size_f));

        const cx0: usize = @intCast(std.math.clamp(cx_min_i, 0, @as(i32, WORLD_SIZE_CHUNKS_X - 1)));
        const cx1: usize = @intCast(std.math.clamp(cx_max_i, 0, @as(i32, WORLD_SIZE_CHUNKS_X - 1)));
        const cy0: usize = @intCast(std.math.clamp(cy_min_i, 0, @as(i32, WORLD_SIZE_CHUNKS_Y - 1)));
        const cy1: usize = @intCast(std.math.clamp(cy_max_i, 0, @as(i32, WORLD_SIZE_CHUNKS_Y - 1)));
        const cz0: usize = @intCast(std.math.clamp(cz_min_i, 0, @as(i32, WORLD_SIZE_CHUNKS_Z - 1)));
        const cz1: usize = @intCast(std.math.clamp(cz_max_i, 0, @as(i32, WORLD_SIZE_CHUNKS_Z - 1)));

        // Iterate chunks (not blocks!)
        var cx: usize = cx0;
        while (cx <= cx1) : (cx += 1) {
            var cy: usize = cy0;
            while (cy <= cy1) : (cy += 1) {
                var cz: usize = cz0;
                while (cz <= cz1) : (cz += 1) {
                    const chunk_idx: usize =
                        cz * WORLD_SIZE_CHUNKS_X * WORLD_SIZE_CHUNKS_Y +
                        cy * WORLD_SIZE_CHUNKS_X +
                        cx;

                    chunks_considered += 1;

                    // Regenerate mesh if dirty
                    if (world.chunks[chunk_idx].dirty) {
                        chunks_regenerated += 1;
                        world.generateChunkMesh(cx, cy, cz) catch |err| {
                            std.debug.print("Mesh gen error: {}\n", .{err});
                            continue;
                        };
                    }

                    const chunk_mesh = &world.chunk_meshes[chunk_idx];
                    if (chunk_mesh.model == null) {
                        chunks_culled += 1;
                        continue;
                    } // Empty chunk

                    // Chunk-level frustum culling
                    const shifted_min = raylib.Vector3{ .x = chunk_mesh.world_min.x, .y = chunk_mesh.world_min.y + scroll_y, .z = chunk_mesh.world_min.z };
                    const shifted_max = raylib.Vector3{ .x = chunk_mesh.world_max.x, .y = chunk_mesh.world_max.y + scroll_y, .z = chunk_mesh.world_max.z };
                    if (!isChunkInFrustum(
                        frustum,
                        shifted_min,
                        shifted_max,
                    )) {
                        chunks_culled += 1;
                        continue;
                    }

                    // Draw cached model
                    raylib.drawModel(chunk_mesh.model.?, model_pos, model_scale, mesh_tint);

                    chunks_drawn += 1;
                    triangles_drawn += @intCast(chunk_mesh.triangle_count);
                    visible_blocks_drawn += @intCast(chunk_mesh.visible_block_count);
                    solid_blocks_drawn += @intCast(chunk_mesh.solid_block_count);
                }
            }
        }

        // Draw grid overlay: quad edges only (no triangle diagonals).
        rlgl.rlEnableSmoothLines();
        rlgl.rlSetLineWidth(3.0);
        rlgl.rlBegin(RL_LINES);
        rlgl.rlColor4ub(grid_color.r, grid_color.g, grid_color.b, grid_color.a);
        cx = cx0;
        while (cx <= cx1) : (cx += 1) {
            var cy2: usize = cy0;
            while (cy2 <= cy1) : (cy2 += 1) {
                var cz2: usize = cz0;
                while (cz2 <= cz1) : (cz2 += 1) {
                    const chunk_idx: usize =
                        cz2 * WORLD_SIZE_CHUNKS_X * WORLD_SIZE_CHUNKS_Y +
                        cy2 * WORLD_SIZE_CHUNKS_X +
                        cx;

                    const chunk_mesh = &world.chunk_meshes[chunk_idx];
                    if (chunk_mesh.model == null) continue;

                    const shifted_min = raylib.Vector3{ .x = chunk_mesh.world_min.x, .y = chunk_mesh.world_min.y + scroll_y, .z = chunk_mesh.world_min.z };
                    const shifted_max = raylib.Vector3{ .x = chunk_mesh.world_max.x, .y = chunk_mesh.world_max.y + scroll_y, .z = chunk_mesh.world_max.z };
                    if (!isChunkInFrustum(frustum, shifted_min, shifted_max)) continue;

                    if (chunk_mesh.grid_line_vertices) |verts| {
                        var i: usize = 0;
                        while (i + 2 < verts.len) : (i += 3) {
                            rlgl.rlVertex3f(verts[i], verts[i + 1] + scroll_y, verts[i + 2]);
                        }
                    }
                }
            }
        }
        rlgl.rlEnd();
        // rlgl state (line width/smoothing) is global, and raylib batches draws.
        // Force a flush here so the grid is rasterized with the intended state
        // before we restore defaults for subsequent rendering.
        rlgl.rlDrawRenderBatchActive();
        rlgl.rlSetLineWidth(1.0);
        rlgl.rlDisableSmoothLines();

        // Debug output (print if any chunks regenerated)
        if (chunks_regenerated > 0) {
            std.debug.print("⚠️  Chunks regenerated: {}, Chunks drawn: {}\n", .{ chunks_regenerated, chunks_drawn });
        }

        // Render worker if present
        if (world.worker) |w| {
            const worker_pos = raylib.Vector3{ .x = w.x, .y = w.y + scroll_y, .z = w.z };
            raylib.drawCube(worker_pos, 0.5, 0.8, 0.5, raylib.Color.red);
            raylib.drawCubeWires(worker_pos, 0.5, 0.8, 0.5, raylib.Color.maroon);
            triangles_drawn += 12; // 6 faces * 2 tris
        }

        // Live drag preview highlight (does not rebuild meshes).
        const WorldT = @TypeOf(world.*);
        if (@hasField(WorldT, "preview_blocks")) {
            const preview_fill = raylib.Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
            const preview_wire = raylib.Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
            var it = world.preview_blocks.keyIterator();
            while (it.next()) |coord| {
                const pos = raylib.Vector3{
                    .x = @as(f32, @floatFromInt(coord.x)) + 0.5,
                    .y = @as(f32, @floatFromInt(coord.y)) + 0.5 + scroll_y,
                    .z = @as(f32, @floatFromInt(coord.z)) + 0.5,
                };
                raylib.drawCube(pos, 1.0, 1.0, 1.0, preview_fill);
                raylib.drawCubeWires(pos, 1.02, 1.02, 1.02, preview_wire);
            }
        }

        return .{
            .triangles_drawn = triangles_drawn,
            .chunks_drawn = chunks_drawn,
            .chunks_regenerated = chunks_regenerated,
            .chunks_considered = chunks_considered,
            .chunks_culled = chunks_culled,
            .visible_blocks_drawn = visible_blocks_drawn,
            .solid_blocks_drawn = solid_blocks_drawn,
        };
    }
};
