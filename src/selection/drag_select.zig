const std = @import("std");
const raylib = @import("raylib");

const raycast = @import("raycast.zig");
pub const BlockHit = raycast.BlockHit;
pub const raycastBlock = raycast.raycastBlock;

fn intersectRayYPlane(ray: raylib.Ray, plane_y: f32) ?raylib.Vector3 {
    const denom = ray.direction.y;
    if (@abs(denom) < 0.000001) return null;
    const t = (plane_y - ray.position.y) / denom;
    return .{
        .x = ray.position.x + ray.direction.x * t,
        .y = plane_y,
        .z = ray.position.z + ray.direction.z * t,
    };
}

fn worldRectFromScreenDrag(start: raylib.Vector2, end: raylib.Vector2, camera: raylib.Camera3D, plane_y: f32) ?[4]raylib.Vector3 {
    const r0 = raylib.getScreenToWorldRay(start, camera);
    const r1 = raylib.getScreenToWorldRay(end, camera);

    const a = intersectRayYPlane(r0, plane_y) orelse return null;
    const b = intersectRayYPlane(r1, plane_y) orelse return null;

    const min_x = @min(a.x, b.x);
    const max_x = @max(a.x, b.x);
    const min_z = @min(a.z, b.z);
    const max_z = @max(a.z, b.z);

    return .{
        .{ .x = min_x, .y = plane_y, .z = min_z },
        .{ .x = max_x, .y = plane_y, .z = min_z },
        .{ .x = max_x, .y = plane_y, .z = max_z },
        .{ .x = min_x, .y = plane_y, .z = max_z },
    };
}

/// Draw the drag selection as a WORLD-ALIGNED rectangle (axis-aligned in X/Z),
/// projected into screen space as a parallelogram for the current camera.
pub fn drawSelectionRect(start: raylib.Vector2, end: raylib.Vector2, camera: raylib.Camera3D) void {
    const plane_y: f32 = camera.target.y;
    const rect = worldRectFromScreenDrag(start, end, camera, plane_y) orelse return;

    const p1 = raylib.getWorldToScreen(rect[0], camera);
    const p2 = raylib.getWorldToScreen(rect[1], camera);
    const p3 = raylib.getWorldToScreen(rect[2], camera);
    const p4 = raylib.getWorldToScreen(rect[3], camera);

    const fill_color = raylib.Color{ .r = 0, .g = 220, .b = 220, .a = 40 };
    const border_color = raylib.Color{ .r = 0, .g = 220, .b = 220, .a = 200 };

    raylib.drawTriangle(p1, p2, p3, fill_color);
    raylib.drawTriangle(p1, p3, p4, fill_color);

    raylib.drawLineV(p1, p2, border_color);
    raylib.drawLineV(p2, p3, border_color);
    raylib.drawLineV(p3, p4, border_color);
    raylib.drawLineV(p4, p1, border_color);
}

/// Select all visible surface blocks within the WORLD-ALIGNED rectangle.
///
/// Requirements on `world`:
/// - `world.addToSelection(x: u16, y: u16, z: u16) void`
/// - `@TypeOf(world.*).worldSizeBlocksX() i16` and same for Z
pub fn dragSelectBlocks(world: anytype, start: raylib.Vector2, end: raylib.Vector2, camera: raylib.Camera3D) void {
    const WorldT = @TypeOf(world.*);

    // Work in rendered-space Y (world is shifted by vertical_scroll when drawn).
    const scroll_y: f32 = @as(f32, @floatFromInt(world.vertical_scroll));
    const plane_y: f32 = camera.target.y + scroll_y;
    const rect = worldRectFromScreenDrag(start, end, camera, plane_y) orelse return;

    const min_xw = @min(rect[0].x, rect[2].x);
    const max_xw = @max(rect[0].x, rect[2].x);
    const min_zw = @min(rect[0].z, rect[2].z);
    const max_zw = @max(rect[0].z, rect[2].z);

    const world_max_x: i32 = @as(i32, WorldT.worldSizeBlocksX());
    const world_max_z: i32 = @as(i32, WorldT.worldSizeBlocksZ());

    const x0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(min_xw))), 0, world_max_x - 1);
    const x1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(max_xw))), 0, world_max_x - 1);
    const z0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(min_zw))), 0, world_max_z - 1);
    const z1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(max_zw))), 0, world_max_z - 1);

    var x: i32 = @min(x0, x1);
    while (x <= @max(x0, x1)) : (x += 1) {
        var z: i32 = @min(z0, z1);
        while (z <= @max(z0, z1)) : (z += 1) {
            const wp = raylib.Vector3{
                .x = @as(f32, @floatFromInt(x)) + 0.5,
                .y = plane_y,
                .z = @as(f32, @floatFromInt(z)) + 0.5,
            };
            const sp = raylib.getWorldToScreen(wp, camera);
            const ray = raylib.getScreenToWorldRay(sp, camera);
            const hit = raycastBlock(world, ray, 500.0);
            if (hit.hit) {
                world.addToSelection(hit.x, hit.y, hit.z);
            }
        }
    }
}

