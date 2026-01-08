// Task queue system for Goblinoria workers

const std = @import("std");
const world_types = @import("world/types.zig");
const BlockCoord = world_types.BlockCoord;
const BlockType = world_types.BlockType;

pub const TaskType = enum {
    dig,
    place,
    stairs,
};

pub const TaskStatus = enum {
    pending,
    in_progress,
    completed,
};

pub const Task = struct {
    id: u32,
    position: BlockCoord,
    task_type: TaskType,
    status: TaskStatus,
    assigned_worker: ?u32,
    /// For place/stairs tasks: which material to place
    place_material: BlockType,

    pub fn init(id: u32, position: BlockCoord, task_type: TaskType) Task {
        return .{
            .id = id,
            .position = position,
            .task_type = task_type,
            .status = .pending,
            .assigned_worker = null,
            .place_material = 1, // Default material (sand)
        };
    }

    pub fn initPlace(id: u32, position: BlockCoord, material: BlockType) Task {
        return .{
            .id = id,
            .position = position,
            .task_type = .place,
            .status = .pending,
            .assigned_worker = null,
            .place_material = material,
        };
    }

    pub fn initStairs(id: u32, position: BlockCoord) Task {
        return .{
            .id = id,
            .position = position,
            .task_type = .stairs,
            .status = .pending,
            .assigned_worker = null,
            .place_material = world_types.STAIR_BLOCK_ID,
        };
    }
};

