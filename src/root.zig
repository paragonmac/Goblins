// Goblinoria - Voxel colony sim library

const std = @import("std");
const raylib = @import("raylib");
const world_types = @import("world/types.zig");
const world_config = @import("world/config.zig");

pub const BlockType = world_types.BlockType;
pub const BlockCoord = world_types.BlockCoord;
pub const STAIR_BLOCK_ID = world_types.STAIR_BLOCK_ID;

pub const WORLD_SIZE_CHUNKS_BASE = world_config.WORLD_SIZE_CHUNKS_BASE;
pub const WORLD_TILES_X = world_config.WORLD_TILES_X;
pub const WORLD_TILES_Z = world_config.WORLD_TILES_Z;
pub const WORLD_SIZE_CHUNKS_X = world_config.WORLD_SIZE_CHUNKS_X;
pub const WORLD_SIZE_CHUNKS_Y = world_config.WORLD_SIZE_CHUNKS_Y;
pub const WORLD_SIZE_CHUNKS_Z = world_config.WORLD_SIZE_CHUNKS_Z;
pub const WORLD_TOTAL_CHUNKS: usize = world_config.WORLD_TOTAL_CHUNKS;
pub const CHUNK_SIZE = world_config.CHUNK_SIZE;
pub const MAX_DEPTH_BLOCKS: i32 = 20000;

const MATERIAL_ID_MIN: BlockType = 1;
const MATERIAL_ID_MAX: BlockType = 9;
const MATERIAL_ID_COUNT: u8 = 9;
pub const WORLDGEN_SEED: u64 = world_config.WORLDGEN_SEED;

const renderer = @import("renderer.zig");
pub const Renderer = renderer.Renderer;

const raycast = @import("selection/raycast.zig");
pub const BlockHit = raycast.BlockHit;
pub const raycastBlock = raycast.raycastBlock;

pub const mode = @import("mode.zig");
pub const PlayerMode = mode.PlayerMode;

pub const task = @import("task.zig");
pub const Task = task.Task;
pub const TaskQueue = task.TaskQueue;
pub const TaskType = task.TaskType;
pub const TaskStatus = task.TaskStatus;

pub const worker = @import("worker.zig");
pub const Worker = worker.Worker;
pub const WorkerManager = worker.WorkerManager;
pub const WorkerState = worker.WorkerState;

const Chunk = struct {
    blocks: [CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE]BlockType,
    dirty: bool,
};

