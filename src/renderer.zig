const std = @import("std");
const raylib = @import("raylib");

pub const Renderer = struct {
    ortho_camera: raylib.Camera3D,

    pub fn init() Renderer {
        const orthoCameraPosition = raylib.Vector3{ .x = 24.0, .y = 24.0, .z = 24.0 };
        const orthoCameraTarget = raylib.Vector3{ .x = 4.0, .y = 2.0, .z = 4.0 };

        return .{
            .ortho_camera = .{
                .position = orthoCameraPosition,
                .target = orthoCameraTarget,
                .up = raylib.Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 },
                .fovy = 45.0,
                .projection = raylib.CameraProjection.orthographic,
            },
        };
    }
    pub fn render(self: *Renderer, world: anytype) void {
        raylib.beginMode3D(self.ortho_camera);
        defer raylib.endMode3D();

        raylib.drawGrid(20, 1.0);

        for (0..10) |x| {
            for (0..10) |y| {
                for (0..10) |z| {
                    const xu8: u8 = @intCast(x);
                    const yu8: u8 = @intCast(y);
                    const zu8: u8 = @intCast(z);

                    const block_type = world.getBlock(xu8, yu8, zu8);
                    if (block_type > 0) { // Zero is air block everything else is a solid or a liquid. I might add gasses for my asses later on hrrrrmmmmm
                        const pos = raylib.Vector3{
                            .x = @as(f32, @floatFromInt(x)),
                            .y = @as(f32, @floatFromInt(y)),
                            .z = @as(f32, @floatFromInt(z)),
                        };
                        raylib.drawCube(pos, 1.0, 1.0, 1.0, raylib.Color.gray);
                        raylib.drawCubeWires(pos, 1.0, 1.0, 1.0, raylib.Color.sky_blue);
                    }
                }
            }
        }
    }
};
