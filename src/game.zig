const std = @import("std");
const Goblinoria = @import("Goblinoria");
const raylib = @import("raylib");
const debugMenu = @import("debugTools");
const PlayerMode = Goblinoria.PlayerMode;
const STAIR_BLOCK_ID = Goblinoria.STAIR_BLOCK_ID;

fn intersectRayYPlane(ray: raylib.Ray, plane_y: f32) ?raylib.Vector3 {
    const denom = ray.direction.y;
    if (@abs(denom) < 0.000001) return null;
    const t = (plane_y - ray.position.y) / denom;
    if (t < 0.0) return null;
    return .{
        .x = ray.position.x + ray.direction.x * t,
        .y = plane_y,
        .z = ray.position.z + ray.direction.z * t,
    };
}

const WorldRectXZ = struct {
    min_x: f32,
    max_x: f32,
    min_z: f32,
    max_z: f32,
};

fn worldRectFromScreenDrag(start: raylib.Vector2, end: raylib.Vector2, camera: raylib.Camera3D, plane_y: f32) ?WorldRectXZ {
    const r0 = raylib.getScreenToWorldRay(start, camera);
    const r1 = raylib.getScreenToWorldRay(end, camera);

    const a = intersectRayYPlane(r0, plane_y) orelse return null;
    const b = intersectRayYPlane(r1, plane_y) orelse return null;

    return .{
        .min_x = @min(a.x, b.x),
        .max_x = @max(a.x, b.x),
        .min_z = @min(a.z, b.z),
        .max_z = @max(a.z, b.z),
    };
}

fn drawWorldSelectionRect(camera: raylib.Camera3D, start: raylib.Vector2, end: raylib.Vector2, plane_y: f32) void {
    const rect = worldRectFromScreenDrag(start, end, camera, plane_y) orelse return;

    // Slight lift to reduce z-fighting against the top faces.
    const y = plane_y + 0.01;
    const p1 = raylib.Vector3{ .x = rect.min_x, .y = y, .z = rect.min_z };
    const p2 = raylib.Vector3{ .x = rect.max_x, .y = y, .z = rect.min_z };
    const p3 = raylib.Vector3{ .x = rect.max_x, .y = y, .z = rect.max_z };
    const p4 = raylib.Vector3{ .x = rect.min_x, .y = y, .z = rect.max_z };

    const fill = raylib.Color{ .r = 0, .g = 255, .b = 0, .a = 30 };
    const border = raylib.Color{ .r = 0, .g = 255, .b = 0, .a = 220 };
    raylib.drawTriangle3D(p1, p2, p3, fill);
    raylib.drawTriangle3D(p1, p3, p4, fill);
    raylib.drawLine3D(p1, p2, border);
    raylib.drawLine3D(p2, p3, border);
    raylib.drawLine3D(p3, p4, border);
    raylib.drawLine3D(p4, p1, border);
}

fn drawGreenBlocksInWorldRect(world: *Goblinoria.World, rect: WorldRectXZ, plane_internal_y: i16) void {
    const world_max_x: i32 = @as(i32, Goblinoria.World.worldSizeBlocksX());
    const world_max_y: i32 = @as(i32, Goblinoria.World.worldSizeBlocksY());
    const world_max_z: i32 = @as(i32, Goblinoria.World.worldSizeBlocksZ());

    const yi: i32 = @as(i32, plane_internal_y);
    if (yi < 0 or yi >= world_max_y) return;

    // Blocks are centered at integer coords (block N spans N-0.5 to N+0.5).
    // Shift by +0.5 before flooring to get the correct block index.
    const x0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.min_x + 0.5))), 0, world_max_x - 1);
    const x1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.max_x + 0.5))), 0, world_max_x - 1);
    const z0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.min_z + 0.5))), 0, world_max_z - 1);
    const z1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.max_z + 0.5))), 0, world_max_z - 1);

    const scroll_y: f32 = @floatFromInt(world.vertical_scroll);
    const fill = raylib.Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
    const wire = raylib.Color{ .r = 0, .g = 255, .b = 0, .a = 255 };

    var x: i32 = @min(x0, x1);
    while (x <= @max(x0, x1)) : (x += 1) {
        var z: i32 = @min(z0, z1);
        while (z <= @max(z0, z1)) : (z += 1) {
            if (world.isBlockSolid(@intCast(x), @intCast(yi), @intCast(z))) {
                // Mesh convention: block center is at integer coord.
                const pos = raylib.Vector3{
                    .x = @as(f32, @floatFromInt(x)),
                    .y = @as(f32, @floatFromInt(yi)) + scroll_y,
                    .z = @as(f32, @floatFromInt(z)),
                };
                raylib.drawCube(pos, 1.0, 1.0, 1.0, fill);
                raylib.drawCubeWires(pos, 1.02, 1.02, 1.02, wire);
            }
        }
    }
}

