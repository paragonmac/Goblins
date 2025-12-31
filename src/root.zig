// Goblinoria - Voxel colony sim library

const std = @import("std");
const BlockType = u8;
const WORLD_SIZE_CHUNKS = 8;
const CHUNK_SIZE = 32;

const Chunk = struct {
    blocks: [CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE]BlockType,
    dirty: bool,
};

pub const World = struct {
    chunks: [WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS]Chunk,

    pub fn init(allocator: std.mem.Allocator) !*World {
        const world =  try allocator.create(World);
        for(&world.chunks)|*chunk|{
            @memset(&chunk.blocks, 0);
            chunk.dirty = false;
        }
        return world;
    }
    pub fn deinit(self: *World, allocator: std.mem.Allocator)void{
        allocator.destroy(self);
    }
};
