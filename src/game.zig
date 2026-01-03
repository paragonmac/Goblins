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

    while (!raylib.windowShouldClose()) {
        // Input handling
        if (raylib.isKeyPressed(raylib.KeyboardKey.f2)) {
            debugMenu.toggle();
        }

        // Adjust top render cutoff (slice) with [ and ]
        if (raylib.isKeyPressed(raylib.KeyboardKey.left_bracket)) {
            world.setTopRenderYIndex(world.top_render_y_index - 1);
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.right_bracket)) {
            world.setTopRenderYIndex(world.top_render_y_index + 1);
        }

        // Camera update
        renderer.update();

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
            render_stats.chunks_drawn,
            render_stats.chunks_regenerated,
        );

        raylib.endDrawing();
    }
}
