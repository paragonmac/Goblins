const std = @import("std");
const raylib = @import("raylib");

/// Result of a raycast against the voxel world.
pub const BlockHit = struct {
    x: u16,
    y: u16,
    z: u16,
    hit: bool,
};

/// Perform ray-voxel intersection using DDA algorithm.
/// Returns the first solid block hit by the ray, or hit=false if none.
///
/// Requirements on `world`:
/// - `world.isBlockSolid(x: i16, y: i16, z: i16) bool`
/// - `@TypeOf(world.*).worldSizeBlocksX() i16` and same for Y/Z
pub fn raycastBlock(world: anytype, ray: raylib.Ray, max_distance: f32) BlockHit {
    const WorldT = @TypeOf(world.*);

    var pos = ray.position;
    const dir = ray.direction;

    // The world is rendered with a vertical offset (`vertical_scroll`) applied.
    // Raylib's screen->world ray is in that rendered coordinate space, but our
    // voxel data (and isBlockSolid) are in internal coordinates.
    if (@hasField(WorldT, "vertical_scroll")) {
        pos.y -= @as(f32, @floatFromInt(world.vertical_scroll));
    }

    var voxel_x: i32 = @intFromFloat(@floor(pos.x));
    var voxel_y: i32 = @intFromFloat(@floor(pos.y));
    var voxel_z: i32 = @intFromFloat(@floor(pos.z));

    const step_x: i32 = if (dir.x >= 0) 1 else -1;
    const step_y: i32 = if (dir.y >= 0) 1 else -1;
    const step_z: i32 = if (dir.z >= 0) 1 else -1;

    const next_x: f32 = if (dir.x >= 0) @floor(pos.x) + 1.0 else @floor(pos.x);
    const next_y: f32 = if (dir.y >= 0) @floor(pos.y) + 1.0 else @floor(pos.y);
    const next_z: f32 = if (dir.z >= 0) @floor(pos.z) + 1.0 else @floor(pos.z);

    var t_max_x: f32 = if (dir.x != 0) (next_x - pos.x) / dir.x else std.math.inf(f32);
    var t_max_y: f32 = if (dir.y != 0) (next_y - pos.y) / dir.y else std.math.inf(f32);
    var t_max_z: f32 = if (dir.z != 0) (next_z - pos.z) / dir.z else std.math.inf(f32);

    const t_delta_x: f32 = if (dir.x != 0) @abs(1.0 / dir.x) else std.math.inf(f32);
    const t_delta_y: f32 = if (dir.y != 0) @abs(1.0 / dir.y) else std.math.inf(f32);
    const t_delta_z: f32 = if (dir.z != 0) @abs(1.0 / dir.z) else std.math.inf(f32);

    var distance: f32 = 0;
    const world_max_x: i32 = @as(i32, WorldT.worldSizeBlocksX());
    const world_max_y: i32 = @as(i32, WorldT.worldSizeBlocksY());
    const world_max_z: i32 = @as(i32, WorldT.worldSizeBlocksZ());

    while (distance < max_distance) {
        if (voxel_x >= 0 and voxel_y >= 0 and voxel_z >= 0 and
            voxel_x < world_max_x and voxel_y < world_max_y and voxel_z < world_max_z)
        {
            // Only allow hits on blocks that are actually visible in the current slice.
            // Meshing treats blocks above top_render_y_index as air; selection should match.
            if (@hasField(WorldT, "top_render_y_index")) {
                if (voxel_y > @as(i32, world.top_render_y_index)) {
                    // Keep stepping.
                } else if (world.isBlockSolid(@intCast(voxel_x), @intCast(voxel_y), @intCast(voxel_z))) {
                    return .{ .x = @intCast(voxel_x), .y = @intCast(voxel_y), .z = @intCast(voxel_z), .hit = true };
                }
            } else if (world.isBlockSolid(@intCast(voxel_x), @intCast(voxel_y), @intCast(voxel_z))) {
                return .{ .x = @intCast(voxel_x), .y = @intCast(voxel_y), .z = @intCast(voxel_z), .hit = true };
            }
        }

        if (t_max_x < t_max_y) {
            if (t_max_x < t_max_z) {
                voxel_x += step_x;
                distance = t_max_x;
                t_max_x += t_delta_x;
            } else {
                voxel_z += step_z;
                distance = t_max_z;
                t_max_z += t_delta_z;
            }
        } else {
            if (t_max_y < t_max_z) {
                voxel_y += step_y;
                distance = t_max_y;
                t_max_y += t_delta_y;
            } else {
                voxel_z += step_z;
                distance = t_max_z;
                t_max_z += t_delta_z;
            }
        }
    }

    return .{ .x = 0, .y = 0, .z = 0, .hit = false };
}
