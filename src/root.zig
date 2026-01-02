// Goblinoria - Voxel colony sim library

const std = @import("std");
const BlockType = u8;
const WORLD_SIZE_CHUNKS = 4;
const CHUNK_SIZE = 4;

pub const Renderer = @import("renderer.zig").Renderer;

const Chunk = struct {
    blocks: [CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE]BlockType,
    dirty: bool,
};

pub const Worker = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const World = struct {
    chunks: [WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS]Chunk,
    worker: ?Worker,

    pub fn init(allocator: std.mem.Allocator) !*World {
        const world = try allocator.create(World);
        for (&world.chunks) |*chunk| {
            @memset(&chunk.blocks, 0);
            chunk.dirty = false;
        }
        // Initialize worker on top of the debug cube
        world.worker = Worker{ .x = 4.0, .y = 9.5, .z = 4.0 };
        return world;
    }
    pub fn deinit(self: *World, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
    pub fn getBlock(self: *const World, x: u8, y: u8, z: u8) BlockType {
        const chunk_x = x / CHUNK_SIZE;
        const chunk_y = y / CHUNK_SIZE;
        const chunk_z = z / CHUNK_SIZE;
        const chunk_index: u32 =
            @as(u32, chunk_z) * WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS +
            @as(u32, chunk_y) * WORLD_SIZE_CHUNKS +
            @as(u32, chunk_x);

        const local_x = x % CHUNK_SIZE;
        const local_y = y % CHUNK_SIZE;
        const local_z = z % CHUNK_SIZE;
        const block_index: u32 =
            @as(u32, local_z) * CHUNK_SIZE * CHUNK_SIZE +
            @as(u32, local_y) * CHUNK_SIZE +
            @as(u32, local_x);

        return self.chunks[chunk_index].blocks[block_index];
    }

    pub fn setBlock(self: *World, x: u8, y: u8, z: u8, blockChange: u8) void {
        const chunk_x = x / CHUNK_SIZE;
        const chunk_y = y / CHUNK_SIZE;
        const chunk_z = z / CHUNK_SIZE;
        const chunk_index: u32 =
            @as(u32, chunk_z) * WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS +
            @as(u32, chunk_y) * WORLD_SIZE_CHUNKS +
            @as(u32, chunk_x);

        const local_x = x % CHUNK_SIZE;
        const local_y = y % CHUNK_SIZE;
        const local_z = z % CHUNK_SIZE;
        const block_index: u32 =
            @as(u32, local_z) * CHUNK_SIZE * CHUNK_SIZE +
            @as(u32, local_y) * CHUNK_SIZE +
            @as(u32, local_x);

        self.chunks[chunk_index].blocks[block_index] = blockChange;
    }

    pub fn seedDebug(self: *World) void {
        // Solid cube for verifying the renderer.
        // 9x9x9 cube starting at the origin.
        for (0..9) |x| {
            for (0..9) |y| {
                for (0..9) |z| {
                    self.setBlock(@intCast(x), @intCast(y), @intCast(z), 1);
                }
            }
        }
    }
};