pub const TaskQueue = struct {
    tasks: std.ArrayListUnmanaged(Task),
    next_id: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TaskQueue {
        return .{
            .tasks = .{},
            .next_id = 1,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TaskQueue) void {
        self.tasks.deinit(self.allocator);
    }

    /// Add a new task and return its ID
    pub fn addTask(self: *TaskQueue, position: BlockCoord, task_type: TaskType) !u32 {
        // Check if task already exists at this position with same type
        for (self.tasks.items) |task| {
            if (task.position.x == position.x and
                task.position.y == position.y and
                task.position.z == position.z and
                task.task_type == task_type and
                task.status != .completed)
            {
                return task.id; // Already exists
            }
        }

        const id = self.next_id;
        self.next_id += 1;

        try self.tasks.append(self.allocator, Task.init(id, position, task_type));
        return id;
    }

    /// Add a place task with a specific material
    pub fn addPlaceTask(self: *TaskQueue, position: BlockCoord, material: BlockType) !u32 {
        // Check if task already exists at this position
        for (self.tasks.items) |task| {
            if (task.position.x == position.x and
                task.position.y == position.y and
                task.position.z == position.z and
                task.task_type == .place and
                task.status != .completed)
            {
                return task.id;
            }
        }

        const id = self.next_id;
        self.next_id += 1;

        try self.tasks.append(self.allocator, Task.initPlace(id, position, material));
        return id;
    }

    /// Add a stairs conversion task (swap to stair block)
    pub fn addStairsTask(self: *TaskQueue, position: BlockCoord) !u32 {
        // Check if task already exists at this position
        for (self.tasks.items) |task| {
            if (task.position.x == position.x and
                task.position.y == position.y and
                task.position.z == position.z and
                task.task_type == .stairs and
                task.status != .completed)
            {
                return task.id;
            }
        }

        const id = self.next_id;
        self.next_id += 1;

        try self.tasks.append(self.allocator, Task.initStairs(id, position));
        return id;
    }

    /// Remove a task by ID
    pub fn removeTask(self: *TaskQueue, id: u32) void {
        for (self.tasks.items, 0..) |task, i| {
            if (task.id == id) {
                _ = self.tasks.swapRemove(i);
                return;
            }
        }
    }

    /// Get a task by ID (mutable)
    pub fn getTask(self: *TaskQueue, id: u32) ?*Task {
        for (self.tasks.items) |*task| {
            if (task.id == id) {
                return task;
            }
        }
        return null;
    }

    /// Find the nearest pending task to a position
    pub fn findNearestPendingTask(self: *TaskQueue, from_x: f32, from_y: f32, from_z: f32) ?*Task {
        var nearest: ?*Task = null;
        var nearest_dist_sq: f32 = std.math.floatMax(f32);

        for (self.tasks.items) |*task| {
            if (task.status != .pending) continue;

            const dx = @as(f32, @floatFromInt(task.position.x)) - from_x;
            const dy = @as(f32, @floatFromInt(task.position.y)) - from_y;
            const dz = @as(f32, @floatFromInt(task.position.z)) - from_z;
            const dist_sq = dx * dx + dy * dy + dz * dz;

            if (dist_sq < nearest_dist_sq) {
                nearest_dist_sq = dist_sq;
                nearest = task;
            }
        }

        return nearest;
    }

    /// Find the nearest pending DIG task (no Y restriction)
    pub fn findNearestDigTask(self: *TaskQueue, from_x: f32, from_y: f32, from_z: f32) ?*Task {
        var nearest: ?*Task = null;
        var nearest_dist_sq: f32 = std.math.floatMax(f32);

        for (self.tasks.items) |*task| {
            if (task.status != .pending) continue;
            if (task.task_type != .dig) continue;

            const dx = @as(f32, @floatFromInt(task.position.x)) - from_x;
            const dy = @as(f32, @floatFromInt(task.position.y)) - from_y;
            const dz = @as(f32, @floatFromInt(task.position.z)) - from_z;
            const dist_sq = dx * dx + dy * dy + dz * dz;

            if (dist_sq < nearest_dist_sq) {
                nearest_dist_sq = dist_sq;
                nearest = task;
            }
        }

        return nearest;
    }

    /// Find the nearest pending PLACE task (can place at any reachable location)
    pub fn findNearestPlaceTask(self: *TaskQueue, from_x: f32, from_y: f32, from_z: f32) ?*Task {
        var nearest: ?*Task = null;
        var nearest_dist_sq: f32 = std.math.floatMax(f32);

        for (self.tasks.items) |*task| {
            if (task.status != .pending) continue;
            if (task.task_type != .place) continue;

            const dx = @as(f32, @floatFromInt(task.position.x)) - from_x;
            const dy = @as(f32, @floatFromInt(task.position.y)) - from_y;
            const dz = @as(f32, @floatFromInt(task.position.z)) - from_z;
            const dist_sq = dx * dx + dy * dy + dz * dz;

            if (dist_sq < nearest_dist_sq) {
                nearest_dist_sq = dist_sq;
                nearest = task;
            }
        }

        return nearest;
    }

    /// Find the nearest pending STAIRS task at current, two-below, or one-above Y level
    pub fn findNearestStairsTaskAtLevel(self: *TaskQueue, from_x: f32, from_y: f32, from_z: f32, y_level: u16) ?*Task {
        var nearest: ?*Task = null;
        var nearest_dist_sq: f32 = std.math.floatMax(f32);
        const below_y = y_level -| 1;
        const below2_y = y_level -| 2;
        const above_y = y_level +| 1;

        for (self.tasks.items) |*task| {
            if (task.status != .pending) continue;
            if (task.task_type != .stairs) continue;
            if (task.position.y != y_level and task.position.y != below_y and task.position.y != below2_y and task.position.y != above_y) continue;

            const dx = @as(f32, @floatFromInt(task.position.x)) - from_x;
            const dy = @as(f32, @floatFromInt(task.position.y)) - from_y;
            const dz = @as(f32, @floatFromInt(task.position.z)) - from_z;
            const dist_sq = dx * dx + dy * dy + dz * dz;

            if (dist_sq < nearest_dist_sq) {
                nearest_dist_sq = dist_sq;
                nearest = task;
            }
        }

        return nearest;
    }

    /// Remove all completed tasks
    pub fn cleanupCompleted(self: *TaskQueue) void {
        var i: usize = 0;
        while (i < self.tasks.items.len) {
            if (self.tasks.items[i].status == .completed) {
                _ = self.tasks.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Get count of pending tasks
    pub fn pendingCount(self: *const TaskQueue) usize {
        var count: usize = 0;
        for (self.tasks.items) |task| {
            if (task.status == .pending) count += 1;
        }
        return count;
    }

    /// Get count of in-progress tasks
    pub fn inProgressCount(self: *const TaskQueue) usize {
        var count: usize = 0;
        for (self.tasks.items) |task| {
            if (task.status == .in_progress) count += 1;
        }
        return count;
    }

    /// Get total task count (excluding completed)
    pub fn activeCount(self: *const TaskQueue) usize {
        var count: usize = 0;
        for (self.tasks.items) |task| {
            if (task.status != .completed) count += 1;
        }
        return count;
    }
};
