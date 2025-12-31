
const std = @import("std");
const Goblinoria = @import("Goblinoria");
const raylib = @import("raylib");

pub fn main() !void {
    const screenWidth: i32 = 800;
    const screenHeight: i32 = 600;
    const title: [:0]const u8 = "Goblinoria";

    raylib.initWindow(screenWidth, screenHeight, title);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const world = try Goblinoria.World.init(allocator);
    defer world.deinit(allocator);
    defer raylib.closeWindow();



    while (!raylib.windowShouldClose()) {
        raylib.beginDrawing();
        raylib.clearBackground(raylib.Color.black);

        raylib.drawText("Welcome to Goblinoria!", 190, 200, 20, raylib.Color.light_gray);

        raylib.endDrawing();
    }
}
