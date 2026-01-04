const std = @import("std");
const Goblinoria = @import("Goblinoria");
const raylib = @import("raylib");
const debugMenu = @import("debugTools");

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

const WorldRect = struct {
    min_x: f32,
    max_x: f32,
    min_z: f32,
    max_z: f32,
};

fn worldRectFromScreenDrag(start: raylib.Vector2, end: raylib.Vector2, camera: raylib.Camera3D, plane_y: f32) ?WorldRect {
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

    while (!raylib.windowShouldClose()) {
        if (raylib.isKeyPressed(raylib.KeyboardKey.f2)) {
            debugMenu.toggle();
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
            world.clearPreviewSelection();
        }

        // Drag preview: filled rectangle on a fixed Y plane (tunnel)
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

                    world.clearPreviewSelection();
                    const rect_opt = worldRectFromScreenDrag(start, current, renderer.ortho_camera, plane_y);
                    if (rect_opt) |rect| {
                        const world_max_x: i32 = @as(i32, Goblinoria.World.worldSizeBlocksX());
                        const world_max_z: i32 = @as(i32, Goblinoria.World.worldSizeBlocksZ());

                        const x0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.min_x))), 0, world_max_x - 1);
                        const x1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.max_x))), 0, world_max_x - 1);
                        const z0: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.min_z))), 0, world_max_z - 1);
                        const z1: i32 = std.math.clamp(@as(i32, @intFromFloat(@floor(rect.max_z))), 0, world_max_z - 1);

                        const yi: i32 = @as(i32, plane_internal_y);
                        if (yi >= 0 and yi < @as(i32, Goblinoria.World.worldSizeBlocksY())) {
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
                    }
                }
            }
        }

        // Release: commit drag or do click select
        if (raylib.isMouseButtonReleased(raylib.MouseButton.left)) {
            const preview_count: usize = world.preview_blocks.count();
            if (is_dragging and preview_count != 0) {
                world.commitPreviewSelection();
            } else if (drag_start != null) {
                const mouse_pos = raylib.getMousePosition();
                const ray = raylib.getScreenToWorldRay(mouse_pos, renderer.ortho_camera);
                const hit = Goblinoria.raycastBlock(world, ray, 500.0);
                if (hit.hit) {
                    world.addToSelection(hit.x, hit.y, hit.z);
                }
            }

            world.clearPreviewSelection();
            drag_start = null;
            is_dragging = false;
            drag_plane_internal_y = null;
        }

        if (raylib.isKeyPressed(raylib.KeyboardKey.escape)) {
            world.clearSelection();
            world.clearPreviewSelection();
        }

        renderer.update(wheel_for_camera);

        raylib.beginDrawing();
        raylib.clearBackground(raylib.Color.black);

        const render_stats = renderer.render(world);
        drawTopRenderLevelHud(world);

        debugMenu.draw(
            10,
            10,
            render_stats.triangles_drawn,
            render_stats.visible_blocks_drawn,
            render_stats.solid_blocks_drawn,
            @intCast(Goblinoria.World.totalBlockSlots()),
            world.vertical_scroll,
            render_stats.chunks_drawn,
            render_stats.chunks_regenerated,
            render_stats.chunks_considered,
            render_stats.chunks_culled,
        );

        raylib.endDrawing();
    }
}
