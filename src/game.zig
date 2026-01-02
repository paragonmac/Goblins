const std = @import("std");
const Goblinoria = @import("Goblinoria");
const raylib = @import("raylib");
const debugMenu = @import("debugTools");

pub fn run() !void {
    const screenWidth: i32 = 800;
    const screenHeight: i32 = 600;
    const title: [:0]const u8 = "Goblinoria";

    raylib.initWindow(screenWidth, screenHeight, title);
    defer raylib.closeWindow();

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

        // Camera update
        renderer.update();

        raylib.beginDrawing();
        raylib.clearBackground(raylib.Color.black);

        // 3D rendering
        const tris_drawn = renderer.render(world);

        // 2D overlay (debug menu)
        debugMenu.draw(10, 10, tris_drawn);

        raylib.endDrawing();
    }
}
