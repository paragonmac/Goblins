const std = @import("std");
const rl = @import("raylib");

var debug_font: ?rl.Font = null;
var debug_font_is_default: bool = true;

fn getDebugFont() rl.Font {
    if (debug_font) |f| return f;

    // Prefer a monospace font to make similar glyphs (C/G) easier to distinguish.
    // Try common Linux paths; fall back to raylib's default font if unavailable.
    const candidates = [_][:0]const u8{
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationMono-Regular.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
        "/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf",
    };

    for (candidates) |path| {
        const loaded = rl.loadFontEx(path, 18, null) catch continue;
        debug_font = loaded;
        debug_font_is_default = false;
        return loaded;
    }

    debug_font = rl.getFontDefault() catch unreachable;
    debug_font_is_default = true;
    return debug_font.?;
}

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
pub fn draw(
    x: i32,
    y: i32,
    cpu_render_ms: f32,
    cpu_mesh_regen_ms: f32,
    cpu_frustum_ms: f32,
    cpu_chunk_loop_ms: f32,
    cpu_grid_ms: f32,
    cpu_overlays_ms: f32,
    tris_drawn: i32,
    tris_facing_camera: i32,
    visible_blocks_drawn: i32,
    solid_blocks_drawn: i32,
    total_blocks_in_memory: i32,
    vertical_scroll: i32,
    chunks_drawn: i32,
    chunks_in_frustum: i32,
    chunks_regenerated: i32,
    chunks_regen_deferred: i32,
    chunk_regen_budget: i32,
    chunks_considered: i32,
    chunks_culled: i32,
    chunks_frustum_culled: i32,
    chunks_empty: i32,
) void {
    if (!debugMenu.state) return;

    const font = getDebugFont();
    const spacing: f32 = 1.0;

    const padding: i32 = 10;
    const font_size: i32 = 16;
    const line_height: i32 = font_size + 4;

    // Get stats from raylib
    const fps = rl.getFPS();
    const frame_time = rl.getFrameTime();

    // Format strings - using stack buffers
    var fps_buf: [64]u8 = undefined;
    var ft_buf: [64]u8 = undefined;
    var cpu_render_buf: [64]u8 = undefined;
    var cpu_regen_buf: [64]u8 = undefined;
    var cpu_frustum_buf: [64]u8 = undefined;
    var cpu_chunk_loop_buf: [64]u8 = undefined;
    var cpu_grid_buf: [64]u8 = undefined;
    var cpu_overlays_buf: [64]u8 = undefined;
    var tris_buf: [64]u8 = undefined;
    var tris_cam_buf: [64]u8 = undefined;
    var blocks_buf: [64]u8 = undefined;
    var solid_buf: [64]u8 = undefined;
    var mem_blocks_buf: [64]u8 = undefined;
    var scroll_buf: [64]u8 = undefined;
    var chunks_buf: [64]u8 = undefined;
    var chunks_in_frustum_buf: [64]u8 = undefined;
    var regen_buf: [64]u8 = undefined;
    var regen_def_buf: [64]u8 = undefined;
    var regen_budget_buf: [64]u8 = undefined;
    var considered_buf: [64]u8 = undefined;
    var culled_buf: [64]u8 = undefined;
    var frustum_culled_buf: [64]u8 = undefined;
    var empty_buf: [64]u8 = undefined;

    const fps_str = std.fmt.bufPrintZ(&fps_buf, "FPS: {d}", .{fps}) catch "FPS: Error";
    const ft_str = std.fmt.bufPrintZ(&ft_buf, "Frame Time: {d:.2}ms", .{frame_time * 1000.0}) catch "Frame Time: Error";
    const cpu_render_str = std.fmt.bufPrintZ(&cpu_render_buf, "CPU Render: {d:.2}ms", .{cpu_render_ms}) catch "CPU Render: Error";
    const cpu_regen_str = std.fmt.bufPrintZ(&cpu_regen_buf, "CPU Mesh Regen: {d:.2}ms", .{cpu_mesh_regen_ms}) catch "CPU Regen: Error";
    const cpu_frustum_str = std.fmt.bufPrintZ(&cpu_frustum_buf, "CPU Frustum: {d:.2}ms", .{cpu_frustum_ms}) catch "CPU Frustum: Error";
    const cpu_chunk_loop_str = std.fmt.bufPrintZ(&cpu_chunk_loop_buf, "CPU Chunks: {d:.2}ms", .{cpu_chunk_loop_ms}) catch "CPU Chunks: Error";
    const cpu_grid_str = std.fmt.bufPrintZ(&cpu_grid_buf, "CPU Grid: {d:.2}ms", .{cpu_grid_ms}) catch "CPU Grid: Error";
    const cpu_overlays_str = std.fmt.bufPrintZ(&cpu_overlays_buf, "CPU Overlays: {d:.2}ms", .{cpu_overlays_ms}) catch "CPU Overlays: Error";
    const tris_str = std.fmt.bufPrintZ(&tris_buf, "Triangles: {d}", .{tris_drawn}) catch "Triangles: Error";
    const tris_cam_str = std.fmt.bufPrintZ(&tris_cam_buf, "Triangles (to camera): {d}", .{tris_facing_camera}) catch "TriCam: Error";
    const blocks_str = std.fmt.bufPrintZ(&blocks_buf, "Blocks (visible): {d}", .{visible_blocks_drawn}) catch "Blocks: Error";
    const solid_str = std.fmt.bufPrintZ(&solid_buf, "Blocks (solid): {d}", .{solid_blocks_drawn}) catch "Solid: Error";
    const mem_blocks_str = std.fmt.bufPrintZ(&mem_blocks_buf, "Blocks (memory): {d}", .{total_blocks_in_memory}) catch "Memory: Error";
    const scroll_str = std.fmt.bufPrintZ(&scroll_buf, "Vertical scroll: {d}", .{vertical_scroll}) catch "Scroll: Error";
    const chunks_str = std.fmt.bufPrintZ(&chunks_buf, "Chunks rendered: {d}", .{chunks_drawn}) catch "Chunks: Error";
    const chunks_in_frustum_str = std.fmt.bufPrintZ(&chunks_in_frustum_buf, "Chunks in frustum: {d}", .{chunks_in_frustum}) catch "Frustum: Error";
    const regen_str = std.fmt.bufPrintZ(&regen_buf, "Chunks regen: {d}", .{chunks_regenerated}) catch "Regen: Error";
    const regen_def_str = std.fmt.bufPrintZ(&regen_def_buf, "Regen deferred: {d}", .{chunks_regen_deferred}) catch "Deferred: Error";
    const regen_budget_str = std.fmt.bufPrintZ(&regen_budget_buf, "Regen budget: {d}/frame", .{chunk_regen_budget}) catch "Budget: Error";
    const considered_str = std.fmt.bufPrintZ(&considered_buf, "Chunks considered: {d}", .{chunks_considered}) catch "Considered: Error";
    const culled_str = std.fmt.bufPrintZ(&culled_buf, "Chunks culled: {d}", .{chunks_culled}) catch "Culled: Error";
    const frustum_culled_str = std.fmt.bufPrintZ(&frustum_culled_buf, "Culled (frustum): {d}", .{chunks_frustum_culled}) catch "CulledF: Error";
    const empty_str = std.fmt.bufPrintZ(&empty_buf, "Culled (empty): {d}", .{chunks_empty}) catch "Empty: Error";

    const gpu_info = getGPUInfo();

    const line1 = "==== Debug Menu ====";
    const line2 = fps_str;
    const line3 = ft_str;
    const line4 = cpu_render_str;
    const line5 = cpu_regen_str;
    const line6 = cpu_frustum_str;
    const line7 = cpu_chunk_loop_str;
    const line8 = cpu_grid_str;
    const line9 = cpu_overlays_str;
    const line10 = tris_str;
    const line11 = tris_cam_str;
    const line12 = blocks_str;
    const line13 = solid_str;
    const line14 = mem_blocks_str;
    const line15 = scroll_str;
    const line16 = chunks_str;
    const line17 = chunks_in_frustum_str;
    const line18 = regen_str;
    const line19 = regen_def_str;
    const line20 = regen_budget_str;
    const line21 = considered_str;
    const line22 = culled_str;
    const line23 = frustum_culled_str;
    const line24 = empty_str;
    const line25 = gpu_info.vendor;
    const line26 = gpu_info.renderer;
    const line27 = "====================";
    const line28 = "[F2] Toggle menu";

    // Measure text widths (using the selected font)
    const font_size_f: f32 = @floatFromInt(font_size);
    const w1: i32 = @intFromFloat(rl.measureTextEx(font, line1, font_size_f, spacing).x);
    const w2: i32 = @intFromFloat(rl.measureTextEx(font, line2, font_size_f, spacing).x);
    const w3: i32 = @intFromFloat(rl.measureTextEx(font, line3, font_size_f, spacing).x);
    const w4: i32 = @intFromFloat(rl.measureTextEx(font, line4, font_size_f, spacing).x);
    const w5: i32 = @intFromFloat(rl.measureTextEx(font, line5, font_size_f, spacing).x);
    const w6: i32 = @intFromFloat(rl.measureTextEx(font, line6, font_size_f, spacing).x);
    const w7: i32 = @intFromFloat(rl.measureTextEx(font, line7, font_size_f, spacing).x);
    const w8: i32 = @intFromFloat(rl.measureTextEx(font, line8, font_size_f, spacing).x);
    const w9: i32 = @intFromFloat(rl.measureTextEx(font, line9, font_size_f, spacing).x);
    const w10: i32 = @intFromFloat(rl.measureTextEx(font, line10, font_size_f, spacing).x);
    const w11: i32 = @intFromFloat(rl.measureTextEx(font, line11, font_size_f, spacing).x);
    const w12: i32 = @intFromFloat(rl.measureTextEx(font, line12, font_size_f, spacing).x);
    const w13: i32 = @intFromFloat(rl.measureTextEx(font, line13, font_size_f, spacing).x);
    const w14: i32 = @intFromFloat(rl.measureTextEx(font, line14, font_size_f, spacing).x);
    const w15: i32 = @intFromFloat(rl.measureTextEx(font, line15, font_size_f, spacing).x);
    const w16: i32 = @intFromFloat(rl.measureTextEx(font, line16, font_size_f, spacing).x);
    const w17: i32 = @intFromFloat(rl.measureTextEx(font, line17, font_size_f, spacing).x);
    const w18: i32 = @intFromFloat(rl.measureTextEx(font, line18, font_size_f, spacing).x);
    const w19: i32 = @intFromFloat(rl.measureTextEx(font, line19, font_size_f, spacing).x);
    const w20: i32 = @intFromFloat(rl.measureTextEx(font, line20, font_size_f, spacing).x);
    const w21: i32 = @intFromFloat(rl.measureTextEx(font, line21, font_size_f, spacing).x);
    const w22: i32 = @intFromFloat(rl.measureTextEx(font, line22, font_size_f, spacing).x);
    const w23: i32 = @intFromFloat(rl.measureTextEx(font, line23, font_size_f, spacing).x);
    const w24: i32 = @intFromFloat(rl.measureTextEx(font, line24, font_size_f, spacing).x);
    const w25: i32 = @intFromFloat(rl.measureTextEx(font, line25, font_size_f, spacing).x);
    const w26: i32 = @intFromFloat(rl.measureTextEx(font, line26, font_size_f, spacing).x);
    const w27: i32 = @intFromFloat(rl.measureTextEx(font, line27, font_size_f, spacing).x);
    const w28: i32 = @intFromFloat(rl.measureTextEx(font, line28, font_size_f, spacing).x);

    var max_w: i32 = w1;
    if (w2 > max_w) max_w = w2;
    if (w3 > max_w) max_w = w3;
    if (w4 > max_w) max_w = w4;
    if (w5 > max_w) max_w = w5;
    if (w6 > max_w) max_w = w6;
    if (w7 > max_w) max_w = w7;
    if (w8 > max_w) max_w = w8;
    if (w9 > max_w) max_w = w9;
    if (w10 > max_w) max_w = w10;
    if (w11 > max_w) max_w = w11;
    if (w12 > max_w) max_w = w12;
    if (w13 > max_w) max_w = w13;
    if (w14 > max_w) max_w = w14;
    if (w15 > max_w) max_w = w15;
    if (w16 > max_w) max_w = w16;
    if (w17 > max_w) max_w = w17;
    if (w18 > max_w) max_w = w18;
    if (w19 > max_w) max_w = w19;
    if (w20 > max_w) max_w = w20;
    if (w21 > max_w) max_w = w21;
    if (w22 > max_w) max_w = w22;
    if (w23 > max_w) max_w = w23;
    if (w24 > max_w) max_w = w24;
    if (w25 > max_w) max_w = w25;
    if (w26 > max_w) max_w = w26;
    if (w27 > max_w) max_w = w27;
    if (w28 > max_w) max_w = w28;

    const box_w: i32 = max_w + padding * 2;
    const box_h: i32 = (line_height * 28) + padding * 2;

    // Draw background and border
    rl.drawRectangle(x, y, box_w, box_h, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 180 });
    rl.drawRectangleLines(x, y, box_w, box_h, rl.Color.ray_white);

    // Draw text lines
    var current_y = y + padding;
    rl.drawTextEx(font, line1, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.ray_white);
    current_y += line_height;
    rl.drawTextEx(font, line2, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.lime);
    current_y += line_height;
    rl.drawTextEx(font, line3, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.lime);
    current_y += line_height;
    rl.drawTextEx(font, line4, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.lime);
    current_y += line_height;
    rl.drawTextEx(font, line5, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.lime);
    current_y += line_height;
    rl.drawTextEx(font, line6, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.lime);
    current_y += line_height;
    rl.drawTextEx(font, line7, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.lime);
    current_y += line_height;
    rl.drawTextEx(font, line8, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.lime);
    current_y += line_height;
    rl.drawTextEx(font, line9, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.lime);
    current_y += line_height;
    rl.drawTextEx(font, line10, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.yellow);
    current_y += line_height;
    rl.drawTextEx(font, line11, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.yellow);
    current_y += line_height;
    rl.drawTextEx(font, line12, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.yellow);
    current_y += line_height;
    rl.drawTextEx(font, line13, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.yellow);
    current_y += line_height;
    rl.drawTextEx(font, line14, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.ray_white);
    current_y += line_height;
    rl.drawTextEx(font, line15, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.yellow);
    current_y += line_height;
    rl.drawTextEx(font, line16, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.ray_white);
    current_y += line_height;
    rl.drawTextEx(font, line17, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.ray_white);
    current_y += line_height;
    rl.drawTextEx(font, line18, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.ray_white);
    current_y += line_height;
    rl.drawTextEx(font, line19, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.yellow);
    current_y += line_height;
    rl.drawTextEx(font, line20, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.yellow);
    current_y += line_height;
    rl.drawTextEx(font, line21, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.yellow);
    current_y += line_height;
    rl.drawTextEx(font, line22, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.yellow);
    current_y += line_height;
    rl.drawTextEx(font, line23, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.ray_white);
    current_y += line_height;
    rl.drawTextEx(font, line24, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.ray_white);
    current_y += line_height;
    rl.drawTextEx(font, line25, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.yellow);
    current_y += line_height;
    rl.drawTextEx(font, line26, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.yellow);
    current_y += line_height;
    rl.drawTextEx(font, line27, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.ray_white);
    current_y += line_height;
    rl.drawTextEx(font, line28, .{ .x = @floatFromInt(x + padding), .y = @floatFromInt(current_y) }, font_size_f, spacing, rl.Color.gray);
}
