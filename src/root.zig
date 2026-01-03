// Goblinoria - Voxel colony sim library

const std = @import("std");
const raylib = @import("raylib");
const BlockType = u8;
pub const WORLD_SIZE_CHUNKS_BASE = 13;
pub const WORLD_TILES_X = 5; // current cube + 4 more (option A)
pub const WORLD_TILES_Z = 5; // current cube + 4 more (option A)
pub const WORLD_SIZE_CHUNKS_X = WORLD_SIZE_CHUNKS_BASE * WORLD_TILES_X;
pub const WORLD_SIZE_CHUNKS_Y = WORLD_SIZE_CHUNKS_BASE;
pub const WORLD_SIZE_CHUNKS_Z = WORLD_SIZE_CHUNKS_BASE * WORLD_TILES_Z;
pub const WORLD_TOTAL_CHUNKS: usize = WORLD_SIZE_CHUNKS_X * WORLD_SIZE_CHUNKS_Y * WORLD_SIZE_CHUNKS_Z;
pub const CHUNK_SIZE = 8;
pub const MAX_DEPTH_BLOCKS: i32 = 20000;

const MATERIAL_ID_MIN: BlockType = 1;
const MATERIAL_ID_MAX: BlockType = 9;
const MATERIAL_ID_COUNT: u8 = 9;
const WORLDGEN_SEED: u64 = 0x9E37_79B9_7F4A_7C15; // fixed seed for deterministic worldgen

pub const Renderer = @import("renderer.zig").Renderer;

const Chunk = struct {
    blocks: [CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE]BlockType,
    dirty: bool,
};

const ChunkMesh = struct {
    model: ?raylib.Model,
    grid_line_vertices: ?[]f32,
    triangle_count: u32,
    visible_block_count: u32,
    solid_block_count: u32,
    world_min: raylib.Vector3,
    world_max: raylib.Vector3,

    pub fn init() ChunkMesh {
        return .{
            .model = null,
            .grid_line_vertices = null,
            .triangle_count = 0,
            .visible_block_count = 0,
            .solid_block_count = 0,
            .world_min = .{ .x = 0, .y = 0, .z = 0 },
            .world_max = .{ .x = 0, .y = 0, .z = 0 },
        };
    }

    pub fn deinit(self: *ChunkMesh, allocator: std.mem.Allocator) void {
        if (self.model) |m| {
            raylib.unloadModel(m);
        }

        if (self.grid_line_vertices) |verts| {
            allocator.free(verts);
        }
    }
};

