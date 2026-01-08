// A* Pathfinding for Goblinoria voxel world

const std = @import("std");
const world_types = @import("world/types.zig");
const BlockCoord = world_types.BlockCoord;
const BlockType = world_types.BlockType;
const STAIR_BLOCK_ID = world_types.STAIR_BLOCK_ID;

/// Node for A* pathfinding
const PathNode = struct {
    pos: BlockCoord,
    g_cost: u32, // Cost from start
    h_cost: u32, // Heuristic to goal
    parent_index: ?usize, // Index of parent in closed set

    pub fn fCost(self: *const PathNode) u32 {
        return self.g_cost + self.h_cost;
    }
};

/// Comparison function for priority queue (min-heap by f_cost)
fn nodeCompare(context: void, a: PathNode, b: PathNode) std.math.Order {
    _ = context;
    const a_f = a.fCost();
    const b_f = b.fCost();
    if (a_f < b_f) return .lt;
    if (a_f > b_f) return .gt;
    // Tie-break by h_cost (prefer closer to goal)
    if (a.h_cost < b.h_cost) return .lt;
    if (a.h_cost > b.h_cost) return .gt;
    return .eq;
}

pub const Pathfinder = struct {
    allocator: std.mem.Allocator,

    fn isBlockingForMovement(block: BlockType) bool {
        return block != 0 and block != STAIR_BLOCK_ID;
    }

    pub fn init(allocator: std.mem.Allocator) Pathfinder {
        return .{ .allocator = allocator };
    }

    /// Check if a position is walkable (solid block below, air at position)
    pub fn isWalkable(world: anytype, x: i32, y: i32, z: i32) bool {
        const WorldT = @TypeOf(world.*);
        const world_max_x: i32 = @as(i32, WorldT.worldSizeBlocksX());
        const world_max_y: i32 = @as(i32, WorldT.worldSizeBlocksY());
        const world_max_z: i32 = @as(i32, WorldT.worldSizeBlocksZ());

        // Out of bounds = not walkable
        if (x < 0 or y < 0 or z < 0) return false;
        if (x >= world_max_x or y >= world_max_y or z >= world_max_z) return false;

        // Need solid block below to stand on
        if (y == 0) return false; // Can't stand on nothing
        const below_block = world.getBlock(@intCast(x), @intCast(y - 1), @intCast(z));
        const below_solid = below_block != 0;
        if (!below_solid) return false;

        // Current position must be air or stairs (so we can stand there)
        const current_block = world.getBlock(@intCast(x), @intCast(y), @intCast(z));
        if (isBlockingForMovement(current_block)) return false;

        return true;
    }

    /// Calculate Manhattan distance heuristic
    fn heuristic(a: BlockCoord, b: BlockCoord) u32 {
        const dx: u32 = if (a.x > b.x) a.x - b.x else b.x - a.x;
        const dy: u32 = if (a.y > b.y) a.y - b.y else b.y - a.y;
        const dz: u32 = if (a.z > b.z) a.z - b.z else b.z - a.z;
        return dx + dy + dz;
    }

    /// Get valid neighbor positions for pathfinding
    /// Includes same-level movement and step up/down (1 block height difference)
    fn getNeighbors(world: anytype, pos: BlockCoord, neighbors: *[18]?BlockCoord) void {
        const WorldT = @TypeOf(world.*);
        const world_max_y: i32 = @as(i32, WorldT.worldSizeBlocksY());
        const x: i32 = @intCast(pos.x);
        const y: i32 = @intCast(pos.y);
        const z: i32 = @intCast(pos.z);

        // Cardinal directions only (no diagonal corner-cutting)
        const directions = [_][2]i32{
            .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 },
        };

        var idx: usize = 0;

        // Same level movement
        for (directions) |dir| {
            const nx = x + dir[0];
            const nz = z + dir[1];
            if (isWalkable(world, nx, y, nz)) {
                neighbors[idx] = .{
                    .x = @intCast(nx),
                    .y = @intCast(y),
                    .z = @intCast(nz),
                };
            } else {
                neighbors[idx] = null;
            }
            idx += 1;
        }

        // Step up (climb 1 block) - only cardinal directions
        const cardinal_dirs = [_][2]i32{
            .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 },
        };

        for (cardinal_dirs) |dir| {
            const nx = x + dir[0];
            const nz = z + dir[1];
            const ny = y + 1;

            // Can step up if: destination is walkable AND current head space is clear
            if (ny < world_max_y) {
                const head_block = world.getBlock(@intCast(x), @intCast(y + 1), @intCast(z));
                if (isWalkable(world, nx, ny, nz) and !isBlockingForMovement(head_block)) {
                    neighbors[idx] = .{
                        .x = @intCast(nx),
                        .y = @intCast(ny),
                        .z = @intCast(nz),
                    };
                } else {
                    neighbors[idx] = null;
                }
            } else {
                neighbors[idx] = null;
            }
            idx += 1;
        }

        // Step down (descend 1 block) - only cardinal directions
        for (cardinal_dirs) |dir| {
            const nx = x + dir[0];
            const nz = z + dir[1];
            const ny = y - 1;

            // Can step down if destination is walkable
            if (ny >= 0 and isWalkable(world, nx, ny, nz)) {
                neighbors[idx] = .{
                    .x = @intCast(nx),
                    .y = @intCast(ny),
                    .z = @intCast(nz),
                };
            } else {
                neighbors[idx] = null;
            }
            idx += 1;
        }

        // Fill remaining slots with null
        while (idx < 18) : (idx += 1) {
            neighbors[idx] = null;
        }
    }

    /// Find path from start to goal using A*
    /// Returns allocated slice of BlockCoords (caller must free), or null if no path
    pub fn findPath(self: *Pathfinder, world: anytype, start: BlockCoord, goal: BlockCoord) ?[]BlockCoord {
        const max_iterations: usize = 10000;

        // Priority queue for open set
        var open_set = std.PriorityQueue(PathNode, void, nodeCompare).init(self.allocator, {});
        defer open_set.deinit();

        // Closed set - stores visited nodes
        var closed_set: std.ArrayList(PathNode) = .{};
        defer closed_set.deinit(self.allocator);

        // Track which positions are in open/closed sets
        var visited = std.AutoHashMap(BlockCoord, usize).init(self.allocator);
        defer visited.deinit();

        // Start node
        const start_node = PathNode{
            .pos = start,
            .g_cost = 0,
            .h_cost = heuristic(start, goal),
            .parent_index = null,
        };

        open_set.add(start_node) catch return null;

        var iterations: usize = 0;
        while (open_set.count() > 0 and iterations < max_iterations) : (iterations += 1) {
            const current = open_set.remove();

            // Check if we reached the goal (or adjacent to goal for dig tasks)
            if (current.pos.x == goal.x and current.pos.y == goal.y and current.pos.z == goal.z) {
                // Reconstruct path
                return self.reconstructPath(&closed_set, current);
            }

            // Check if adjacent to goal (good enough for work tasks)
            const dx = if (current.pos.x > goal.x) current.pos.x - goal.x else goal.x - current.pos.x;
            const dy = if (current.pos.y > goal.y) current.pos.y - goal.y else goal.y - current.pos.y;
            const dz = if (current.pos.z > goal.z) current.pos.z - goal.z else goal.z - current.pos.z;
            if (dx <= 1 and dy <= 1 and dz <= 1) {
                return self.reconstructPath(&closed_set, current);
            }

            // Add to closed set
            const closed_index = closed_set.items.len;
            closed_set.append(self.allocator, current) catch return null;
            visited.put(current.pos, closed_index) catch return null;

            // Process neighbors
            var neighbors: [18]?BlockCoord = undefined;
            getNeighbors(world, current.pos, &neighbors);

            for (neighbors) |maybe_neighbor| {
                const neighbor_pos = maybe_neighbor orelse continue;

                // Skip if already in closed set
                if (visited.contains(neighbor_pos)) continue;

                const g_cost = current.g_cost + 1;
                const h_cost = heuristic(neighbor_pos, goal);

                const neighbor_node = PathNode{
                    .pos = neighbor_pos,
                    .g_cost = g_cost,
                    .h_cost = h_cost,
                    .parent_index = closed_index,
                };

                open_set.add(neighbor_node) catch return null;
            }
        }

        // No path found
        return null;
    }

    /// Reconstruct path from closed set
    fn reconstructPath(self: *Pathfinder, closed_set: *std.ArrayList(PathNode), final_node: PathNode) ?[]BlockCoord {
        // Count path length
        var path_length: usize = 1;
        var current = final_node;
        while (current.parent_index) |parent_idx| {
            path_length += 1;
            current = closed_set.items[parent_idx];
        }

        // Allocate path
        const path = self.allocator.alloc(BlockCoord, path_length) catch return null;

        // Fill path in reverse order
        var idx = path_length;
        current = final_node;
        while (true) {
            idx -= 1;
            path[idx] = current.pos;
            if (current.parent_index) |parent_idx| {
                current = closed_set.items[parent_idx];
            } else {
                break;
            }
        }

        return path;
    }

    /// Free a path allocated by findPath
    pub fn freePath(self: *Pathfinder, path: []BlockCoord) void {
        self.allocator.free(path);
    }
};
