const std = @import("std");
const raylib = @import("raylib");
const root = @import("../root.zig");

const BlockType = root.BlockType;

const MATERIAL_ID_MIN: BlockType = 1;
const MATERIAL_ID_MAX: BlockType = 9;

fn isBlockSolidForMeshing(world: *const root.World, x: i16, y: i16, z: i16) bool {
    // Treat any blocks above the current render cutoff as air so the slice
    // produces a clean, flat top surface.
    if (y > world.top_render_y_index) return false;
    return world.isBlockSolid(x, y, z);
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
        is_selected: bool,
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
        const base_color = if (is_selected)
            // Solid blue for selected blocks (green is reserved for drag preview)
            ColorRGB{ .r = 0, .g = 150, .b = 155 }
        else
            material_palette[@as(usize, @intCast(mid))];

        const shaded = if (is_selected)
            base_color
        else
            shadeColor(base_color, faceShade(normal));

        // Add color for all 6 vertices (RGBA format)
        for (0..6) |_| {
            try self.colors.appendSlice(self.allocator, &[_]u8{ shaded.r, shaded.g, shaded.b, 255 });
        }
    }
};

pub fn generateChunkMesh(
    world: *root.World,
    chunk_x: usize,
    chunk_y: usize,
    chunk_z: usize,
) !void {
    const chunk_index = root.World.chunkToIndex(chunk_x, chunk_y, chunk_z);

    var builder = MeshBuilder.init(world.allocator);
    defer builder.deinit();

    const world_x_base: u16 = @intCast(chunk_x * root.CHUNK_SIZE);
    const world_y_base: u16 = @intCast(chunk_y * root.CHUNK_SIZE);
    const world_z_base: u16 = @intCast(chunk_z * root.CHUNK_SIZE);

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

    var edge_set = std.AutoHashMap(EdgeKey, void).init(world.allocator);
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
    for (0..root.CHUNK_SIZE) |lx| {
        for (0..root.CHUNK_SIZE) |ly| {
            for (0..root.CHUNK_SIZE) |lz| {
                const wx: u16 = world_x_base + @as(u16, @intCast(lx));
                const wy: u16 = world_y_base + @as(u16, @intCast(ly));
                const wz: u16 = world_z_base + @as(u16, @intCast(lz));

                const block_type: BlockType = world.getBlock(wx, wy, wz);
                if (block_type == 0) continue; // Skip air

                const yi: i16 = @intCast(wy);
                if (yi > world.top_render_y_index) continue; // Cut off everything above the slice

                solid_blocks_in_chunk += 1;

                const xf: f32 = @floatFromInt(wx);
                const yf: f32 = @floatFromInt(wy);
                const zf: f32 = @floatFromInt(wz);
                const pos = raylib.Vector3{ .x = xf, .y = yf, .z = zf };

                const xi: i16 = @intCast(wx);
                const zi: i16 = @intCast(wz);

                const is_selected = world.isBlockSelected(wx, wy, wz);
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
                if (!isBlockSolidForMeshing(world, xi, yi + 1, zi)) {
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
                        is_selected,
                    );
                }

                // Bottom face (-Y)
                if (!isBlockSolidForMeshing(world, xi, yi - 1, zi)) {
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
                        is_selected,
                    );
                }

                // Front face (+Z)
                if (!isBlockSolidForMeshing(world, xi, yi, zi + 1)) {
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
                        is_selected,
                    );
                }

                // Back face (-Z)
                if (!isBlockSolidForMeshing(world, xi, yi, zi - 1)) {
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
                        is_selected,
                    );
                }

                // Right face (+X)
                if (!isBlockSolidForMeshing(world, xi + 1, yi, zi)) {
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
                        is_selected,
                    );
                }

                // Left face (-X)
                if (!isBlockSolidForMeshing(world, xi - 1, yi, zi)) {
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
                        is_selected,
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
        if (world.chunk_meshes[chunk_index].model) |old_model| {
            raylib.unloadModel(old_model);
        }
        world.chunk_meshes[chunk_index].model = null;

        if (world.chunk_meshes[chunk_index].grid_line_vertices) |old_lines| {
            world.allocator.free(old_lines);
        }
        world.chunk_meshes[chunk_index].grid_line_vertices = null;

        world.chunk_meshes[chunk_index].triangle_count = 0;
        world.chunk_meshes[chunk_index].visible_block_count = 0;
        world.chunk_meshes[chunk_index].solid_block_count = solid_blocks_in_chunk;
        world.chunks[chunk_index].dirty = false;
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

        if (world.chunk_meshes[chunk_index].model) |old_model| {
            raylib.unloadModel(old_model);
        }
        world.chunk_meshes[chunk_index].model = null;
        world.chunk_meshes[chunk_index].triangle_count = 0;
        world.chunk_meshes[chunk_index].visible_block_count = 0;
        world.chunk_meshes[chunk_index].solid_block_count = solid_blocks_in_chunk;
        world.chunks[chunk_index].dirty = false;
        return;
    };

    // Free old model if it exists
    if (world.chunk_meshes[chunk_index].model) |old_model| {
        raylib.unloadModel(old_model);
    }

    // Store model and metadata
    world.chunk_meshes[chunk_index].model = model;
    world.chunk_meshes[chunk_index].triangle_count = @intCast(mesh.triangleCount);
    world.chunk_meshes[chunk_index].visible_block_count = visible_blocks_in_chunk;
    world.chunk_meshes[chunk_index].solid_block_count = solid_blocks_in_chunk;

    // Store grid line vertices (quad edges only, no diagonals)
    if (world.chunk_meshes[chunk_index].grid_line_vertices) |old_lines| {
        world.allocator.free(old_lines);
    }
    if (edge_set.count() > 0) {
        var grid_line_builder = try std.ArrayList(f32).initCapacity(world.allocator, edge_set.count() * 2 * 3);
        defer grid_line_builder.deinit(world.allocator);

        var it = edge_set.keyIterator();
        while (it.next()) |k| {
            const ax: f32 = @as(f32, @floatFromInt(k.ax)) * 0.01;
            const ay: f32 = @as(f32, @floatFromInt(k.ay)) * 0.01;
            const az: f32 = @as(f32, @floatFromInt(k.az)) * 0.01;
            const bx: f32 = @as(f32, @floatFromInt(k.bx)) * 0.01;
            const by: f32 = @as(f32, @floatFromInt(k.by)) * 0.01;
            const bz: f32 = @as(f32, @floatFromInt(k.bz)) * 0.01;

            try grid_line_builder.append(world.allocator, ax);
            try grid_line_builder.append(world.allocator, ay);
            try grid_line_builder.append(world.allocator, az);
            try grid_line_builder.append(world.allocator, bx);
            try grid_line_builder.append(world.allocator, by);
            try grid_line_builder.append(world.allocator, bz);
        }

        const copied = try world.allocator.alloc(f32, grid_line_builder.items.len);
        @memcpy(copied, grid_line_builder.items);
        world.chunk_meshes[chunk_index].grid_line_vertices = copied;
    } else {
        world.chunk_meshes[chunk_index].grid_line_vertices = null;
    }

    // Calculate AABB for frustum culling
    world.chunk_meshes[chunk_index].world_min = .{
        .x = @floatFromInt(world_x_base),
        .y = @floatFromInt(world_y_base),
        .z = @floatFromInt(world_z_base),
    };
    world.chunk_meshes[chunk_index].world_max = .{
        .x = @floatFromInt(world_x_base + root.CHUNK_SIZE),
        .y = @floatFromInt(world_y_base + root.CHUNK_SIZE),
        .z = @floatFromInt(world_z_base + root.CHUNK_SIZE),
    };

    // Mark chunk as clean
    world.chunks[chunk_index].dirty = false;
}
