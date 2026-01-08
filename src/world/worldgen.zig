const std = @import("std");
const world_types = @import("types.zig");
const world_config = @import("config.zig");

const BlockType = world_types.BlockType;
const WORLD_SIZE_CHUNKS_X = world_config.WORLD_SIZE_CHUNKS_X;
const WORLD_SIZE_CHUNKS_Y = world_config.WORLD_SIZE_CHUNKS_Y;
const WORLD_SIZE_CHUNKS_Z = world_config.WORLD_SIZE_CHUNKS_Z;
const CHUNK_SIZE = world_config.CHUNK_SIZE;
const WORLDGEN_SEED = world_config.WORLDGEN_SEED;

fn setBlockRaw(world: anytype, x: u16, y: u16, z: u16, block_value: u8) void {
    const WorldT = @TypeOf(world.*);
    const chunk_x: usize = @intCast(x / CHUNK_SIZE);
    const chunk_y: usize = @intCast(y / CHUNK_SIZE);
    const chunk_z: usize = @intCast(z / CHUNK_SIZE);
    const chunk_index: usize = WorldT.chunkToIndex(chunk_x, chunk_y, chunk_z);

    const local_x: u16 = x % CHUNK_SIZE;
    const local_y: u16 = y % CHUNK_SIZE;
    const local_z: u16 = z % CHUNK_SIZE;
    const block_index: usize =
        @as(usize, local_z) * CHUNK_SIZE * CHUNK_SIZE +
        @as(usize, local_y) * CHUNK_SIZE +
        @as(usize, local_x);

    world.chunks[chunk_index].blocks[block_index] = block_value;
}

pub fn seedDebug(world: anytype) void {
    const WorldT = @TypeOf(world.*);
    const world_size_x: usize = WORLD_SIZE_CHUNKS_X * CHUNK_SIZE;
    const world_size_y: usize = WORLD_SIZE_CHUNKS_Y * CHUNK_SIZE;
    const world_size_z: usize = WORLD_SIZE_CHUNKS_Z * CHUNK_SIZE;

    // Seeded PRNG for deterministic, random-looking material assignment.
    var prng = std.Random.DefaultPrng.init(WORLDGEN_SEED);

    // Clear existing blocks (seedDebug is allowed to blow away previous content).
    for (&world.chunks) |*chunk| {
        @memset(&chunk.blocks, 0);
    }

    const sea_internal: i32 = @as(i32, world.sea_level_y_index);
    const solid_limit_internal_y: i32 = sea_internal - world.vertical_scroll;

    // Fill chunks up to sea level.
    for (0..WORLD_SIZE_CHUNKS_Y) |cy| {
        const y0: i32 = @intCast(cy * CHUNK_SIZE);
        const y1: i32 = y0 + (CHUNK_SIZE - 1);

        if (y1 <= solid_limit_internal_y) {
            // Entire chunk layer is solid.
            for (0..WORLD_SIZE_CHUNKS_X) |cx| {
                for (0..WORLD_SIZE_CHUNKS_Z) |cz| {
                    const idx = WorldT.chunkToIndex(cx, cy, cz);
                    // Fill per-voxel with random material IDs 1..9.
                    for (0..CHUNK_SIZE) |ly| {
                        for (0..CHUNK_SIZE) |lx| {
                            for (0..CHUNK_SIZE) |lz| {
                                const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                                const block_index: usize =
                                    lz * CHUNK_SIZE * CHUNK_SIZE +
                                    ly * CHUNK_SIZE +
                                    lx;
                                world.chunks[idx].blocks[block_index] = mat;
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
                    const idx = WorldT.chunkToIndex(cx, cy, cz);
                    var ly: usize = 0;
                    while (ly < solid_in_chunk) : (ly += 1) {
                        for (0..CHUNK_SIZE) |lx| {
                            for (0..CHUNK_SIZE) |lz| {
                                const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                                const block_index: usize =
                                    lz * CHUNK_SIZE * CHUNK_SIZE +
                                    ly * CHUNK_SIZE +
                                    lx;
                                world.chunks[idx].blocks[block_index] = mat;
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
                setBlockRaw(world, @intCast(x), @intCast(y), @intCast(z), 0);
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
                const internal_y: i32 = world_y - world.vertical_scroll + sea_internal;
                if (internal_y >= 0 and internal_y < @as(i32, @intCast(world_size_y))) {
                    const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                    setBlockRaw(world, @intCast(x), @intCast(internal_y), @intCast(z), mat);
                }
            }
        }
    }

    for (world_size_x - 5..world_size_x) |x| {
        for (0..tower_height) |y| {
            for (0..5) |z| {
                const world_y: i32 = @as(i32, @intCast(y)) + 1;
                const internal_y: i32 = world_y - world.vertical_scroll + sea_internal;
                if (internal_y >= 0 and internal_y < @as(i32, @intCast(world_size_y))) {
                    const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                    setBlockRaw(world, @intCast(x), @intCast(internal_y), @intCast(z), mat);
                }
            }
        }
    }

    for (0..5) |x| {
        for (0..tower_height) |y| {
            for (world_size_z - 5..world_size_z) |z| {
                const world_y: i32 = @as(i32, @intCast(y)) + 1;
                const internal_y: i32 = world_y - world.vertical_scroll + sea_internal;
                if (internal_y >= 0 and internal_y < @as(i32, @intCast(world_size_y))) {
                    const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                    setBlockRaw(world, @intCast(x), @intCast(internal_y), @intCast(z), mat);
                }
            }
        }
    }

    for (world_size_x - 5..world_size_x) |x| {
        for (0..tower_height) |y| {
            for (world_size_z - 5..world_size_z) |z| {
                const world_y: i32 = @as(i32, @intCast(y)) + 1;
                const internal_y: i32 = world_y - world.vertical_scroll + sea_internal;
                if (internal_y >= 0 and internal_y < @as(i32, @intCast(world_size_y))) {
                    const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                    setBlockRaw(world, @intCast(x), @intCast(internal_y), @intCast(z), mat);
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
                    const internal_y: i32 = world_y - world.vertical_scroll + sea_internal;
                    if (internal_y >= 0 and internal_y < @as(i32, @intCast(world_size_y))) {
                        const mat: BlockType = prng.random().intRangeAtMost(BlockType, 1, 9);
                        setBlockRaw(world, @intCast(x), @intCast(internal_y), @intCast(z), mat);
                    }
                }
            }
        }
    }

    // Everything was written raw; force all chunks to regenerate meshes.
    world.markAllChunksDirty();
}
