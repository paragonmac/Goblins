const std = @import("std");
const Goblinoria = @import("Goblinoria");
const raylib = @import("raylib");
const debugMenu = @import("debugTools");

fn drawTopRenderLevelHud(world: *const Goblinoria.World) void {
    const padding: i32 = 10;
    const font_size: i32 = 20;

    var buf: [96]u8 = undefined;
    const level_str = std.fmt.bufPrintZ(
        &buf,
        "Top Render Level: {d}",
        .{world.topRenderLevel()},
    ) catch "Top Render Level: ?";

    // Background for readability
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

    raylib.setTargetFPS(144); // Cap at 144 FPS (or 60 for VSync with most monitors)

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
    const slice_repeat_rate: f32 = 0.05; // seconds per step after delay

    while (!raylib.windowShouldClose()) {
        // Input handling
        if (raylib.isKeyPressed(raylib.KeyboardKey.f2)) {
            debugMenu.toggle();
        }

        const dt: f32 = raylib.getFrameTime();
        const shift_down = raylib.isKeyDown(raylib.KeyboardKey.left_shift) or raylib.isKeyDown(raylib.KeyboardKey.right_shift);

        // Read mouse wheel once per frame. If Shift is held, use it for slice control
        // and do not zoom the camera.
        const wheel: f32 = raylib.getMouseWheelMove();
        var wheel_for_camera: f32 = wheel;
        if (shift_down and wheel != 0.0) {
            const dir: i32 = if (wheel > 0.0) 1 else -1;
            const fast_step: i32 = 10;
            world.adjustTopRenderLevel(dir * fast_step);
            wheel_for_camera = 0.0;
        }

        // Adjust top render cutoff (slice) with [ and ]
        // - tap: single step
        // - hold: repeats after a short delay
        // - hold Shift: 10x steps
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

        // Camera update
        renderer.update(wheel_for_camera);

        raylib.beginDrawing();
        raylib.clearBackground(raylib.Color.black);

        // 3D rendering
        const render_stats = renderer.render(world);

        // Always-on HUD
        drawTopRenderLevelHud(world);

        // 2D overlay (debug menu)
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
