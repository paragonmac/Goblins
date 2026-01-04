const raylib = @import("raylib");

pub fn sub(a: raylib.Vector3, b: raylib.Vector3) raylib.Vector3 {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

pub fn add(a: raylib.Vector3, b: raylib.Vector3) raylib.Vector3 {
    return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
}

pub fn scale(v: raylib.Vector3, s: f32) raylib.Vector3 {
    return .{ .x = v.x * s, .y = v.y * s, .z = v.z * s };
}

pub fn cross(a: raylib.Vector3, b: raylib.Vector3) raylib.Vector3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

pub fn dot(a: raylib.Vector3, b: raylib.Vector3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

pub fn normalize(v: raylib.Vector3) raylib.Vector3 {
    const len = @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (len == 0) return v;
    return scale(v, 1.0 / len);
}
