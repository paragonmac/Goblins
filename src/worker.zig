// Worker system for Goblinoria

const std = @import("std");
const world_types = @import("world/types.zig");
const task_mod = @import("task.zig");
const pathfinding = @import("pathfinding.zig");
const BlockCoord = world_types.BlockCoord;
const Task = task_mod.Task;
const TaskQueue = task_mod.TaskQueue;
const TaskStatus = task_mod.TaskStatus;
const Pathfinder = pathfinding.Pathfinder;

pub const WorkerState = enum {
    idle, // No task, looking for work
    moving, // Walking to task position
    working, // Executing task (dig/place)
};

const WorkerDebugNote = enum {
    none,
    no_task,
    no_visible_task,
    no_path_dig,
    no_path_place,
    no_path_stairs,
};

fn debugNoteLabel(note: WorkerDebugNote) []const u8 {
    return switch (note) {
        .none => "none",
        .no_task => "no_task",
        .no_visible_task => "no_visible_task",
        .no_path_dig => "no_path_dig",
        .no_path_place => "no_path_place",
        .no_path_stairs => "no_path_stairs",
    };
}

pub const Worker = struct {
    id: u32,
    x: f32,
    y: f32,
    z: f32,
    state: WorkerState,
    current_task_id: ?u32,

    // Movement
    target_x: f32,
    target_y: f32,
    target_z: f32,
    move_speed: f32, // Blocks per second

    // Pathfinding
    path: ?[]BlockCoord,
    path_index: usize,

    // Work timing
    work_timer: f32, // Time remaining on current work action
    idle_timer: f32, // Time spent idle (for pause between tasks)
    debug_timer: f32,
    debug_note: WorkerDebugNote,
    debug_pending_total: u32,
    debug_pending_dig_total: u32,
    debug_pending_dig_visible: u32,
    debug_pending_stairs_total: u32,
    debug_pending_stairs_visible: u32,
    debug_pending_place_total: u32,
    debug_worker_y: u16,
    debug_stairs_nearest_y: ?u16,
    rng: std.Random.DefaultPrng,
    wander_wait: f32,

    const WORK_DURATION: f32 = 0.5; // Time to complete a task
    const IDLE_PAUSE: f32 = 0.5; // Pause between tasks (natural feel)
    const DEFAULT_SPEED: f32 = 4.0; // Blocks per second
    const WANDER_WAIT_MIN: f32 = 3.0;
    const WANDER_WAIT_MAX: f32 = 5.0;

    pub fn init(id: u32, x: f32, y: f32, z: f32) Worker {
        const seed =
            @as(u64, id) ^
            (@as(u64, @intFromFloat(x)) << 16) ^
            (@as(u64, @intFromFloat(y)) << 32) ^
            (@as(u64, @intFromFloat(z)) << 48);
        var rng = std.Random.DefaultPrng.init(seed);
        const initial_wait = WANDER_WAIT_MIN + (WANDER_WAIT_MAX - WANDER_WAIT_MIN) * rng.random().float(f32);
        return .{
            .id = id,
            .x = x,
            .y = y,
            .z = z,
            .state = .idle,
            .current_task_id = null,
            .target_x = x,
            .target_y = y,
            .target_z = z,
            .move_speed = DEFAULT_SPEED,
            .path = null,
            .path_index = 0,
            .work_timer = 0,
            .idle_timer = 0,
            .debug_timer = 1.0,
            .debug_note = .none,
            .debug_pending_total = 0,
            .debug_pending_dig_total = 0,
            .debug_pending_dig_visible = 0,
            .debug_pending_stairs_total = 0,
            .debug_pending_stairs_visible = 0,
            .debug_pending_place_total = 0,
            .debug_worker_y = 0,
            .debug_stairs_nearest_y = null,
            .rng = rng,
            .wander_wait = initial_wait,
        };
    }

    pub fn getBlockCoord(self: *const Worker) BlockCoord {
        return .{
            .x = @intFromFloat(@floor(self.x + 0.5)),
            .y = @intFromFloat(@floor(self.y)),
            .z = @intFromFloat(@floor(self.z + 0.5)),
        };
    }

    /// Update worker each frame
    pub fn update(self: *Worker, dt: f32, world: anytype, task_queue: *TaskQueue, pf: *Pathfinder) void {
        self.updateDebugCounts(task_queue);
        switch (self.state) {
            .idle => self.updateIdle(dt, world, task_queue, pf),
            .moving => self.updateMoving(dt, pf),
            .working => self.updateWorking(dt, world, task_queue, pf),
        }
        self.tickDebug(dt);
    }

    fn updateIdle(self: *Worker, dt: f32, world: anytype, task_queue: *TaskQueue, pf: *Pathfinder) void {
        // Wait for idle pause to complete
        if (self.idle_timer > 0) {
            self.idle_timer -= dt;
            return;
        }

        // Get worker's current Y level (the block they're standing on)
        const worker_y: u16 = @intFromFloat(@floor(self.y));

        // Look for nearest task - dig/stairs/place are all player-planned, workers handle reachability
        // First try dig tasks, then stairs, then place
        var maybe_task: ?*Task = task_queue.findNearestDigTask(self.x, self.y, self.z);
        if (maybe_task == null) {
            maybe_task = task_queue.findNearestStairsTaskAtLevel(self.x, self.y, self.z, worker_y);
        }
        if (maybe_task == null) {
            maybe_task = task_queue.findNearestPlaceTask(self.x, self.y, self.z);
        }

        if (maybe_task) |task| {
            // Try to find a path to the task
            const start = self.getBlockCoord();

            // Find path to task position (we want to stand near it)
            const maybe_path = if (task.task_type == .stairs)
                self.findPathToStairs(world, start, task.position, pf)
            else
                pf.findPath(world, start, task.position);

            if (maybe_path) |found_path| {
                self.debug_note = .none;
                // Claim the task
                task.status = .in_progress;
                task.assigned_worker = self.id;
                self.current_task_id = task.id;

                // Store the path
                self.path = found_path;
                self.path_index = 0;

                // Set initial target to first path node
                if (found_path.len > 0) {
                    self.setTargetFromPath();
                    self.state = .moving;
                } else {
                    // Path is empty, we're already at destination
                    self.state = .working;
                    self.work_timer = WORK_DURATION;
                }
            } else {
                // No path found - skip this task for now
                // The task remains pending for other workers or retry later
                self.debug_note = switch (task.task_type) {
                    .dig => .no_path_dig,
                    .place => .no_path_place,
                    .stairs => .no_path_stairs,
                };
            }
        } else {
            self.debug_note = if (self.debug_pending_total == 0) .no_task else .no_visible_task;
            self.updateWander(dt, world, pf);
        }
    }

    fn setTargetFromPath(self: *Worker) void {
        if (self.path) |p| {
            if (self.path_index < p.len) {
                const node = p[self.path_index];
                self.target_x = @floatFromInt(node.x);
                self.target_y = @floatFromInt(node.y);
                self.target_z = @floatFromInt(node.z);
            }
        }
    }

    fn updateMoving(self: *Worker, dt: f32, pf: *Pathfinder) void {
        // Calculate distance to current target
        const dx = self.target_x - self.x;
        const dy = self.target_y - self.y;
        const dz = self.target_z - self.z;
        const dist = @sqrt(dx * dx + dy * dy + dz * dz);

        if (dist < 0.15) {
            // Arrived at current path node
            self.x = self.target_x;
            self.y = self.target_y;
            self.z = self.target_z;

            // Advance to next path node
            self.path_index += 1;

            if (self.path) |p| {
                if (self.path_index >= p.len) {
                    // Reached end of path - start working if this was a task
                    pf.freePath(p);
                    self.path = null;
                    if (self.current_task_id) |_| {
                        self.state = .working;
                        self.work_timer = WORK_DURATION;
                    } else {
                        self.state = .idle;
                        self.wander_wait = self.randomRangeF32(WANDER_WAIT_MIN, WANDER_WAIT_MAX);
                    }
                    return;
                }
                // Set next target
                self.setTargetFromPath();
            } else {
                // No path, shouldn't happen
                self.state = if (self.current_task_id != null) .working else .idle;
                if (self.current_task_id != null) {
                    self.work_timer = WORK_DURATION;
                } else {
                    self.wander_wait = self.randomRangeF32(WANDER_WAIT_MIN, WANDER_WAIT_MAX);
                }
            }
            return;
        }

        // Move towards target
        const move_dist = self.move_speed * dt;
        if (move_dist >= dist) {
            self.x = self.target_x;
            self.y = self.target_y;
            self.z = self.target_z;
        } else {
            const factor = move_dist / dist;
            self.x += dx * factor;
            self.y += dy * factor;
            self.z += dz * factor;
        }
    }

    fn updateWorking(self: *Worker, dt: f32, world: anytype, task_queue: *TaskQueue, pf: *Pathfinder) void {
        _ = pf;
        self.work_timer -= dt;

        if (self.work_timer <= 0) {
            // Work complete - execute the task
            if (self.current_task_id) |task_id| {
                if (task_queue.getTask(task_id)) |task| {
                    // Execute the task
                    switch (task.task_type) {
                        .dig => {
                            // Remove the block
                            world.setBlock(task.position.x, task.position.y, task.position.z, 0);
                        },
                        .place => {
                            // Place a block
                            world.setBlock(task.position.x, task.position.y, task.position.z, task.place_material);
                        },
                        .stairs => {
                            // Convert block to stairs
                            world.setBlock(task.position.x, task.position.y, task.position.z, task.place_material);
                        },
                    }

                    // Mark task completed
                    task.status = .completed;
                }
            }

            // Return to idle state with pause
            self.state = .idle;
            self.current_task_id = null;
            self.idle_timer = IDLE_PAUSE;
        }
    }

    /// Release current task back to pending (e.g., if path is blocked)
    pub fn releaseTask(self: *Worker, task_queue: *TaskQueue, pf: *Pathfinder) void {
        if (self.current_task_id) |task_id| {
            if (task_queue.getTask(task_id)) |task| {
                task.status = .pending;
                task.assigned_worker = null;
            }
        }
        if (self.path) |p| {
            pf.freePath(p);
            self.path = null;
        }
        self.current_task_id = null;
        self.state = .idle;
    }

    /// Clean up any allocated resources
    pub fn deinit(self: *Worker, pf: *Pathfinder) void {
        if (self.path) |p| {
            pf.freePath(p);
            self.path = null;
        }
    }

    fn tickDebug(self: *Worker, dt: f32) void {
        self.debug_timer -= dt;
        if (self.debug_timer > 0) return;
        self.debug_timer = 1.0;

        const xi: i32 = @intFromFloat(@floor(self.x + 0.5));
        const yi: i32 = @intFromFloat(@floor(self.y));
        const zi: i32 = @intFromFloat(@floor(self.z + 0.5));

        const state_label = switch (self.state) {
            .idle => "idle",
            .moving => "moving",
            .working => "working",
        };

        const stairs_y_label: []const u8 = if (self.debug_stairs_nearest_y == null) "none" else "set";
        if (self.current_task_id) |task_id| {
            std.debug.print(
                "worker({d}) state={s} note={s} pos=({d},{d},{d}) y={d} task={d} pending=total:{d} dig:{d}/{d} stairs:{d}/{d} place:{d} stairs_y={s}",
                .{
                    self.id,
                    state_label,
                    debugNoteLabel(self.debug_note),
                    xi,
                    yi,
                    zi,
                    self.debug_worker_y,
                    task_id,
                    self.debug_pending_total,
                    self.debug_pending_dig_total,
                    self.debug_pending_dig_visible,
                    self.debug_pending_stairs_total,
                    self.debug_pending_stairs_visible,
                    self.debug_pending_place_total,
                    stairs_y_label,
                },
            );
            if (self.debug_stairs_nearest_y) |stairs_y| {
                std.debug.print("({d})\n", .{stairs_y});
            } else {
                std.debug.print("\n", .{});
            }
        } else {
            std.debug.print(
                "worker({d}) state={s} note={s} pos=({d},{d},{d}) y={d} task=none pending=total:{d} dig:{d}/{d} stairs:{d}/{d} place:{d} stairs_y={s}",
                .{
                    self.id,
                    state_label,
                    debugNoteLabel(self.debug_note),
                    xi,
                    yi,
                    zi,
                    self.debug_worker_y,
                    self.debug_pending_total,
                    self.debug_pending_dig_total,
                    self.debug_pending_dig_visible,
                    self.debug_pending_stairs_total,
                    self.debug_pending_stairs_visible,
                    self.debug_pending_place_total,
                    stairs_y_label,
                },
            );
            if (self.debug_stairs_nearest_y) |stairs_y| {
                std.debug.print("({d})\n", .{stairs_y});
            } else {
                std.debug.print("\n", .{});
            }
        }
    }

    fn findPathToStairs(
        self: *Worker,
        world: anytype,
        start: BlockCoord,
        target: BlockCoord,
        pf: *Pathfinder,
    ) ?[]BlockCoord {
        _ = self;
        var candidates: [27]BlockCoord = undefined;
        var candidate_dists: [27]u32 = undefined;
        var count: usize = 0;

        const base_x: i32 = @intCast(target.x);
        const base_y: i32 = @intCast(target.y);
        const base_z: i32 = @intCast(target.z);

        var dy: i32 = 0;
        while (dy <= 2) : (dy += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                var dz: i32 = -1;
                while (dz <= 1) : (dz += 1) {
                    const x = base_x + dx;
                    const y = base_y + dy;
                    const z = base_z + dz;
                    if (!Pathfinder.isWalkable(world, x, y, z)) continue;

                    candidates[count] = .{
                        .x = @intCast(x),
                        .y = @intCast(y),
                        .z = @intCast(z),
                    };

                    const dxs: i32 = x - @as(i32, @intCast(start.x));
                    const dys: i32 = y - @as(i32, @intCast(start.y));
                    const dzs: i32 = z - @as(i32, @intCast(start.z));
                    candidate_dists[count] = @intCast(dxs * dxs + dys * dys + dzs * dzs);
                    count += 1;
                }
            }
        }

        while (count > 0) {
            var best_idx: usize = 0;
            var best_dist: u32 = candidate_dists[0];
            var i: usize = 1;
            while (i < count) : (i += 1) {
                if (candidate_dists[i] < best_dist) {
                    best_dist = candidate_dists[i];
                    best_idx = i;
                }
            }

            const goal = candidates[best_idx];
            if (pf.findPath(world, start, goal)) |path| {
                return path;
            }

            count -= 1;
            candidates[best_idx] = candidates[count];
            candidate_dists[best_idx] = candidate_dists[count];
        }

        return null;
    }

    fn updateWander(self: *Worker, dt: f32, world: anytype, pf: *Pathfinder) void {
        if (self.wander_wait > 0) {
            self.wander_wait -= dt;
            return;
        }

        const start = self.getBlockCoord();
        const WorldT = @TypeOf(world.*);
        const max_x: i32 = @as(i32, WorldT.worldSizeBlocksX());
        const max_y: i32 = @as(i32, WorldT.worldSizeBlocksY());
        const max_z: i32 = @as(i32, WorldT.worldSizeBlocksZ());

        const base_x: i32 = @intCast(start.x);
        const base_y: i32 = @intCast(start.y);
        const base_z: i32 = @intCast(start.z);

        var attempt: usize = 0;
        while (attempt < 8) : (attempt += 1) {
            const dist: i32 = self.rng.random().intRangeAtMost(i32, 1, 10);
            const dx: i32 = self.rng.random().intRangeAtMost(i32, -dist, dist);
            const dz: i32 = self.rng.random().intRangeAtMost(i32, -dist, dist);
            if (dx == 0 and dz == 0) continue;

            const x = base_x + dx;
            const y = base_y;
            const z = base_z + dz;
            if (x < 0 or z < 0 or x >= max_x or z >= max_z) continue;
            if (y < 0 or y >= max_y) continue;
            if (!Pathfinder.isWalkable(world, x, y, z)) continue;

            const goal = BlockCoord{
                .x = @intCast(x),
                .y = @intCast(y),
                .z = @intCast(z),
            };

            if (pf.findPath(world, start, goal)) |found_path| {
                self.path = found_path;
                self.path_index = 0;
                if (found_path.len > 0) {
                    self.setTargetFromPath();
                    self.state = .moving;
                } else {
                    self.state = .idle;
                    self.wander_wait = self.randomRangeF32(WANDER_WAIT_MIN, WANDER_WAIT_MAX);
                }
                return;
            }
        }

        self.wander_wait = self.randomRangeF32(WANDER_WAIT_MIN, WANDER_WAIT_MAX);
    }

    fn randomRangeF32(self: *Worker, min: f32, max: f32) f32 {
        return min + (max - min) * self.rng.random().float(f32);
    }

    fn updateDebugCounts(self: *Worker, task_queue: *TaskQueue) void {
        const worker_y: u16 = @intFromFloat(@floor(self.y));
        const below_y: u16 = worker_y -| 1;
        const below2_y: u16 = worker_y -| 2;
        const above_y: u16 = worker_y +| 1;

        var pending_total: u32 = 0;
        var pending_dig_total: u32 = 0;
        var pending_dig_visible: u32 = 0;
        var pending_stairs_total: u32 = 0;
        var pending_stairs_visible: u32 = 0;
        var pending_place_total: u32 = 0;
        var stairs_nearest_y: ?u16 = null;
        var stairs_nearest_dist_sq: f32 = std.math.floatMax(f32);

        for (task_queue.tasks.items) |task| {
            if (task.status != .pending) continue;
            pending_total += 1;
            switch (task.task_type) {
                .dig => {
                    pending_dig_total += 1;
                    pending_dig_visible += 1;
                },
                .stairs => {
                    pending_stairs_total += 1;
                    if (task.position.y == worker_y or task.position.y == below_y or task.position.y == below2_y or task.position.y == above_y) {
                        pending_stairs_visible += 1;
                    }
                    const dx = @as(f32, @floatFromInt(task.position.x)) - self.x;
                    const dy = @as(f32, @floatFromInt(task.position.y)) - self.y;
                    const dz = @as(f32, @floatFromInt(task.position.z)) - self.z;
                    const dist_sq = dx * dx + dy * dy + dz * dz;
                    if (dist_sq < stairs_nearest_dist_sq) {
                        stairs_nearest_dist_sq = dist_sq;
                        stairs_nearest_y = task.position.y;
                    }
                },
                .place => {
                    pending_place_total += 1;
                },
            }
        }

        self.debug_pending_total = pending_total;
        self.debug_pending_dig_total = pending_dig_total;
        self.debug_pending_dig_visible = pending_dig_visible;
        self.debug_pending_stairs_total = pending_stairs_total;
        self.debug_pending_stairs_visible = pending_stairs_visible;
        self.debug_pending_place_total = pending_place_total;
        self.debug_worker_y = worker_y;
        self.debug_stairs_nearest_y = stairs_nearest_y;
    }
};