const ChunkMesh = struct {
    model: ?raylib.Model,
    grid_line_vertices: ?[]f32,
    triangle_count: u32,
    // Triangle counts emitted per axis-aligned face normal.
    // Index order: +Y, -Y, +Z, -Z, +X, -X.
    triangles_by_face: [6]u32,
    visible_block_count: u32,
    solid_block_count: u32,
    world_min: raylib.Vector3,
    world_max: raylib.Vector3,

    pub fn init() ChunkMesh {
        return .{
            .model = null,
            .grid_line_vertices = null,
            .triangle_count = 0,
            .triangles_by_face = [_]u32{0} ** 6,
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

// Old simple Worker struct removed - now using worker.Worker from worker.zig

pub const World = struct {
    chunks: [WORLD_TOTAL_CHUNKS]Chunk,
    chunk_meshes: [WORLD_TOTAL_CHUNKS]ChunkMesh,
    allocator: std.mem.Allocator,
    worker_manager: WorkerManager,
    sea_level_y_index: i16,
    top_render_y_index: i16,
    /// World-space vertical offset in blocks for the current in-memory window.
    /// Displayed level = (internal_y - sea_level_y_index) + vertical_scroll.
    vertical_scroll: i32,
    /// Set of currently selected block coordinates.
    selected_blocks: std.AutoHashMap(BlockCoord, void),
    /// Current player interaction mode
    player_mode: PlayerMode,
    /// Queue of tasks for workers
    task_queue: TaskQueue,

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
        world.selected_blocks = std.AutoHashMap(BlockCoord, void).init(allocator);
        world.player_mode = .dig; // Default to dig mode for easier testing
        world.task_queue = TaskQueue.init(allocator);
        world.worker_manager = WorkerManager.init(allocator);

        return world;
    }

    pub fn deinit(self: *World, allocator: std.mem.Allocator) void {
        // Unload all chunk meshes
        for (&self.chunk_meshes) |*cm| {
            cm.deinit(allocator);
        }
        self.selected_blocks.deinit();
        self.task_queue.deinit();
        self.worker_manager.deinit();
        allocator.destroy(self);
    }

    /// Check if a block at the given coordinates is selected.
    pub fn isBlockSelected(self: *const World, x: u16, y: u16, z: u16) bool {
        const key = BlockCoord{ .x = x, .y = y, .z = z };
        return self.selected_blocks.contains(key);
    }

    /// Toggle selection state for a block. Marks the containing chunk dirty.
    pub fn toggleBlockSelection(self: *World, x: u16, y: u16, z: u16) void {
        const coord = BlockCoord{ .x = x, .y = y, .z = z };
        if (self.selected_blocks.contains(coord)) {
            _ = self.selected_blocks.remove(coord);
        } else {
            self.selected_blocks.put(coord, {}) catch {};
        }
        // Mark the containing chunk as dirty for re-meshing
        const chunk_x: usize = @intCast(x / CHUNK_SIZE);
        const chunk_y: usize = @intCast(y / CHUNK_SIZE);
        const chunk_z: usize = @intCast(z / CHUNK_SIZE);
        const idx = chunkToIndex(chunk_x, chunk_y, chunk_z);
        self.chunks[idx].dirty = true;
    }

    /// Clear all selections, marking affected chunks as dirty.
    pub fn clearSelection(self: *World) void {
        var it = self.selected_blocks.keyIterator();
        while (it.next()) |coord| {
            const chunk_x: usize = @intCast(coord.x / CHUNK_SIZE);
            const chunk_y: usize = @intCast(coord.y / CHUNK_SIZE);
            const chunk_z: usize = @intCast(coord.z / CHUNK_SIZE);
            const idx = chunkToIndex(chunk_x, chunk_y, chunk_z);
            self.chunks[idx].dirty = true;
        }
        self.selected_blocks.clearRetainingCapacity();
    }

    /// Add a block to selection without toggling. Marks chunk dirty if newly selected.
    pub fn addToSelection(self: *World, x: u16, y: u16, z: u16) void {
        const coord = BlockCoord{ .x = x, .y = y, .z = z };
        const was_new = self.selected_blocks.fetchPut(coord, {}) catch return;
        if (was_new == null) {
            // Only mark dirty if this was a new addition
            const chunk_x: usize = @intCast(x / CHUNK_SIZE);
            const chunk_y: usize = @intCast(y / CHUNK_SIZE);
            const chunk_z: usize = @intCast(z / CHUNK_SIZE);
            const idx = chunkToIndex(chunk_x, chunk_y, chunk_z);
            self.chunks[idx].dirty = true;
        }
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

    pub fn chunkToIndex(cx: usize, cy: usize, cz: usize) usize {
        return cz * WORLD_SIZE_CHUNKS_X * WORLD_SIZE_CHUNKS_Y +
            cy * WORLD_SIZE_CHUNKS_X +
            cx;
    }

    pub fn generateChunkMesh(
        self: *World,
        chunk_x: usize,
        chunk_y: usize,
        chunk_z: usize,
    ) !void {
        return @import("world/meshing.zig").generateChunkMesh(self, chunk_x, chunk_y, chunk_z);
    }

    pub fn seedDebug(self: *World) void {
        @import("world/worldgen.zig").seedDebug(self);
    }

    pub fn spawnInitialWorkers(self: *World) void {
        const max_x: i32 = @as(i32, worldSizeBlocksX()) - 1;
        const max_z: i32 = @as(i32, worldSizeBlocksZ()) - 1;
        const center_x: i32 = @divFloor(@as(i32, worldSizeBlocksX()), 2);
        const center_z: i32 = @divFloor(@as(i32, worldSizeBlocksZ()), 2);

        const offsets = [_][2]i32{
            .{ -10, -10 },
            .{ 10, -10 },
            .{ -10, 10 },
            .{ 10, 10 },
        };

        for (offsets) |offset| {
            const spawn_x = std.math.clamp(center_x + offset[0], 0, max_x);
            const spawn_z = std.math.clamp(center_z + offset[1], 0, max_z);
            const surface_y = self.findSurfaceY(@intCast(spawn_x), @intCast(spawn_z));
            const spawn_y: f32 = @floatFromInt(surface_y + 1);
            _ = self.worker_manager.spawnWorker(@floatFromInt(spawn_x), spawn_y, @floatFromInt(spawn_z)) catch {};
        }
    }

    fn findSurfaceY(self: *const World, x: u16, z: u16) u16 {
        var y: i32 = @as(i32, worldMaxYIndex());
        while (y >= 0) : (y -= 1) {
            if (self.getBlock(x, @intCast(y), z) != 0) {
                return @intCast(y);
            }
        }
        return 0;
    }
};