/// Populate `world`'s preview selection with all visible surface blocks within the drag rectangle.
///
/// Requirements on `world`:
/// - `world.clearPreviewSelection() void`
/// - `world.addToPreviewSelection(x: u16, y: u16, z: u16) void`
/// - `@TypeOf(world.*).worldSizeBlocksX() i16` and same for Z
pub fn dragPreviewBlocks(world: anytype, start: raylib.Vector2, end: raylib.Vector2, camera: raylib.Camera3D) void {
    const WorldT = @TypeOf(world.*);

    world.clearPreviewSelection();

    // Work in rendered-space Y (world is shifted by vertical_scroll when drawn).
    const scroll_y: f32 = @as(f32, @floatFromInt(world.vertical_scroll));
    const plane_y: f32 = camera.target.y + scroll_y;
    const rect = worldRectFromScreenDrag(start, end, camera, plane_y) orelse return;

    const min_xw = @min(rect[0].x, rect[2].x);
    const max_xw = @max(rect[0].x, rect[2].x);
    const min_zw = @min(rect[0].z, rect[2].z);
    const max_zw = @max(rect[0].z, rect[2].z);

    const world_max_x: i32 = @as(i32, WorldT.worldSizeBlocksX());
    const world_max_z: i32 = @as(i32, WorldT.worldSizeBlocksZ());

    const x0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(min_xw))), 0, world_max_x - 1);
    const x1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(max_xw))), 0, world_max_x - 1);
    const z0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(min_zw))), 0, world_max_z - 1);
    const z1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(max_zw))), 0, world_max_z - 1);

    var x: i32 = @min(x0, x1);
    while (x <= @max(x0, x1)) : (x += 1) {
        var z: i32 = @min(z0, z1);
        while (z <= @max(z0, z1)) : (z += 1) {
            const wp = raylib.Vector3{
                .x = @as(f32, @floatFromInt(x)) + 0.5,
                .y = plane_y,
                .z = @as(f32, @floatFromInt(z)) + 0.5,
            };
            const sp = raylib.getWorldToScreen(wp, camera);
            const ray = raylib.getScreenToWorldRay(sp, camera);
            const hit = raycastBlock(world, ray, 500.0);
            if (hit.hit) {
                world.addToPreviewSelection(hit.x, hit.y, hit.z);
            }
        }
    }
}

/// Populate `world`'s preview selection with all SOLID blocks within the drag rectangle
/// on a fixed internal-Y plane ("tunnel" behavior).
///
/// This does NOT try to find the visible surface. It selects blocks at `plane_internal_y`
/// for all X/Z cells inside the screen-drag rectangle projected onto that plane.
pub fn dragPreviewBlocksFixedY(world: anytype, start: raylib.Vector2, end: raylib.Vector2, camera: raylib.Camera3D, plane_internal_y: i16) void {
    const WorldT = @TypeOf(world.*);

    world.clearPreviewSelection();

    const world_max_x: i32 = @as(i32, WorldT.worldSizeBlocksX());
    const world_max_y: i32 = @as(i32, WorldT.worldSizeBlocksY());
    const world_max_z: i32 = @as(i32, WorldT.worldSizeBlocksZ());

    const yi: i32 = @as(i32, plane_internal_y);
    if (yi < 0 or yi >= world_max_y) return;

    // Project the screen drag onto the fixed Y plane in rendered space.
    const scroll_y: f32 = @as(f32, @floatFromInt(world.vertical_scroll));
    const plane_y: f32 = @as(f32, @floatFromInt(plane_internal_y)) + 0.5 + scroll_y;
    const rect = worldRectFromScreenDrag(start, end, camera, plane_y) orelse return;

    const min_xw = @min(rect[0].x, rect[2].x);
    const max_xw = @max(rect[0].x, rect[2].x);
    const min_zw = @min(rect[0].z, rect[2].z);
    const max_zw = @max(rect[0].z, rect[2].z);

    const x0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(min_xw))), 0, world_max_x - 1);
    const x1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(max_xw))), 0, world_max_x - 1);
    const z0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(min_zw))), 0, world_max_z - 1);
    const z1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(max_zw))), 0, world_max_z - 1);

    var x: i32 = @min(x0, x1);
    while (x <= @max(x0, x1)) : (x += 1) {
        var z: i32 = @min(z0, z1);
        while (z <= @max(z0, z1)) : (z += 1) {
            if (world.isBlockSolid(@intCast(x), @intCast(yi), @intCast(z))) {
                world.addToPreviewSelection(@intCast(x), @intCast(yi), @intCast(z));
            }
        }
    }
}