pub const WorkerManager = struct {
    workers: std.ArrayList(Worker),
    next_id: u32,
    allocator: std.mem.Allocator,
    pathfinder: Pathfinder,

    pub fn init(allocator: std.mem.Allocator) WorkerManager {
        return .{
            .workers = .{},
            .next_id = 1,
            .allocator = allocator,
            .pathfinder = Pathfinder.init(allocator),
        };
    }

    pub fn deinit(self: *WorkerManager) void {
        // Clean up worker paths
        for (self.workers.items) |*w| {
            w.deinit(&self.pathfinder);
        }
        self.workers.deinit(self.allocator);
    }

    /// Spawn a new worker at the given position
    pub fn spawnWorker(self: *WorkerManager, x: f32, y: f32, z: f32) !*Worker {
        const id = self.next_id;
        self.next_id += 1;

        try self.workers.append(self.allocator, Worker.init(id, x, y, z));
        return &self.workers.items[self.workers.items.len - 1];
    }

    /// Update all workers
    pub fn updateAll(self: *WorkerManager, dt: f32, world: anytype, task_queue: *TaskQueue) void {
        for (self.workers.items) |*w| {
            w.update(dt, world, task_queue, &self.pathfinder);
        }

        // Cleanup completed tasks periodically
        task_queue.cleanupCompleted();
    }

    /// Get worker count
    pub fn count(self: *const WorkerManager) usize {
        return self.workers.items.len;
    }

    /// Get worker by ID
    pub fn getWorker(self: *WorkerManager, id: u32) ?*Worker {
        for (self.workers.items) |*w| {
            if (w.id == id) {
                return w;
            }
        }
        return null;
    }
};
