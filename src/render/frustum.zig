const std = @import("std");
const raylib = @import("raylib");

const v3 = @import("vec3.zig");

pub const Frustum = struct {
    // Camera basis + ortho extents
    pos: raylib.Vector3,
    right: raylib.Vector3,
    up: raylib.Vector3,
    forward: raylib.Vector3,
    half_width: f32,
    half_height: f32,
    near_dist: f32,
    far_dist: f32,

    // Coarse world-space AABB of the frustum (used only to bound chunk iteration)
    aabb_min_x: f32,
    aabb_max_x: f32,
    aabb_min_y: f32,
    aabb_max_y: f32,
    aabb_min_z: f32,
    aabb_max_z: f32,
};

/// Calculate an orthographic frustum for chunk culling.
///
/// `padding` expands the frustum box in all directions (world units).
/// This prevents edge-case culling of chunks near the camera boundary.
pub fn calculateOrthoFrustum(
    camera: raylib.Camera3D,
    screen_width: f32,
    screen_height: f32,
    world_min: raylib.Vector3,
    world_max: raylib.Vector3,
    padding: f32,
) Frustum {
    const aspect = screen_width / screen_height;

    // raylib orthographic: fovy is viewport *width* in world units (not an angle).
    // Apply padding here so the frustum box is uniformly expanded.
    const half_width = camera.fovy / 2.0 + padding;
    const half_height = half_width / aspect;

    // Camera basis vectors
    const forward = v3.normalize(v3.sub(camera.target, camera.position));
    const right = v3.normalize(v3.cross(forward, camera.up));
    const up = v3.normalize(v3.cross(right, forward));

    // Project world AABB corners onto forward axis to get tight near/far.
    var min_d: f32 = std.math.inf(f32);
    var max_d: f32 = -std.math.inf(f32);
    const corners = [_]raylib.Vector3{
        .{ .x = world_min.x, .y = world_min.y, .z = world_min.z },
        .{ .x = world_min.x, .y = world_min.y, .z = world_max.z },
        .{ .x = world_min.x, .y = world_max.y, .z = world_min.z },
        .{ .x = world_min.x, .y = world_max.y, .z = world_max.z },
        .{ .x = world_max.x, .y = world_min.y, .z = world_min.z },
        .{ .x = world_max.x, .y = world_min.y, .z = world_max.z },
        .{ .x = world_max.x, .y = world_max.y, .z = world_min.z },
        .{ .x = world_max.x, .y = world_max.y, .z = world_max.z },
    };
    for (corners) |c| {
        const d = v3.dot(forward, v3.sub(c, camera.position));
        min_d = @min(min_d, d);
        max_d = @max(max_d, d);
    }

    // Expand near/far by padding. Negative near is fine for ortho (no z-fighting).
    const near_dist = min_d - padding;
    const far_dist = max_d + padding;

    // Build frustum corners and compute world-space AABB.
    const center_near = v3.add(camera.position, v3.scale(forward, near_dist));
    const center_far = v3.add(camera.position, v3.scale(forward, far_dist));

    var aabb_min = raylib.Vector3{ .x = std.math.inf(f32), .y = std.math.inf(f32), .z = std.math.inf(f32) };
    var aabb_max = raylib.Vector3{ .x = -std.math.inf(f32), .y = -std.math.inf(f32), .z = -std.math.inf(f32) };

    for ([_]raylib.Vector3{ center_near, center_far }) |center| {
        for ([_][2]f32{
            .{ -half_width, -half_height },
            .{ -half_width, half_height },
            .{ half_width, -half_height },
            .{ half_width, half_height },
        }) |off| {
            const corner = v3.add(v3.add(center, v3.scale(right, off[0])), v3.scale(up, off[1]));
            aabb_min.x = @min(aabb_min.x, corner.x);
            aabb_max.x = @max(aabb_max.x, corner.x);
            aabb_min.y = @min(aabb_min.y, corner.y);
            aabb_max.y = @max(aabb_max.y, corner.y);
            aabb_min.z = @min(aabb_min.z, corner.z);
            aabb_max.z = @max(aabb_max.z, corner.z);
        }
    }

    return .{
        .pos = camera.position,
        .right = right,
        .up = up,
        .forward = forward,
        .half_width = half_width,
        .half_height = half_height,
        .near_dist = near_dist,
        .far_dist = far_dist,
        .aabb_min_x = aabb_min.x,
        .aabb_max_x = aabb_max.x,
        .aabb_min_y = aabb_min.y,
        .aabb_max_y = aabb_max.y,
        .aabb_min_z = aabb_min.z,
        .aabb_max_z = aabb_max.z,
    };
}

pub fn isBlockInFrustum(frustum: Frustum, x: f32, y: f32, z: f32) bool {
    const half: f32 = 0.5;
    if (x + half < frustum.aabb_min_x or x - half > frustum.aabb_max_x) return false;
    if (y + half < frustum.aabb_min_y or y - half > frustum.aabb_max_y) return false;
    if (z + half < frustum.aabb_min_z or z - half > frustum.aabb_max_z) return false;
    return true;
}

pub fn isChunkInFrustum(frustum: Frustum, min: raylib.Vector3, max: raylib.Vector3) bool {
    // Tight orthographic frustum test in camera space.
    // Transform AABB to camera axes using center/extents projection.
    const center = raylib.Vector3{
        .x = (min.x + max.x) * 0.5,
        .y = (min.y + max.y) * 0.5,
        .z = (min.z + max.z) * 0.5,
    };
    const ext = raylib.Vector3{
        .x = (max.x - min.x) * 0.5,
        .y = (max.y - min.y) * 0.5,
        .z = (max.z - min.z) * 0.5,
    };

    const rel = v3.sub(center, frustum.pos);

    const rx = ext.x * @abs(frustum.right.x) + ext.y * @abs(frustum.right.y) + ext.z * @abs(frustum.right.z);
    const ux = ext.x * @abs(frustum.up.x) + ext.y * @abs(frustum.up.y) + ext.z * @abs(frustum.up.z);
    const fx = ext.x * @abs(frustum.forward.x) + ext.y * @abs(frustum.forward.y) + ext.z * @abs(frustum.forward.z);

    const c_right = v3.dot(frustum.right, rel);
    if (c_right + rx < -frustum.half_width or c_right - rx > frustum.half_width) return false;

    const c_up = v3.dot(frustum.up, rel);
    if (c_up + ux < -frustum.half_height or c_up - ux > frustum.half_height) return false;

    const c_fwd = v3.dot(frustum.forward, rel);
    if (c_fwd + fx < frustum.near_dist or c_fwd - fx > frustum.far_dist) return false;

    return true;
}
