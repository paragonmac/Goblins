// Goblinoria - Voxel colony sim library

const std = @import("std");
const raylib = @import("raylib");
const BlockType = u8;
pub const WORLD_SIZE_CHUNKS = 13;
pub const CHUNK_SIZE = 8;

pub const Renderer = @import("renderer.zig").Renderer;

const Chunk = struct {
    blocks: [CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE]BlockType,
    dirty: bool,
};

const ChunkMesh = struct {
    mesh: ?raylib.Mesh,
    triangle_count: u32,
    world_min: raylib.Vector3,
    world_max: raylib.Vector3,

    pub fn init() ChunkMesh {
        return .{
            .mesh = null,
            .triangle_count = 0,
            .world_min = .{ .x = 0, .y = 0, .z = 0 },
            .world_max = .{ .x = 0, .y = 0, .z = 0 },
        };
    }

    pub fn deinit(self: *ChunkMesh) void {
        if (self.mesh) |m| {
            raylib.unloadMesh(m);
        }
    }
};

pub const Worker = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const World = struct {
    chunks: [WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS]Chunk,
    chunk_meshes: [WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS]ChunkMesh,
    allocator: std.mem.Allocator,
    worker: ?Worker,

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

        // Initialize worker on top of the debug cube
        world.worker = Worker{ .x = 4.0, .y = 9.5, .z = 4.0 };
        return world;
    }

    pub fn deinit(self: *World, allocator: std.mem.Allocator) void {
        // Unload all chunk meshes
        for (&self.chunk_meshes) |*cm| {
            cm.deinit();
        }
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

    /// Check if block at position is solid (non-air)
    /// Returns false for out-of-bounds (treat as air)
    pub fn isBlockSolid(self: *const World, x: i16, y: i16, z: i16) bool {
        if (x < 0 or y < 0 or z < 0) return false;
        const max_coord: i16 = WORLD_SIZE_CHUNKS * CHUNK_SIZE;
        if (x >= max_coord or y >= max_coord or z >= max_coord) return false;
        return self.getBlock(@intCast(x), @intCast(y), @intCast(z)) > 0;
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

        // Mark chunk dirty for mesh regeneration
        self.chunks[chunk_index].dirty = true;

        // Mark neighbor chunks dirty if on boundary (affects their visible faces)
        if (local_x == 0 and chunk_x > 0) {
            const neighbor_idx = chunk_index - 1;
            self.chunks[neighbor_idx].dirty = true;
        }
        if (local_x == CHUNK_SIZE - 1 and chunk_x < WORLD_SIZE_CHUNKS - 1) {
            const neighbor_idx = chunk_index + 1;
            self.chunks[neighbor_idx].dirty = true;
        }
        if (local_y == 0 and chunk_y > 0) {
            const neighbor_idx = chunk_index - WORLD_SIZE_CHUNKS;
            self.chunks[neighbor_idx].dirty = true;
        }
        if (local_y == CHUNK_SIZE - 1 and chunk_y < WORLD_SIZE_CHUNKS - 1) {
            const neighbor_idx = chunk_index + WORLD_SIZE_CHUNKS;
            self.chunks[neighbor_idx].dirty = true;
        }
        if (local_z == 0 and chunk_z > 0) {
            const neighbor_idx = chunk_index - (WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS);
            self.chunks[neighbor_idx].dirty = true;
        }
        if (local_z == CHUNK_SIZE - 1 and chunk_z < WORLD_SIZE_CHUNKS - 1) {
            const neighbor_idx = chunk_index + (WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS);
            self.chunks[neighbor_idx].dirty = true;
        }
    }

    fn chunkToIndex(cx: usize, cy: usize, cz: usize) u32 {
        return @intCast(cz * WORLD_SIZE_CHUNKS * WORLD_SIZE_CHUNKS +
            cy * WORLD_SIZE_CHUNKS +
            cx);
    }

    const MeshBuilder = struct {
        vertices: std.ArrayList(f32),
        texcoords: std.ArrayList(f32),
        normals: std.ArrayList(f32),
        colors: std.ArrayList(u8),
        allocator: std.mem.Allocator,

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

            // Calculate color based on face direction (simple directional shading)
            var r: u8 = 255;
            var g: u8 = 255;
            var b: u8 = 255;

            if (normal.y > 0.5) {
                // Top face - brightest (full light from above)
                r = 255; g = 255; b = 255;
            } else if (normal.y < -0.5) {
                // Bottom face - darkest
                r = 128; g = 128; b = 128;
            } else if (normal.x > 0.5 or normal.x < -0.5) {
                // X-axis faces - medium-dark
                r = 180; g = 180; b = 180;
            } else {
                // Z-axis faces - medium
                r = 200; g = 200; b = 200;
            }

            // Add color for all 6 vertices (RGBA format)
            for (0..6) |_| {
                try self.colors.appendSlice(self.allocator, &[_]u8{ r, g, b, 255 });
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

        const world_x_base: u8 = @intCast(chunk_x * CHUNK_SIZE);
        const world_y_base: u8 = @intCast(chunk_y * CHUNK_SIZE);
        const world_z_base: u8 = @intCast(chunk_z * CHUNK_SIZE);

        const h: f32 = 0.5;

        // Iterate over blocks in THIS chunk only
        for (0..CHUNK_SIZE) |lx| {
            for (0..CHUNK_SIZE) |ly| {
                for (0..CHUNK_SIZE) |lz| {
                    const wx = world_x_base + @as(u8, @intCast(lx));
                    const wy = world_y_base + @as(u8, @intCast(ly));
                    const wz = world_z_base + @as(u8, @intCast(lz));

                    const block_type = self.getBlock(wx, wy, wz);
                    if (block_type == 0) continue; // Skip air

                    const xf: f32 = @floatFromInt(wx);
                    const yf: f32 = @floatFromInt(wy);
                    const zf: f32 = @floatFromInt(wz);
                    const pos = raylib.Vector3{ .x = xf, .y = yf, .z = zf };

                    const xi: i16 = @intCast(wx);
                    const yi: i16 = @intCast(wy);
                    const zi: i16 = @intCast(wz);

                    // Add faces where neighbor is air (backface culling)
                    // Top face (+Y)
                    if (!self.isBlockSolid(xi, yi + 1, zi)) {
                        try builder.addQuad(
                            .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z - h },
                            .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z + h },
                            .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z + h },
                            .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z - h },
                            .{ .x = 0, .y = 1, .z = 0 },
                        );
                    }

                    // Bottom face (-Y)
                    if (!self.isBlockSolid(xi, yi - 1, zi)) {
                        try builder.addQuad(
                            .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z - h },
                            .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z - h },
                            .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z + h },
                            .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z + h },
                            .{ .x = 0, .y = -1, .z = 0 },
                        );
                    }

                    // Front face (+Z)
                    if (!self.isBlockSolid(xi, yi, zi + 1)) {
                        try builder.addQuad(
                            .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z + h },
                            .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z + h },
                            .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z + h },
                            .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z + h },
                            .{ .x = 0, .y = 0, .z = 1 },
                        );
                    }

                    // Back face (-Z)
                    if (!self.isBlockSolid(xi, yi, zi - 1)) {
                        try builder.addQuad(
                            .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z - h },
                            .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z - h },
                            .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z - h },
                            .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z - h },
                            .{ .x = 0, .y = 0, .z = -1 },
                        );
                    }

                    // Right face (+X)
                    if (!self.isBlockSolid(xi + 1, yi, zi)) {
                        try builder.addQuad(
                            .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z - h },
                            .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z - h },
                            .{ .x = pos.x + h, .y = pos.y + h, .z = pos.z + h },
                            .{ .x = pos.x + h, .y = pos.y - h, .z = pos.z + h },
                            .{ .x = 1, .y = 0, .z = 0 },
                        );
                    }

                    // Left face (-X)
                    if (!self.isBlockSolid(xi - 1, yi, zi)) {
                        try builder.addQuad(
                            .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z - h },
                            .{ .x = pos.x - h, .y = pos.y - h, .z = pos.z + h },
                            .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z + h },
                            .{ .x = pos.x - h, .y = pos.y + h, .z = pos.z - h },
                            .{ .x = -1, .y = 0, .z = 0 },
                        );
                    }
                }
            }
        }

        // Convert to raylib Mesh
        const vertex_count: u32 = @intCast(builder.vertices.items.len / 3);
        if (vertex_count == 0) {
            // Empty chunk, no mesh needed
            self.chunk_meshes[chunk_index].mesh = null;
            self.chunk_meshes[chunk_index].triangle_count = 0;
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

        // Free old mesh if it exists
        if (self.chunk_meshes[chunk_index].mesh) |old_mesh| {
            raylib.unloadMesh(old_mesh);
        }

        // Store mesh and metadata
        self.chunk_meshes[chunk_index].mesh = mesh;
        self.chunk_meshes[chunk_index].triangle_count = @intCast(mesh.triangleCount);

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
        const world_size = WORLD_SIZE_CHUNKS * CHUNK_SIZE; // 104

        // Create a ground plane
        for (0..world_size) |x| {
            for (0..world_size) |z| {
                self.setBlock(@intCast(x), 0, @intCast(z), 1);
            }
        }

        // Create some scattered structures to test performance
        // Towers in corners
        const tower_height = 20;
        for (0..5) |x| {
            for (0..tower_height) |y| {
                for (0..5) |z| {
                    self.setBlock(@intCast(x), @intCast(y), @intCast(z), 1);
                }
            }
        }

        for (world_size - 5..world_size) |x| {
            for (0..tower_height) |y| {
                for (0..5) |z| {
                    self.setBlock(@intCast(x), @intCast(y), @intCast(z), 1);
                }
            }
        }

        for (0..5) |x| {
            for (0..tower_height) |y| {
                for (world_size - 5..world_size) |z| {
                    self.setBlock(@intCast(x), @intCast(y), @intCast(z), 1);
                }
            }
        }

        for (world_size - 5..world_size) |x| {
            for (0..tower_height) |y| {
                for (world_size - 5..world_size) |z| {
                    self.setBlock(@intCast(x), @intCast(y), @intCast(z), 1);
                }
            }
        }

        // Central pyramid
        const pyramid_base = 30;
        const pyramid_x = world_size / 2 - pyramid_base / 2;
        const pyramid_z = world_size / 2 - pyramid_base / 2;

        for (0..pyramid_base) |layer| {
            const size = pyramid_base - layer;
            const offset = layer / 2;
            for (0..size) |dx| {
                for (0..size) |dz| {
                    const x = pyramid_x + offset + dx;
                    const z = pyramid_z + offset + dz;
                    if (x < world_size and z < world_size) {
                        self.setBlock(@intCast(x), @intCast(layer + 1), @intCast(z), 1);
                    }
                }
            }
        }

        // Generate initial meshes for all dirty chunks
        for (0..WORLD_SIZE_CHUNKS) |cx| {
            for (0..WORLD_SIZE_CHUNKS) |cy| {
                for (0..WORLD_SIZE_CHUNKS) |cz| {
                    const chunk_idx = chunkToIndex(cx, cy, cz);
                    if (self.chunks[chunk_idx].dirty) {
                        self.generateChunkMesh(cx, cy, cz) catch |err| {
                            std.debug.print("Initial mesh gen error at ({},{},{}): {}\n", .{ cx, cy, cz, err });
                        };
                    }
                }
            }
        }
    }
};
