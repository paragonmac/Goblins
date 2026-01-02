const std = @import("std");

pub const debugMenu = struct {
    var state: bool = true;
};
pub fn isOpen() bool {
    return debugMenu.state;
}

pub fn setOpen(is_open: bool) void {
    debugMenu.state = is_open;
}

pub fn open() void {
    debugMenu.state = true;
}

pub fn close() void {
    debugMenu.state = false;
}

pub fn toggle() void {
    debugMenu.state = !debugMenu.state;
}

fn getGPUInfo() struct { vendor: [:0]const u8, renderer: [:0]const u8 } {
    // GPU info is printed to console at startup
    // In the future, we can use rlgl functions to get this
    return .{
        .vendor = "GPU: NVIDIA GeForce RTX 5070 Ti",
        .renderer = "(See console for full info)",
    };
}

/// Draw the debug menu with stats
pub fn draw(x: i32, y: i32, tris_drawn: i32) void {
    if (!debugMenu.state) return;

    const rl = @import("raylib");

    const padding: i32 = 10;
    const font_size: i32 = 20;
    const line_height: i32 = font_size + 4;

    // Get stats from raylib
    const fps = rl.getFPS();
    const frame_time = rl.getFrameTime();

    // Format strings - using stack buffers
    var fps_buf: [64]u8 = undefined;
    var ft_buf: [64]u8 = undefined;
    var tris_buf: [64]u8 = undefined;

    const fps_str = std.fmt.bufPrintZ(&fps_buf, "FPS: {d}", .{fps}) catch "FPS: Error";
    const ft_str = std.fmt.bufPrintZ(&ft_buf, "Frame Time: {d:.2}ms", .{frame_time * 1000.0}) catch "Frame Time: Error";
    const tris_str = std.fmt.bufPrintZ(&tris_buf, "Triangles: {d}", .{tris_drawn}) catch "Triangles: Error";

    const gpu_info = getGPUInfo();

    const line1 = "==== Debug Menu ====";
    const line2 = fps_str;
    const line3 = ft_str;
    const line4 = tris_str;
    const line5 = gpu_info.vendor;
    const line6 = gpu_info.renderer;
    const line7 = "====================";
    const line8 = "[F2] Toggle menu";

    // Measure text widths
    const w1: i32 = rl.measureText(line1, font_size);
    const w2: i32 = rl.measureText(line2, font_size);
    const w3: i32 = rl.measureText(line3, font_size);
    const w4: i32 = rl.measureText(line4, font_size);
    const w5: i32 = rl.measureText(line5, font_size);
    const w6: i32 = rl.measureText(line6, font_size);
    const w7: i32 = rl.measureText(line7, font_size);
    const w8: i32 = rl.measureText(line8, font_size);

    var max_w: i32 = w1;
    if (w2 > max_w) max_w = w2;
    if (w3 > max_w) max_w = w3;
    if (w4 > max_w) max_w = w4;
    if (w5 > max_w) max_w = w5;
    if (w6 > max_w) max_w = w6;
    if (w7 > max_w) max_w = w7;
    if (w8 > max_w) max_w = w8;

    const box_w: i32 = max_w + padding * 2;
    const box_h: i32 = (line_height * 8) + padding * 2;

    // Draw background and border
    rl.drawRectangle(x, y, box_w, box_h, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 180 });
    rl.drawRectangleLines(x, y, box_w, box_h, rl.Color.ray_white);

    // Draw text lines
    var current_y = y + padding;
    rl.drawText(line1, x + padding, current_y, font_size, rl.Color.ray_white);
    current_y += line_height;
    rl.drawText(line2, x + padding, current_y, font_size, rl.Color.lime);
    current_y += line_height;
    rl.drawText(line3, x + padding, current_y, font_size, rl.Color.lime);
    current_y += line_height;
    rl.drawText(line4, x + padding, current_y, font_size, rl.Color.lime);
    current_y += line_height;
    rl.drawText(line5, x + padding, current_y, font_size, rl.Color.yellow);
    current_y += line_height;
    rl.drawText(line6, x + padding, current_y, font_size, rl.Color.yellow);
    current_y += line_height;
    rl.drawText(line7, x + padding, current_y, font_size, rl.Color.ray_white);
    current_y += line_height;
    rl.drawText(line8, x + padding, current_y, font_size, rl.Color.gray);
}