pub const Worker = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const World = struct {
    chunks: [WORLD_TOTAL_CHUNKS]Chunk,
    chunk_meshes: [WORLD_TOTAL_CHUNKS]ChunkMesh,
    allocator: std.mem.Allocator,
    worker: ?Worker,
    sea_level_y_index: i16,
    top_render_y_index: i16,
    /// World-space vertical offset in blocks for the current in-memory window.
    /// Displayed level = (internal_y - sea_level_y_index) + vertical_scroll.
    vertical_scroll: i32,

    pub fn worldSizeBlocksX() i16 {
        return @intCast(WORLD_SIZE_CHUNKS_X * CHUNK_SIZE);
    }

    pub fn worldSizeBlocksY() i16 {
        return @intCast(WORLD_SIZE_CHUNKS_Y * CHUNK_SIZE);
    }

    pub fn worldSizeBlocksZ() i16 {
        return @intCast(WORLD_SIZE_CHUNKS_Z * CHUNK_SIZE);
    }

    pub fn totalBlockSlots() u32 {
        const sx: u32 = @intCast(WORLD_SIZE_CHUNKS_X * CHUNK_SIZE);
        const sy: u32 = @intCast(WORLD_SIZE_CHUNKS_Y * CHUNK_SIZE);
        const sz: u32 = @intCast(WORLD_SIZE_CHUNKS_Z * CHUNK_SIZE);
        return sx * sy * sz;
    }

    pub fn worldMaxYIndex() i16 {
        return worldSizeBlocksY() - 1;
    }

    pub fn seaLevelYIndexDefault() i16 {
        // Leave headroom above sea level for mountains (~30 blocks)
        const mountain_headroom: i16 = 30;
        return worldMaxYIndex() - mountain_headroom;
    }

    pub fn topRenderLevel(self: *const World) i32 {
        // Displayed to player: sea level is 0, below is negative.
        return @as(i32, self.top_render_y_index - self.sea_level_y_index) + self.vertical_scroll;
    }

    pub fn setTopRenderLevel(self: *World, desired_level: i32) void {
        var desired = desired_level;
        if (desired < -MAX_DEPTH_BLOCKS) desired = -MAX_DEPTH_BLOCKS;

        const max_internal: i32 = @as(i32, worldMaxYIndex());
        const sea_internal: i32 = @as(i32, self.sea_level_y_index);

        // internal = desired - scroll + sea
        var desired_internal: i32 = desired - self.vertical_scroll + sea_internal;
        var window_shifted = false;

        if (desired_internal < 0) {
            // Shift the window so desired maps to the TOP of the in-memory window.
            // We render blocks with internal_y <= top_render_y_index, so mapping the
            // cutoff to max_internal keeps a full depth range below it.
            self.vertical_scroll = desired + sea_internal - max_internal;
            desired_internal = max_internal;
            window_shifted = true;
        } else if (desired_internal > max_internal) {
            // Shift the window so desired maps to internal y=max.
            self.vertical_scroll = desired + sea_internal;
            desired_internal = 0;
            window_shifted = true;
        }

        self.setTopRenderYIndex(@intCast(desired_internal));
        if (window_shifted) {
            // Rebuild the debug world content for the new vertical window.
            // (Keeps memory constant while allowing very deep levels.)
            self.seedDebug();
        }
    }

    pub fn adjustTopRenderLevel(self: *World, delta: i32) void {
        self.setTopRenderLevel(self.topRenderLevel() + delta);
    }

    pub fn markAllChunksDirty(self: *World) void {
        for (&self.chunks) |*chunk| {
            chunk.dirty = true;
        }
    }

    fn markChunksDirtyForYRange(self: *World, y_a: i16, y_b: i16) void {
        const y0: i16 = @min(y_a, y_b);
        const y1: i16 = @max(y_a, y_b);

        const cy0: usize = @intCast(@divFloor(@as(i32, y0), CHUNK_SIZE));
        const cy1: usize = @intCast(@divFloor(@as(i32, y1), CHUNK_SIZE));
        const max_cy: usize = WORLD_SIZE_CHUNKS_Y - 1;

        const clamped_cy0: usize = @min(cy0, max_cy);
        const clamped_cy1: usize = @min(cy1, max_cy);

        var cy: usize = clamped_cy0;
        while (cy <= clamped_cy1) : (cy += 1) {
            for (0..WORLD_SIZE_CHUNKS_X) |cx| {
                for (0..WORLD_SIZE_CHUNKS_Z) |cz| {
                    self.chunks[chunkToIndex(cx, cy, cz)].dirty = true;
                }
            }
        }
    }

    pub fn setTopRenderYIndex(self: *World, desired: i16) void {
        const clamped = std.math.clamp(desired, 0, worldMaxYIndex());
        if (clamped == self.top_render_y_index) return;
        const old = self.top_render_y_index;
        self.top_render_y_index = clamped;

        // Only chunks whose block range intersects the changed cutoff band can change mesh.
        // If delta is 1, this touches at most two chunk-Y layers.
        self.markChunksDirtyForYRange(old, clamped);
    }

    pub fn init(allocator: std.mem.Allocator) !*World {
        const world = try allocator.create(World);
        world.allocator = allocator;

        for (&world.chunks) |*chunk| {
            @memset(&chunk.blocks, 0);
            chunk.dirty = false;
        }

        // Initialize chunk meshes
        for (&world.chunk_meshes) |*cm| {
            cm.* = ChunkMesh.init();
        }

        world.sea_level_y_index = seaLevelYIndexDefault();
        world.top_render_y_index = world.sea_level_y_index;
        world.vertical_scroll = 0;

        // Initialize worker on top of the debug cube
        world.worker = Worker{ .x = 4.0, .y = @as(f32, @floatFromInt(world.sea_level_y_index)) + 9.5, .z = 4.0 };
        return world;
    }

    pub fn deinit(self: *World, allocator: std.mem.Allocator) void {
        // Unload all chunk meshes
        for (&self.chunk_meshes) |*cm| {
            cm.deinit(allocator);
        }
        allocator.destroy(self);
    }
    pub fn getBlock(self: *const World, x: u16, y: u16, z: u16) BlockType {
        const chunk_x: usize = @intCast(x / CHUNK_SIZE);
        const chunk_y: usize = @intCast(y / CHUNK_SIZE);
        const chunk_z: usize = @intCast(z / CHUNK_SIZE);
        const chunk_index: usize = chunkToIndex(chunk_x, chunk_y, chunk_z);

        const local_x: u16 = x % CHUNK_SIZE;
        const local_y: u16 = y % CHUNK_SIZE;
        const local_z: u16 = z % CHUNK_SIZE;
        const block_index: usize =
            @as(usize, local_z) * CHUNK_SIZE * CHUNK_SIZE +
            @as(usize, local_y) * CHUNK_SIZE +
            @as(usize, local_x);

        return self.chunks[chunk_index].blocks[block_index];
    }

    /// Check if block at position is solid (non-air)
    /// Returns false for out-of-bounds (treat as air)
    pub fn isBlockSolid(self: *const World, x: i16, y: i16, z: i16) bool {
        if (x < 0 or y < 0 or z < 0) return false;
        if (x >= worldSizeBlocksX() or y >= worldSizeBlocksY() or z >= worldSizeBlocksZ()) return false;
        return self.getBlock(@intCast(x), @intCast(y), @intCast(z)) > 0;
    }

    fn isBlockSolidForMeshing(self: *const World, x: i16, y: i16, z: i16) bool {
        // Treat any blocks above the current render cutoff as air so the slice
        // produces a clean, flat top surface.
        if (y > self.top_render_y_index) return false;
        return self.isBlockSolid(x, y, z);
    }

    pub fn setBlock(self: *World, x: u16, y: u16, z: u16, blockChange: u8) void {
        const chunk_x: usize = @intCast(x / CHUNK_SIZE);
        const chunk_y: usize = @intCast(y / CHUNK_SIZE);
        const chunk_z: usize = @intCast(z / CHUNK_SIZE);
        const chunk_index: usize = chunkToIndex(chunk_x, chunk_y, chunk_z);

        const local_x: u16 = x % CHUNK_SIZE;
        const local_y: u16 = y % CHUNK_SIZE;
        const local_z: u16 = z % CHUNK_SIZE;
        const block_index: usize =
            @as(usize, local_z) * CHUNK_SIZE * CHUNK_SIZE +
            @as(usize, local_y) * CHUNK_SIZE +
            @as(usize, local_x);

        self.chunks[chunk_index].blocks[block_index] = blockChange;

        // Mark chunk dirty for mesh regeneration
        self.chunks[chunk_index].dirty = true;

        const stride_y: usize = WORLD_SIZE_CHUNKS_X;
        const stride_z: usize = WORLD_SIZE_CHUNKS_X * WORLD_SIZE_CHUNKS_Y;

        // Mark neighbor chunks dirty if on boundary (affects their visible faces)
        if (local_x == 0 and chunk_x > 0) {
            const neighbor_idx = chunk_index - 1;
            self.chunks[neighbor_idx].dirty = true;
        }
        if (local_x == CHUNK_SIZE - 1 and chunk_x < WORLD_SIZE_CHUNKS_X - 1) {
            const neighbor_idx = chunk_index + 1;
            self.chunks[neighbor_idx].dirty = true;
        }
        if (local_y == 0 and chunk_y > 0) {
            const neighbor_idx = chunk_index - stride_y;
            self.chunks[neighbor_idx].dirty = true;
        }
        if (local_y == CHUNK_SIZE - 1 and chunk_y < WORLD_SIZE_CHUNKS_Y - 1) {
            const neighbor_idx = chunk_index + stride_y;
            self.chunks[neighbor_idx].dirty = true;
        }
        if (local_z == 0 and chunk_z > 0) {
            const neighbor_idx = chunk_index - stride_z;
            self.chunks[neighbor_idx].dirty = true;
        }
        if (local_z == CHUNK_SIZE - 1 and chunk_z < WORLD_SIZE_CHUNKS_Z - 1) {
            const neighbor_idx = chunk_index + stride_z;
            self.chunks[neighbor_idx].dirty = true;
        }
    }

    fn setBlockRaw(self: *World, x: u16, y: u16, z: u16, block_value: u8) void {
        const chunk_x: usize = @intCast(x / CHUNK_SIZE);
        const chunk_y: usize = @intCast(y / CHUNK_SIZE);
        const chunk_z: usize = @intCast(z / CHUNK_SIZE);
        const chunk_index: usize = chunkToIndex(chunk_x, chunk_y, chunk_z);

        const local_x: u16 = x % CHUNK_SIZE;
        const local_y: u16 = y % CHUNK_SIZE;
        const local_z: u16 = z % CHUNK_SIZE;
        const block_index: usize =
            @as(usize, local_z) * CHUNK_SIZE * CHUNK_SIZE +
            @as(usize, local_y) * CHUNK_SIZE +
            @as(usize, local_x);

        self.chunks[chunk_index].blocks[block_index] = block_value;
    }

    fn chunkToIndex(cx: usize, cy: usize, cz: usize) usize {
        return cz * WORLD_SIZE_CHUNKS_X * WORLD_SIZE_CHUNKS_Y +
            cy * WORLD_SIZE_CHUNKS_X +
            cx;
    }

    const MeshBuilder = struct {
        vertices: std.ArrayList(f32),
        texcoords: std.ArrayList(f32),
        normals: std.ArrayList(f32),
        colors: std.ArrayList(u8),
        allocator: std.mem.Allocator,

        const ColorRGB = struct { r: u8, g: u8, b: u8 };

        // 1..9 earth-tone palette. Index 0 is unused (air).
        const material_palette: [10]ColorRGB = .{
            .{ .r = 0, .g = 0, .b = 0 }, // 0 (unused)
            .{ .r = 210, .g = 180, .b = 140 }, // 1 sand
            .{ .r = 199, .g = 172, .b = 128 }, // 2 dry grass
            .{ .r = 184, .g = 152, .b = 108 }, // 3 tan
            .{ .r = 170, .g = 132, .b = 84 }, // 4 ochre
            .{ .r = 153, .g = 106, .b = 72 }, // 5 clay
            .{ .r = 139, .g = 90, .b = 43 }, // 6 brown
            .{ .r = 112, .g = 74, .b = 38 }, // 7 dark soil
            .{ .r = 124, .g = 124, .b = 124 }, // 8 stone
            .{ .r = 84, .g = 84, .b = 84 }, // 9 dark stone
        };

        fn clampMaterialId(material_id: BlockType) BlockType {
            if (material_id < MATERIAL_ID_MIN) return MATERIAL_ID_MIN;
            if (material_id > MATERIAL_ID_MAX) return MATERIAL_ID_MAX;
            return material_id;
        }

        fn faceShade(normal: raylib.Vector3) u8 {
            // Simple directional shading factor in 0..255.
            if (normal.y > 0.5) return 255; // top
            if (normal.y < -0.5) return 150; // bottom
            if (normal.x > 0.5 or normal.x < -0.5) return 190; // X sides
            return 210; // Z sides
        }

        fn shadeColor(base: ColorRGB, shade: u8) ColorRGB {
            const sr: u16 = @intCast(shade);
            return .{
                .r = @intCast((@as(u16, base.r) * sr) / 255),
                .g = @intCast((@as(u16, base.g) * sr) / 255),
                .b = @intCast((@as(u16, base.b) * sr) / 255),
            };
        }

        fn init(allocator: std.mem.Allocator) MeshBuilder {
            return .{
                .vertices = .{},
                .texcoords = .{},
                .normals = .{},
                .colors = .{},
                .allocator = allocator,
            };
        }

        fn deinit(self: *MeshBuilder) void {
            self.vertices.deinit(self.allocator);
            self.texcoords.deinit(self.allocator);
            self.normals.deinit(self.allocator);
            self.colors.deinit(self.allocator);
        }

        fn addQuad(
            self: *MeshBuilder,
            material_id: BlockType,
            v1: raylib.Vector3,
            v2: raylib.Vector3,
            v3: raylib.Vector3,
            v4: raylib.Vector3,
            normal: raylib.Vector3,
        ) !void {
            // Triangle 1: v1, v2, v3
            try self.vertices.appendSlice(self.allocator, &[_]f32{ v1.x, v1.y, v1.z });
            try self.vertices.appendSlice(self.allocator, &[_]f32{ v2.x, v2.y, v2.z });
            try self.vertices.appendSlice(self.allocator, &[_]f32{ v3.x, v3.y, v3.z });

            // Triangle 2: v1, v3, v4
            try self.vertices.appendSlice(self.allocator, &[_]f32{ v1.x, v1.y, v1.z });
            try self.vertices.appendSlice(self.allocator, &[_]f32{ v3.x, v3.y, v3.z });
            try self.vertices.appendSlice(self.allocator, &[_]f32{ v4.x, v4.y, v4.z });

            // Texcoords (basic UV mapping, 6 vertices)
            const uvs = [_]f32{ 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1 };
            try self.texcoords.appendSlice(self.allocator, &uvs);

            // Normals (same for all 6 vertices)
            for (0..6) |_| {
                try self.normals.appendSlice(self.allocator, &[_]f32{ normal.x, normal.y, normal.z });
            }

            const mid = clampMaterialId(material_id);
            const base = material_palette[@as(usize, @intCast(mid))];
            const shaded = shadeColor(base, faceShade(normal));

            // Add color for all 6 vertices (RGBA format)
            for (0..6) |_| {
                try self.colors.appendSlice(self.allocator, &[_]u8{ shaded.r, shaded.g, shaded.b, 255 });
            }
        }
    };

    pub fn generateChunkMesh(
        self: *World,
        chunk_x: usize,
        chunk_y: usize,
        chunk_z: usize,
    ) !void {
        const chunk_index = chunkToIndex(chunk_x, chunk_y, chunk_z);

        var builder = MeshBuilder.init(self.allocator);
        defer builder.deinit();

        const world_x_base: u16 = @intCast(chunk_x * CHUNK_SIZE);
        const world_y_base: u16 = @intCast(chunk_y * CHUNK_SIZE);
        const world_z_base: u16 = @intCast(chunk_z * CHUNK_SIZE);

        const h: f32 = 0.5;

        var visible_blocks_in_chunk: u32 = 0;
        var solid_blocks_in_chunk: u32 = 0;

        const EdgeKey = struct {
            ax: i32,
            ay: i32,
            az: i32,
            bx: i32,
            by: i32,
            bz: i32,
        };

        var edge_set = std.AutoHashMap(EdgeKey, void).init(self.allocator);
        defer edge_set.deinit();

        const Edge = struct {
            fn lt(a: EdgeKey, b: EdgeKey) bool {
                if (a.ax != b.ax) return a.ax < b.ax;
                if (a.ay != b.ay) return a.ay < b.ay;
                if (a.az != b.az) return a.az < b.az;
                if (a.bx != b.bx) return a.bx < b.bx;
                if (a.by != b.by) return a.by < b.by;
                return a.bz < b.bz;
            }

            fn addFixed(set: *std.AutoHashMap(EdgeKey, void), ax: i32, ay: i32, az: i32, bx: i32, by: i32, bz: i32) !void {
                var key = EdgeKey{ .ax = ax, .ay = ay, .az = az, .bx = bx, .by = by, .bz = bz };
                // Normalize so undirected edges hash the same.
                const swapped = EdgeKey{ .ax = key.bx, .ay = key.by, .az = key.bz, .bx = key.ax, .by = key.ay, .bz = key.az };
                if (lt(swapped, key)) key = swapped;
                try set.put(key, {});
            }

            fn quadEdgesFixed(
                set: *std.AutoHashMap(EdgeKey, void),
                v1: [3]i32,
                v2: [3]i32,
                v3: [3]i32,
                v4: [3]i32,
            ) !void {
                try addFixed(set, v1[0], v1[1], v1[2], v2[0], v2[1], v2[2]);
                try addFixed(set, v2[0], v2[1], v2[2], v3[0], v3[1], v3[2]);
                try addFixed(set, v3[0], v3[1], v3[2], v4[0], v4[1], v4[2]);
                try addFixed(set, v4[0], v4[1], v4[2], v1[0], v1[1], v1[2]);
            }
        };

        // Iterate over blocks in THIS chunk only
        for (0..CHUNK_SIZE) |lx| {
            for (0..CHUNK_SIZE) |ly| {
                for (0..CHUNK_SIZE) |lz| {
                    const wx: u16 = world_x_base + @as(u16, @intCast(lx));
                    const wy: u16 = world_y_base + @as(u16, @intCast(ly));
                    const wz: u16 = world_z_base + @as(u16, @intCast(lz));

                    const block_type = self.getBlock(wx, wy, wz);
                    if (block_type == 0) continue; // Skip air

                    const yi: i16 = @intCast(wy);
                    if (yi > self.top_render_y_index) continue; // Cut off everything above the slice

                    solid_blocks_in_chunk += 1;

                    const xf: f32 = @floatFromInt(wx);
                    const yf: f32 = @floatFromInt(wy);
                    const zf: f32 = @floatFromInt(wz);
                    const pos = raylib.Vector3{ .x = xf, .y = yf, .z = zf };

                    const xi: i16 = @intCast(wx);
                    const zi: i16 = @intCast(wz);

                    var emitted_any_face = false;

                    // Grid line positions are generated in fixed-point (1/100 units)
                    // to avoid float rounding artifacts when deduplicating edges.
                    const unit: i32 = 100;
                    const half: i32 = 50;
                    const eps: i32 = 1; // 0.01
                    const fx: i32 = @as(i32, @intCast(wx)) * unit;
                    const fy_fixed: i32 = @as(i32, @intCast(wy)) * unit;
                    const fz: i32 = @as(i32, @intCast(wz)) * unit;

                    // Add faces where neighbor is air (backface culling)
                    // Top face (+Y)
                    if (!self.isBlockSolidForMeshing(xi, yi + 1, zi)) {
                        emitted_any_face = true;
                        const v1 = raylib.Vector3{ .x = pos.x - h, .y = pos.y + h, .z = pos.z - h };
                        const v2 = raylib.Vector3{ .x = pos.x - h, .y = pos.y + h, .z = pos.z + h };
                        const v3 = raylib.Vector3{ .x = pos.x + h, .y = pos.y + h, .z = pos.z + h };
                        const v4 = raylib.Vector3{ .x = pos.x + h, .y = pos.y + h, .z = pos.z - h };
                        try Edge.quadEdgesFixed(
                            &edge_set,
                            .{ fx - half, fy_fixed + half + eps, fz - half },
                            .{ fx - half, fy_fixed + half + eps, fz + half },
                            .{ fx + half, fy_fixed + half + eps, fz + half },
                            .{ fx + half, fy_fixed + half + eps, fz - half },
                        );
                        try builder.addQuad(
                            block_type,
                            v1,
                            v2,
                            v3,
                            v4,
                            .{ .x = 0, .y = 1, .z = 0 },
                        );
                    }

                    // Bottom face (-Y)
                    if (!self.isBlockSolidForMeshing(xi, yi - 1, zi)) {
                        emitted_any_face = true;
                        const v1 = raylib.Vector3{ .x = pos.x - h, .y = pos.y - h, .z = pos.z - h };
                        const v2 = raylib.Vector3{ .x = pos.x + h, .y = pos.y - h, .z = pos.z - h };
                        const v3 = raylib.Vector3{ .x = pos.x + h, .y = pos.y - h, .z = pos.z + h };
                        const v4 = raylib.Vector3{ .x = pos.x - h, .y = pos.y - h, .z = pos.z + h };
                        try Edge.quadEdgesFixed(
                            &edge_set,
                            .{ fx - half, fy_fixed - half - eps, fz - half },
                            .{ fx + half, fy_fixed - half - eps, fz - half },
                            .{ fx + half, fy_fixed - half - eps, fz + half },
                            .{ fx - half, fy_fixed - half - eps, fz + half },
                        );
                        try builder.addQuad(
                            block_type,
                            v1,
                            v2,
                            v3,
                            v4,
                            .{ .x = 0, .y = -1, .z = 0 },
                        );
                    }

                    // Front face (+Z)
                    if (!self.isBlockSolidForMeshing(xi, yi, zi + 1)) {
                        emitted_any_face = true;
                        const v1 = raylib.Vector3{ .x = pos.x - h, .y = pos.y - h, .z = pos.z + h };
                        const v2 = raylib.Vector3{ .x = pos.x + h, .y = pos.y - h, .z = pos.z + h };
                        const v3 = raylib.Vector3{ .x = pos.x + h, .y = pos.y + h, .z = pos.z + h };
                        const v4 = raylib.Vector3{ .x = pos.x - h, .y = pos.y + h, .z = pos.z + h };
                        try Edge.quadEdgesFixed(
                            &edge_set,
                            .{ fx - half, fy_fixed - half, fz + half + eps },
                            .{ fx + half, fy_fixed - half, fz + half + eps },
                            .{ fx + half, fy_fixed + half, fz + half + eps },
                            .{ fx - half, fy_fixed + half, fz + half + eps },
                        );
                        try builder.addQuad(
                            block_type,
                            v1,
                            v2,
                            v3,
                            v4,
                            .{ .x = 0, .y = 0, .z = 1 },
                        );
                    }

                    // Back face (-Z)
                    if (!self.isBlockSolidForMeshing(xi, yi, zi - 1)) {
                        emitted_any_face = true;
                        const v1 = raylib.Vector3{ .x = pos.x - h, .y = pos.y - h, .z = pos.z - h };
                        const v2 = raylib.Vector3{ .x = pos.x - h, .y = pos.y + h, .z = pos.z - h };
                        const v3 = raylib.Vector3{ .x = pos.x + h, .y = pos.y + h, .z = pos.z - h };
                        const v4 = raylib.Vector3{ .x = pos.x + h, .y = pos.y - h, .z = pos.z - h };
                        try Edge.quadEdgesFixed(
                            &edge_set,
                            .{ fx - half, fy_fixed - half, fz - half - eps },
                            .{ fx - half, fy_fixed + half, fz - half - eps },
                            .{ fx + half, fy_fixed + half, fz - half - eps },
                            .{ fx + half, fy_fixed - half, fz - half - eps },
                        );
                        try builder.addQuad(
                            block_type,
                            v1,
                            v2,
                            v3,
                            v4,
                            .{ .x = 0, .y = 0, .z = -1 },
                        );
                    }

                    // Right face (+X)
                    if (!self.isBlockSolidForMeshing(xi + 1, yi, zi)) {
                        emitted_any_face = true;
                        const v1 = raylib.Vector3{ .x = pos.x + h, .y = pos.y - h, .z = pos.z - h };
                        const v2 = raylib.Vector3{ .x = pos.x + h, .y = pos.y + h, .z = pos.z - h };
                        const v3 = raylib.Vector3{ .x = pos.x + h, .y = pos.y + h, .z = pos.z + h };
                        const v4 = raylib.Vector3{ .x = pos.x + h, .y = pos.y - h, .z = pos.z + h };
                        try Edge.quadEdgesFixed(
                            &edge_set,
                            .{ fx + half + eps, fy_fixed - half, fz - half },
                            .{ fx + half + eps, fy_fixed + half, fz - half },
                            .{ fx + half + eps, fy_fixed + half, fz + half },
                            .{ fx + half + eps, fy_fixed - half, fz + half },
                        );
                        try builder.addQuad(
                            block_type,
                            v1,
                            v2,
                            v3,
                            v4,
                            .{ .x = 1, .y = 0, .z = 0 },
                        );
                    }

                    // Left face (-X)
                    if (!self.isBlockSolidForMeshing(xi - 1, yi, zi)) {
                        emitted_any_face = true;
                        const v1 = raylib.Vector3{ .x = pos.x - h, .y = pos.y - h, .z = pos.z - h };
                        const v2 = raylib.Vector3{ .x = pos.x - h, .y = pos.y - h, .z = pos.z + h };
                        const v3 = raylib.Vector3{ .x = pos.x - h, .y = pos.y + h, .z = pos.z + h };
                        const v4 = raylib.Vector3{ .x = pos.x - h, .y = pos.y + h, .z = pos.z - h };
                        try Edge.quadEdgesFixed(
                            &edge_set,
                            .{ fx - half - eps, fy_fixed - half, fz - half },
                            .{ fx - half - eps, fy_fixed - half, fz + half },
                            .{ fx - half - eps, fy_fixed + half, fz + half },
                            .{ fx - half - eps, fy_fixed + half, fz - half },
                        );
                        try builder.addQuad(
                            block_type,
                            v1,
                            v2,
                            v3,
                            v4,
                            .{ .x = -1, .y = 0, .z = 0 },
                        );
                    }

                    if (emitted_any_face) {
                        visible_blocks_in_chunk += 1;
                    }
                }
            }
        }

        // Convert to raylib Mesh
        const vertex_count: u32 = @intCast(builder.vertices.items.len / 3);
        if (vertex_count == 0) {
            // Empty chunk, no mesh needed
            if (self.chunk_meshes[chunk_index].model) |old_model| {
                raylib.unloadModel(old_model);
            }
            self.chunk_meshes[chunk_index].model = null;

            if (self.chunk_meshes[chunk_index].grid_line_vertices) |old_lines| {
                self.allocator.free(old_lines);
            }
            self.chunk_meshes[chunk_index].grid_line_vertices = null;

            self.chunk_meshes[chunk_index].triangle_count = 0;
            self.chunk_meshes[chunk_index].visible_block_count = 0;
            self.chunk_meshes[chunk_index].solid_block_count = solid_blocks_in_chunk;
            self.chunks[chunk_index].dirty = false;
            return;
        }

        var mesh: raylib.Mesh = std.mem.zeroes(raylib.Mesh);
        mesh.vertexCount = @intCast(vertex_count);
        mesh.triangleCount = @intCast(vertex_count / 3);

        // Allocate and copy vertex data using raylib's memory allocation
        const vert_size = builder.vertices.items.len * @sizeOf(f32);
        mesh.vertices = @ptrCast(@alignCast(raylib.memAlloc(@intCast(vert_size))));
        @memcpy(mesh.vertices[0..builder.vertices.items.len], builder.vertices.items);

        const tex_size = builder.texcoords.items.len * @sizeOf(f32);
        mesh.texcoords = @ptrCast(@alignCast(raylib.memAlloc(@intCast(tex_size))));
        @memcpy(mesh.texcoords[0..builder.texcoords.items.len], builder.texcoords.items);

        const norm_size = builder.normals.items.len * @sizeOf(f32);
        mesh.normals = @ptrCast(@alignCast(raylib.memAlloc(@intCast(norm_size))));
        @memcpy(mesh.normals[0..builder.normals.items.len], builder.normals.items);

        const color_size = builder.colors.items.len * @sizeOf(u8);
        mesh.colors = @ptrCast(@alignCast(raylib.memAlloc(@intCast(color_size))));
        @memcpy(mesh.colors[0..builder.colors.items.len], builder.colors.items);

        // Upload to GPU
        raylib.uploadMesh(&mesh, false); // false = static mesh

        const model = raylib.loadModelFromMesh(mesh) catch |err| {
            std.debug.print("LoadModelFromMesh error: {}\n", .{err});
            raylib.unloadMesh(mesh);

            if (self.chunk_meshes[chunk_index].model) |old_model| {
                raylib.unloadModel(old_model);
            }
            self.chunk_meshes[chunk_index].model = null;
            self.chunk_meshes[chunk_index].triangle_count = 0;
            self.chunk_meshes[chunk_index].visible_block_count = 0;
            self.chunk_meshes[chunk_index].solid_block_count = solid_blocks_in_chunk;
            self.chunks[chunk_index].dirty = false;
            return;
        };

        // Free old model if it exists
        if (self.chunk_meshes[chunk_index].model) |old_model| {
            raylib.unloadModel(old_model);
        }

        // Store model and metadata
        self.chunk_meshes[chunk_index].model = model;
        self.chunk_meshes[chunk_index].triangle_count = @intCast(mesh.triangleCount);
        self.chunk_meshes[chunk_index].visible_block_count = visible_blocks_in_chunk;
        self.chunk_meshes[chunk_index].solid_block_count = solid_blocks_in_chunk;

        // Store grid line vertices (quad edges only, no diagonals)
        if (self.chunk_meshes[chunk_index].grid_line_vertices) |old_lines| {
            self.allocator.free(old_lines);
        }
        if (edge_set.count() > 0) {
            var grid_line_builder = try std.ArrayList(f32).initCapacity(self.allocator, edge_set.count() * 2 * 3);
            defer grid_line_builder.deinit(self.allocator);

            var it = edge_set.keyIterator();
            while (it.next()) |k| {
                const ax: f32 = @as(f32, @floatFromInt(k.ax)) * 0.01;
                const ay: f32 = @as(f32, @floatFromInt(k.ay)) * 0.01;
                const az: f32 = @as(f32, @floatFromInt(k.az)) * 0.01;
                const bx: f32 = @as(f32, @floatFromInt(k.bx)) * 0.01;
                const by: f32 = @as(f32, @floatFromInt(k.by)) * 0.01;
                const bz: f32 = @as(f32, @floatFromInt(k.bz)) * 0.01;

                try grid_line_builder.append(self.allocator, ax);
                try grid_line_builder.append(self.allocator, ay);
                try grid_line_builder.append(self.allocator, az);
                try grid_line_builder.append(self.allocator, bx);
                try grid_line_builder.append(self.allocator, by);
                try grid_line_builder.append(self.allocator, bz);
            }

            const copied = try self.allocator.alloc(f32, grid_line_builder.items.len);
            @memcpy(copied, grid_line_builder.items);
            self.chunk_meshes[chunk_index].grid_line_vertices = copied;
        } else {
            self.chunk_meshes[chunk_index].grid_line_vertices = null;
        }

        // Calculate AABB for frustum culling
        self.chunk_meshes[chunk_index].world_min = .{
            .x = @floatFromInt(world_x_base),
            .y = @floatFromInt(world_y_base),
            .z = @floatFromInt(world_z_base),
        };
        self.chunk_meshes[chunk_index].world_max = .{
            .x = @floatFromInt(world_x_base + CHUNK_SIZE),
            .y = @floatFromInt(world_y_base + CHUNK_SIZE),
            .z = @floatFromInt(world_z_base + CHUNK_SIZE),
        };

        // Mark chunk as clean
        self.chunks[chunk_index].dirty = false;
    }

    pub fn seedDebug(self: *World) void {
        const world_size_x: usize = WORLD_SIZE_CHUNKS_X * CHUNK_SIZE;
        const world_size_y: usize = WORLD_SIZE_CHUNKS_Y * CHUNK_SIZE;
        const world_size_z: usize = WORLD_SIZE_CHUNKS_Z * CHUNK_SIZE;

        // Seeded PRNG for deterministic, random-looking material assignment.
        var prng = std.Random.DefaultPrng.init(WORLDGEN_SEED);

        // Clear existing blocks (seedDebug is allowed to blow away previous content).
        for (&self.chunks) |*chunk| {
            @memset(&chunk.blocks, 0);
        }

        const sea_internal: i32 = @as(i32, self.sea_level_y_index);
        const solid_limit_internal_y: i32 = sea_internal - self.vertical_scroll;

        // Fill chunks up to sea level.
        for (0..WORLD_SIZE_CHUNKS_Y) |cy| {
            const y0: i32 = @intCast(cy * CHUNK_SIZE);
            const y1: i32 = y0 + (CHUNK_SIZE - 1);

            if (y1 <= solid_limit_internal_y) {
                // Entire chunk layer is solid.
                for (0..WORLD_SIZE_CHUNKS_X) |cx| {
                    for (0..WORLD_SIZE_CHUNKS_Z) |cz| {
                        const idx = chunkToIndex(cx, cy, cz);
                        // Fill per-voxel with random material IDs 1..9.
                        for (0..CHUNK_SIZE) |ly| {
                            for (0..CHUNK_SIZE) |lx| {
                                for (0..CHUNK_SIZE) |lz| {
                                    const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                                    const block_index: usize =
                                        lz * CHUNK_SIZE * CHUNK_SIZE +
                                        ly * CHUNK_SIZE +
                                        lx;
                                    self.chunks[idx].blocks[block_index] = mat;
                                }
                            }
                        }
                    }
                }
            } else if (y0 <= solid_limit_internal_y and y1 > solid_limit_internal_y) {
                // Partial layer: fill only internal y <= solid_limit.
                const solid_in_chunk: usize = @intCast((solid_limit_internal_y - y0) + 1);
                for (0..WORLD_SIZE_CHUNKS_X) |cx| {
                    for (0..WORLD_SIZE_CHUNKS_Z) |cz| {
                        const idx = chunkToIndex(cx, cy, cz);
                        var ly: usize = 0;
                        while (ly < solid_in_chunk) : (ly += 1) {
                            for (0..CHUNK_SIZE) |lx| {
                                for (0..CHUNK_SIZE) |lz| {
                                    const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                                    const block_index: usize =
                                        lz * CHUNK_SIZE * CHUNK_SIZE +
                                        ly * CHUNK_SIZE +
                                        lx;
                                    self.chunks[idx].blocks[block_index] = mat;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Carve a vertical shaft near center for visual depth when slicing.
        const center_x: usize = world_size_x / 2;
        const center_z: usize = world_size_z / 2;
        const shaft_half: usize = 2;
        for (center_x - shaft_half..center_x + shaft_half) |x| {
            for (center_z - shaft_half..center_z + shaft_half) |z| {
                for (0..world_size_y) |y| {
                    self.setBlockRaw(@intCast(x), @intCast(y), @intCast(z), 0);
                }
            }
        }

        // Create some scattered structures to test performance.
        // Towers in corners.
        const tower_height = 20;
        for (0..5) |x| {
            for (0..tower_height) |y| {
                for (0..5) |z| {
                    const world_y: i32 = @as(i32, @intCast(y)) + 1;
                    const internal_y: i32 = world_y - self.vertical_scroll + sea_internal;
                    if (internal_y >= 0 and internal_y < @as(i32, @intCast(world_size_y))) {
                        const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                        self.setBlockRaw(@intCast(x), @intCast(internal_y), @intCast(z), mat);
                    }
                }
            }
        }

        for (world_size_x - 5..world_size_x) |x| {
            for (0..tower_height) |y| {
                for (0..5) |z| {
                    const world_y: i32 = @as(i32, @intCast(y)) + 1;
                    const internal_y: i32 = world_y - self.vertical_scroll + sea_internal;
                    if (internal_y >= 0 and internal_y < @as(i32, @intCast(world_size_y))) {
                        const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                        self.setBlockRaw(@intCast(x), @intCast(internal_y), @intCast(z), mat);
                    }
                }
            }
        }

        for (0..5) |x| {
            for (0..tower_height) |y| {
                for (world_size_z - 5..world_size_z) |z| {
                    const world_y: i32 = @as(i32, @intCast(y)) + 1;
                    const internal_y: i32 = world_y - self.vertical_scroll + sea_internal;
                    if (internal_y >= 0 and internal_y < @as(i32, @intCast(world_size_y))) {
                        const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                        self.setBlockRaw(@intCast(x), @intCast(internal_y), @intCast(z), mat);
                    }
                }
            }
        }

        for (world_size_x - 5..world_size_x) |x| {
            for (0..tower_height) |y| {
                for (world_size_z - 5..world_size_z) |z| {
                    const world_y: i32 = @as(i32, @intCast(y)) + 1;
                    const internal_y: i32 = world_y - self.vertical_scroll + sea_internal;
                    if (internal_y >= 0 and internal_y < @as(i32, @intCast(world_size_y))) {
                        const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                        self.setBlockRaw(@intCast(x), @intCast(internal_y), @intCast(z), mat);
                    }
                }
            }
        }

        // Central pyramid.
        const pyramid_base = 30;
        const pyramid_x = world_size_x / 2 - pyramid_base / 2;
        const pyramid_z = world_size_z / 2 - pyramid_base / 2;

        for (0..pyramid_base) |layer| {
            const size = pyramid_base - layer;
            const offset = layer / 2;
            for (0..size) |dx| {
                for (0..size) |dz| {
                    const x = pyramid_x + offset + dx;
                    const z = pyramid_z + offset + dz;
                    if (x < world_size_x and z < world_size_z) {
                        const world_y: i32 = @as(i32, @intCast(layer)) + 1;
                        const internal_y: i32 = world_y - self.vertical_scroll + sea_internal;
                        if (internal_y >= 0 and internal_y < @as(i32, @intCast(world_size_y))) {
                            const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                            self.setBlockRaw(@intCast(x), @intCast(internal_y), @intCast(z), mat);
                        }
                    }
                }
            }
        }

        // Everything was written raw; force all chunks to regenerate meshes.
        self.markAllChunksDirty();
    }
};
