const std = @import("std");
const raylib = @import("raylib");
const root = @import("root.zig");

const WORLD_SIZE_CHUNKS = root.WORLD_SIZE_CHUNKS;

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

// Vector helper functions
fn sub3(a: raylib.Vector3, b: raylib.Vector3) raylib.Vector3 {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

fn add3(a: raylib.Vector3, b: raylib.Vector3) raylib.Vector3 {
    return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
}

fn scale3(v: raylib.Vector3, s: f32) raylib.Vector3 {
    return .{ .x = v.x * s, .y = v.y * s, .z = v.z * s };
}

fn cross3(a: raylib.Vector3, b: raylib.Vector3) raylib.Vector3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

fn normalize3(v: raylib.Vector3) raylib.Vector3 {
    const len = @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (len == 0) return v;
    return scale3(v, 1.0 / len);
}

// Frustum culling
const Frustum = struct {
    aabb_min_x: f32,
    aabb_max_x: f32,
    aabb_min_y: f32,
    aabb_max_y: f32,
    aabb_min_z: f32,
    aabb_max_z: f32,
};

fn calculateOrthoFrustum(camera: raylib.Camera3D, screen_width: f32, screen_height: f32) Frustum {
    const aspect = screen_width / screen_height;
    const half_height = camera.fovy / 2.0;
    const half_width = half_height * aspect;

    // Camera basis vectors
    const forward = normalize3(sub3(camera.target, camera.position));
    const right = normalize3(cross3(forward, camera.up));
    const up = normalize3(cross3(right, forward));

    // Near/far distances
    const near_dist: f32 = 0.01;
    const far_dist: f32 = 1000.0;

    const center_near = add3(camera.position, scale3(forward, near_dist));
    const center_far = add3(camera.position, scale3(forward, far_dist));

    // Compute AABB of frustum in world space
    var min_x: f32 = std.math.inf(f32);
    var max_x: f32 = -std.math.inf(f32);
    var min_y: f32 = std.math.inf(f32);
    var max_y: f32 = -std.math.inf(f32);
    var min_z: f32 = std.math.inf(f32);
    var max_z: f32 = -std.math.inf(f32);

    const centers = [_]raylib.Vector3{ center_near, center_far };
    const offsets = [_][2]f32{
        .{ -half_width, -half_height },
        .{ -half_width, half_height },
        .{ half_width, -half_height },
        .{ half_width, half_height },
    };

    for (centers) |center| {
        for (offsets) |off| {
            const corner = add3(add3(center, scale3(right, off[0])), scale3(up, off[1]));
            min_x = @min(min_x, corner.x);
            max_x = @max(max_x, corner.x);
            min_y = @min(min_y, corner.y);
            max_y = @max(max_y, corner.y);
            min_z = @min(min_z, corner.z);
            max_z = @max(max_z, corner.z);
        }
    }

    return Frustum{
        .aabb_min_x = min_x,
        .aabb_max_x = max_x,
        .aabb_min_y = min_y,
        .aabb_max_y = max_y,
        .aabb_min_z = min_z,
        .aabb_max_z = max_z,
    };
}

fn isBlockInFrustum(frustum: Frustum, x: f32, y: f32, z: f32) bool {
    const half: f32 = 0.5;
    if (x + half < frustum.aabb_min_x or x - half > frustum.aabb_max_x) return false;
    if (y + half < frustum.aabb_min_y or y - half > frustum.aabb_max_y) return false;
    if (z + half < frustum.aabb_min_z or z - half > frustum.aabb_max_z) return false;
    return true;
}

fn isChunkInFrustum(frustum: Frustum, min: raylib.Vector3, max: raylib.Vector3) bool {
    // AABB vs AABB intersection test
    if (max.x < frustum.aabb_min_x or min.x > frustum.aabb_max_x) return false;
    if (max.y < frustum.aabb_min_y or min.y > frustum.aabb_max_y) return false;
    if (max.z < frustum.aabb_min_z or min.z > frustum.aabb_max_z) return false;
    return true;
}

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
    visible_blocks_drawn: i32,
    solid_blocks_drawn: i32,
};

pub const Renderer = struct {
    ortho_camera: raylib.Camera3D,
    material: raylib.Material,

    pub fn init() Renderer {
        const sea_y: f32 = @as(f32, @floatFromInt(root.World.seaLevelYIndexDefault()));
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

    pub fn update(self: *Renderer) void {
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
        const wheel = raylib.getMouseWheelMove();
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
        const frustum = calculateOrthoFrustum(self.ortho_camera, screen_w, screen_h);

        var triangles_drawn: i32 = 0;
        var chunks_regenerated: i32 = 0;
        var chunks_drawn: i32 = 0;
        var visible_blocks_drawn: i32 = 0;
        var solid_blocks_drawn: i32 = 0;

        const model_pos = raylib.Vector3{ .x = 0, .y = 0, .z = 0 };
        const model_scale: f32 = 1.0;
        const mesh_tint = raylib.Color.ray_white;

        const rlgl = raylib.gl;
        const RL_LINES: i32 = 0x0001;
        const grid_color = raylib.Color{ .r = 0, .g = 0, .b = 0, .a = 120 };

        var drawn_chunk_indices: [WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS]usize = undefined;
        var drawn_chunk_count: usize = 0;

        // Iterate chunks (not blocks!)
        for (0..WORLD_SIZE_CHUNKS) |cx| {
            for (0..WORLD_SIZE_CHUNKS) |cy| {
                for (0..WORLD_SIZE_CHUNKS) |cz| {
                    const chunk_idx: usize =
                        cz * WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS +
                        cy * WORLD_SIZE_CHUNKS +
                        cx;

                    // Regenerate mesh if dirty
                    if (world.chunks[chunk_idx].dirty) {
                        chunks_regenerated += 1;
                        world.generateChunkMesh(cx, cy, cz) catch |err| {
                            std.debug.print("Mesh gen error: {}\n", .{err});
                            continue;
                        };
                    }

                    const chunk_mesh = &world.chunk_meshes[chunk_idx];
                    if (chunk_mesh.model == null) continue; // Empty chunk

                    // Chunk-level frustum culling
                    if (!isChunkInFrustum(
                        frustum,
                        chunk_mesh.world_min,
                        chunk_mesh.world_max,
                    )) continue;

                    // Draw cached model
                    raylib.drawModel(chunk_mesh.model.?, model_pos, model_scale, mesh_tint);

                    drawn_chunk_indices[drawn_chunk_count] = chunk_idx;
                    drawn_chunk_count += 1;

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
        for (drawn_chunk_indices[0..drawn_chunk_count]) |idx| {
            const chunk_mesh = &world.chunk_meshes[idx];
            if (chunk_mesh.grid_line_vertices) |verts| {
                var i: usize = 0;
                while (i + 2 < verts.len) : (i += 3) {
                    rlgl.rlVertex3f(verts[i], verts[i + 1], verts[i + 2]);
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
            const worker_pos = raylib.Vector3{ .x = w.x, .y = w.y, .z = w.z };
            raylib.drawCube(worker_pos, 0.5, 0.8, 0.5, raylib.Color.red);
            raylib.drawCubeWires(worker_pos, 0.5, 0.8, 0.5, raylib.Color.maroon);
            triangles_drawn += 12; // 6 faces * 2 tris
        }

        return .{
            .triangles_drawn = triangles_drawn,
            .chunks_drawn = chunks_drawn,
            .chunks_regenerated = chunks_regenerated,
            .visible_blocks_drawn = visible_blocks_drawn,
            .solid_blocks_drawn = solid_blocks_drawn,
        };
    }
};