fn addSelectionInWorldRect(world: *Goblinoria.World, rect: WorldRectXZ, plane_internal_y: i16) bool {
    const world_max_x: i32 = @as(i32, Goblinoria.World.worldSizeBlocksX());
    const world_max_y: i32 = @as(i32, Goblinoria.World.worldSizeBlocksY());
    const world_max_z: i32 = @as(i32, Goblinoria.World.worldSizeBlocksZ());

    const yi: i32 = @as(i32, plane_internal_y);
    if (yi < 0 or yi >= world_max_y) return false;

    // Blocks are centered at integer coords (block N spans N-0.5 to N+0.5).
    // Shift by +0.5 before flooring to get the correct block index.
    const x0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.min_x + 0.5))), 0, world_max_x - 1);
    const x1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.max_x + 0.5))), 0, world_max_x - 1);
    const z0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.min_z + 0.5))), 0, world_max_z - 1);
    const z1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.max_z + 0.5))), 0, world_max_z - 1);

    var any: bool = false;
    var x: i32 = @min(x0, x1);
    while (x <= @max(x0, x1)) : (x += 1) {
        var z: i32 = @min(z0, z1);
        while (z <= @max(z0, z1)) : (z += 1) {
            if (world.isBlockSolid(@intCast(x), @intCast(yi), @intCast(z))) {
                any = true;
                world.addToSelection(@intCast(x), @intCast(yi), @intCast(z));
            }
        }
    }
    return any;
}

fn drawTopRenderLevelHud(world: *const Goblinoria.World) void {
    const padding: i32 = 10;
    const font_size: i32 = 20;

    var buf: [96]u8 = undefined;
    const level_str = std.fmt.bufPrintZ(
        &buf,
        "Top Render Level: {d}",
        .{world.topRenderLevel()},
    ) catch "Top Render Level: ?";

    const w = raylib.measureText(level_str, font_size);
    const h = font_size + 8;

    const screen_w: i32 = raylib.getScreenWidth();
    const screen_h: i32 = raylib.getScreenHeight();
    const box_w: i32 = w + 12;
    const box_h: i32 = h;

    const x = @max(0, screen_w - box_w - padding);
    const y = @max(0, screen_h - box_h - padding);

    raylib.drawRectangle(x, y, box_w, box_h, raylib.Color{ .r = 0, .g = 0, .b = 0, .a = 180 });
    raylib.drawRectangleLines(x, y, box_w, box_h, raylib.Color.ray_white);
    raylib.drawText(level_str, x + 6, y + 4, font_size, raylib.Color.ray_white);
}

fn drawModeHud(world: *const Goblinoria.World) void {
    const padding: i32 = 10;
    const font_size: i32 = 20;

    // Mode display
    const mode_name = world.player_mode.displayName();
    const mode_hint = world.player_mode.keyHint();

    var buf: [64]u8 = undefined;
    const mode_str = std.fmt.bufPrintZ(&buf, "Mode: {s} {s}", .{ mode_name, mode_hint }) catch "Mode: ?";

    const w = raylib.measureText(mode_str, font_size);
    const box_w: i32 = w + 12;
    const box_h: i32 = font_size + 8;

    // Bottom-left corner
    const x = padding;
    const y = raylib.getScreenHeight() - box_h - padding;

    // Color based on mode
    const mode_color: raylib.Color = switch (world.player_mode) {
        .information => raylib.Color{ .r = 100, .g = 100, .b = 255, .a = 200 }, // Blue
        .dig => raylib.Color{ .r = 255, .g = 100, .b = 100, .a = 200 }, // Red
        .place => raylib.Color{ .r = 100, .g = 255, .b = 100, .a = 200 }, // Green
        .stairs => raylib.Color{ .r = 160, .g = 120, .b = 60, .a = 200 }, // Brown
    };

    raylib.drawRectangle(x, y, box_w, box_h, mode_color);
    raylib.drawRectangleLines(x, y, box_w, box_h, raylib.Color.ray_white);
    raylib.drawText(mode_str, x + 6, y + 4, font_size, raylib.Color.ray_white);

    // Task count display (if there are tasks)
    const task_count = world.task_queue.activeCount();
    if (task_count > 0) {
        var task_buf: [64]u8 = undefined;
        const task_str = std.fmt.bufPrintZ(&task_buf, "Tasks: {d}", .{task_count}) catch "Tasks: ?";
        const task_w = raylib.measureText(task_str, font_size);
        const task_box_w: i32 = task_w + 12;
        const task_x = padding;
        const task_y = y - box_h - 5;

        raylib.drawRectangle(task_x, task_y, task_box_w, box_h, raylib.Color{ .r = 0, .g = 0, .b = 0, .a = 180 });
        raylib.drawRectangleLines(task_x, task_y, task_box_w, box_h, raylib.Color.ray_white);
        raylib.drawText(task_str, task_x + 6, task_y + 4, font_size, raylib.Color.yellow);
    }
}

