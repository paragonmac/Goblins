const std = @import("std");
const Goblinoria = @import("Goblinoria");
const raylib = @import("raylib");

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
        raylib.beginDrawing();
        raylib.clearBackground(raylib.Color.black);
        renderer.render(world);
        raylib.endDrawing();
    }
}