fn drawModeHelp() void {
    const font_size: i32 = 16;
    const padding: i32 = 10;
    const line_height: i32 = 20;

    const help_lines = [_][:0]const u8{
        "[1] Info mode - inspect blocks",
        "[2] Dig mode - select blocks to dig",
        "[3] Place mode - select where to build",
        "[4] Stairs mode - convert blocks to stairs",
    };

    const max_w = blk: {
        var max: i32 = 0;
        for (help_lines) |line| {
            const w = raylib.measureText(line, font_size);
            if (w > max) max = w;
        }
        break :blk max;
    };

    const box_w: i32 = max_w + 12;
    const box_h: i32 = @intCast(help_lines.len * line_height + 8);

    // Top-left corner, below debug menu area
    const x = padding;
    const y = padding;

    raylib.drawRectangle(x, y, box_w, box_h, raylib.Color{ .r = 0, .g = 0, .b = 0, .a = 120 });

    for (help_lines, 0..) |line, i| {
        const line_y = y + 4 + @as(i32, @intCast(i)) * line_height;
        raylib.drawText(line, x + 6, line_y, font_size, raylib.Color{ .r = 200, .g = 200, .b = 200, .a = 255 });
    }
}

pub fn run() !void {
    const screenWidth: i32 = 800;
    const screenHeight: i32 = 600;
    const title: [:0]const u8 = "Goblinoria";

    raylib.setConfigFlags(raylib.ConfigFlags{ .window_resizable = true, .msaa_4x_hint = true });
    raylib.initWindow(screenWidth, screenHeight, title);
    defer raylib.closeWindow();

    raylib.setTargetFPS(144);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var world = try Goblinoria.World.init(allocator);
    defer world.deinit(allocator);
    world.seedDebug();
    world.spawnInitialWorkers();

    var renderer = Goblinoria.Renderer.init();

    // Slice controls
    var slice_hold_time: f32 = 0.0;
    var slice_repeat_accum: f32 = 0.0;
    const slice_repeat_delay: f32 = 0.25;
    const slice_repeat_rate: f32 = 0.05;

    // Drag-select state
    var drag_start: ?raylib.Vector2 = null;
    var is_dragging: bool = false;
    var drag_plane_internal_y: ?i16 = null;
    var drag_rect: ?WorldRectXZ = null;

    while (!raylib.windowShouldClose()) {
        if (raylib.isKeyPressed(raylib.KeyboardKey.f2)) {
            debugMenu.toggle();
        }

        // Mode switching: 1=Info, 2=Dig, 3=Place
        if (raylib.isKeyPressed(raylib.KeyboardKey.one)) {
            world.player_mode = .information;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.two)) {
            world.player_mode = .dig;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.three)) {
            world.player_mode = .place;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.four)) {
            world.player_mode = .stairs;
        }

        const dt: f32 = raylib.getFrameTime();
        const shift_down = raylib.isKeyDown(raylib.KeyboardKey.left_shift) or raylib.isKeyDown(raylib.KeyboardKey.right_shift);

        // Mouse wheel: Shift+wheel = slice, wheel = zoom
        const wheel: f32 = raylib.getMouseWheelMove();
        var wheel_for_camera: f32 = wheel;
        if (shift_down and wheel != 0.0) {
            const dir: i32 = if (wheel > 0.0) 1 else -1;
            const fast_step: i32 = 10;
            world.adjustTopRenderLevel(dir * fast_step);
            wheel_for_camera = 0.0;
        }

        // Slice keys [ and ]
        const step: i32 = if (shift_down) 10 else 1;
        const left_pressed = raylib.isKeyPressed(raylib.KeyboardKey.left_bracket);
        const right_pressed = raylib.isKeyPressed(raylib.KeyboardKey.right_bracket);
        const left_down = raylib.isKeyDown(raylib.KeyboardKey.left_bracket);
        const right_down = raylib.isKeyDown(raylib.KeyboardKey.right_bracket);

        var delta_level: i32 = 0;
        if (left_pressed) delta_level -= step;
        if (right_pressed) delta_level += step;

        if ((left_down or right_down) and !(left_down and right_down)) {
            slice_hold_time += dt;
            if (slice_hold_time >= slice_repeat_delay) {
                slice_repeat_accum += dt;
                while (slice_repeat_accum >= slice_repeat_rate) {
                    slice_repeat_accum -= slice_repeat_rate;
                    if (left_down) delta_level -= step;
                    if (right_down) delta_level += step;
                }
            }
        } else {
            slice_hold_time = 0.0;
            slice_repeat_accum = 0.0;
        }

        if (delta_level != 0) {
            world.adjustTopRenderLevel(delta_level);
        }

        // Start drag
        if (raylib.isMouseButtonPressed(raylib.MouseButton.left)) {
            drag_start = raylib.getMousePosition();
            is_dragging = false;
            drag_plane_internal_y = null;
            drag_rect = null;
        }

        // Drag preview: world-aligned rectangle on a fixed Y plane.
        if (raylib.isMouseButtonDown(raylib.MouseButton.left)) {
            if (drag_start) |start| {
                const current = raylib.getMousePosition();
                const dx = @abs(current.x - start.x);
                const dy = @abs(current.y - start.y);
                if (dx > 5 or dy > 5) {
                    is_dragging = true;
                }

                if (is_dragging) {
                    if (drag_plane_internal_y == null) {
                        const ray0 = raylib.getScreenToWorldRay(start, renderer.ortho_camera);
                        const hit0 = Goblinoria.raycastBlock(world, ray0, 500.0);
                        drag_plane_internal_y = if (hit0.hit) @intCast(hit0.y) else world.top_render_y_index;
                    }

                    const plane_internal_y: i16 = drag_plane_internal_y.?;
                    const scroll_y: f32 = @floatFromInt(world.vertical_scroll);
                    const plane_y: f32 = @as(f32, @floatFromInt(plane_internal_y)) + 0.5 + scroll_y;

                    const rect_opt = worldRectFromScreenDrag(start, current, renderer.ortho_camera, plane_y);
                    if (rect_opt) |rect| {
                        drag_rect = rect;
                    } else {
                        drag_rect = null;
                    }
                }
            }
        }

        // Release: commit drag or do click select based on mode
        if (raylib.isMouseButtonReleased(raylib.MouseButton.left)) {
            var did_drag_select: bool = false;

            switch (world.player_mode) {
                .information => {
                    // Single click to inspect - don't do drag selection
                    if (drag_start != null and !is_dragging) {
                        const mouse_pos = raylib.getMousePosition();
                        const ray = raylib.getScreenToWorldRay(mouse_pos, renderer.ortho_camera);
                        const hit = Goblinoria.raycastBlock(world, ray, 500.0);
                        if (hit.hit) {
                            // TODO: Show info popup for block at hit.x, hit.y, hit.z
                            // For now, just toggle selection to show we detected it
                            world.toggleBlockSelection(hit.x, hit.y, hit.z);
                        }
                    }
                },
                .dig => {
                    // Drag to select, then create dig tasks
                    if (is_dragging and drag_rect != null and drag_plane_internal_y != null) {
                        did_drag_select = addSelectionInWorldRect(world, drag_rect.?, drag_plane_internal_y.?);
                    }

                    if (!did_drag_select and drag_start != null) {
                        const mouse_pos = raylib.getMousePosition();
                        const ray = raylib.getScreenToWorldRay(mouse_pos, renderer.ortho_camera);
                        const hit = Goblinoria.raycastBlock(world, ray, 500.0);
                        if (hit.hit) {
                            world.addToSelection(hit.x, hit.y, hit.z);
                        }
                    }

                    // Convert selection to dig tasks
                    var it = world.selected_blocks.keyIterator();
                    while (it.next()) |coord| {
                        if (world.isBlockSolid(@intCast(coord.x), @intCast(coord.y), @intCast(coord.z))) {
                            _ = world.task_queue.addTask(coord.*, .dig) catch {};
                        }
                    }
                    // Clear selection after creating tasks
                    world.clearSelection();
                },
                .place => {
                    // Drag to select empty spaces, then create place tasks
                    if (is_dragging and drag_rect != null and drag_plane_internal_y != null) {
                        did_drag_select = addSelectionInWorldRect(world, drag_rect.?, drag_plane_internal_y.?);
                    }

                    if (!did_drag_select and drag_start != null) {
                        const mouse_pos = raylib.getMousePosition();
                        const ray = raylib.getScreenToWorldRay(mouse_pos, renderer.ortho_camera);
                        const hit = Goblinoria.raycastBlock(world, ray, 500.0);
                        if (hit.hit) {
                            // For place mode, select the block above the hit
                            if (hit.y < Goblinoria.World.worldSizeBlocksY() - 1) {
                                world.addToSelection(hit.x, hit.y + 1, hit.z);
                            }
                        }
                    }

                    // Convert selection to place tasks (for empty blocks)
                    var it = world.selected_blocks.keyIterator();
                    while (it.next()) |coord| {
                        if (!world.isBlockSolid(@intCast(coord.x), @intCast(coord.y), @intCast(coord.z))) {
                            _ = world.task_queue.addPlaceTask(coord.*, 8) catch {}; // Material 8 = stone
                        }
                    }
                    world.clearSelection();
                },
                .stairs => {
                    // Drag to select solid blocks, then convert to stairs
                    if (is_dragging and drag_rect != null and drag_plane_internal_y != null) {
                        did_drag_select = addSelectionInWorldRect(world, drag_rect.?, drag_plane_internal_y.?);
                    }

                    if (!did_drag_select and drag_start != null) {
                        const mouse_pos = raylib.getMousePosition();
                        const ray = raylib.getScreenToWorldRay(mouse_pos, renderer.ortho_camera);
                        const hit = Goblinoria.raycastBlock(world, ray, 500.0);
                        if (hit.hit) {
                            world.addToSelection(hit.x, hit.y, hit.z);
                        }
                    }

                    // Convert selection to stairs tasks (for solid blocks)
                    var it = world.selected_blocks.keyIterator();
                    while (it.next()) |coord| {
                        const block = world.getBlock(@intCast(coord.x), @intCast(coord.y), @intCast(coord.z));
                        if (block != 0 and block != STAIR_BLOCK_ID) {
                            _ = world.task_queue.addStairsTask(coord.*) catch {};
                        }
                    }
                    world.clearSelection();
                },
            }

            drag_start = null;
            is_dragging = false;
            drag_plane_internal_y = null;
            drag_rect = null;
        }

        if (raylib.isKeyPressed(raylib.KeyboardKey.escape)) {
            world.clearSelection();
        }

        renderer.update(wheel_for_camera);

        // Update workers
        world.worker_manager.updateAll(dt, world, &world.task_queue);

        raylib.beginDrawing();
        raylib.clearBackground(raylib.Color.black);

        const render_stats = renderer.render(world);
        drawTopRenderLevelHud(world);
        drawModeHud(world);
        if (!debugMenu.isOpen()) {
            drawModeHelp();
        }

        if (is_dragging) {
            if (drag_start) |start| {
                const current = raylib.getMousePosition();
                if (drag_plane_internal_y) |plane_internal_y| {
                    const scroll_y: f32 = @floatFromInt(world.vertical_scroll);
                    const plane_y: f32 = @as(f32, @floatFromInt(plane_internal_y)) + 0.5 + scroll_y;
                    raylib.beginMode3D(renderer.ortho_camera);
                    drawWorldSelectionRect(renderer.ortho_camera, start, current, plane_y);
                    if (drag_rect) |rect| {
                        drawGreenBlocksInWorldRect(world, rect, plane_internal_y);
                    }
                    raylib.endMode3D();
                }
            }
        }

        debugMenu.draw(
            10,
            10,
            render_stats.cpu_render_ms,
            render_stats.cpu_mesh_regen_ms,
            render_stats.cpu_frustum_ms,
            render_stats.cpu_chunk_loop_ms,
            render_stats.cpu_grid_ms,
            render_stats.cpu_overlays_ms,
            render_stats.triangles_drawn,
            render_stats.triangles_facing_camera,
            render_stats.visible_blocks_drawn,
            render_stats.solid_blocks_drawn,
            @intCast(Goblinoria.World.totalBlockSlots()),
            world.vertical_scroll,
            render_stats.chunks_drawn,
            render_stats.chunks_in_frustum,
            render_stats.chunks_regenerated,
            render_stats.chunks_regen_deferred,
            render_stats.chunk_regen_budget,
            render_stats.chunks_considered,
            render_stats.chunks_culled,
            render_stats.chunks_frustum_culled,
            render_stats.chunks_empty,
        );

        raylib.endDrawing();
    }
}
