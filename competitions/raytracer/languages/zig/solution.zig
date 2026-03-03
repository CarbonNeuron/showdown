const std = @import("std");
const math = std.math;

const Vec3 = struct {
    x: f64,
    y: f64,
    z: f64,

    fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    fn mul(a: Vec3, s: f64) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    fn vmul(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x * b.x, .y = a.y * b.y, .z = a.z * b.z };
    }
    fn dot(a: Vec3, b: Vec3) f64 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }
    fn length(a: Vec3) f64 {
        return @sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    }
    fn normalize(a: Vec3) Vec3 {
        const l = a.length();
        if (l == 0) return .{ .x = 0, .y = 0, .z = 0 };
        return .{ .x = a.x / l, .y = a.y / l, .z = a.z / l };
    }
    fn clamp01(a: Vec3) Vec3 {
        return .{
            .x = @max(0.0, @min(1.0, a.x)),
            .y = @max(0.0, @min(1.0, a.y)),
            .z = @max(0.0, @min(1.0, a.z)),
        };
    }
};

const Sphere = struct {
    center: Vec3,
    radius: f64,
    color: Vec3,
    reflectivity: f64,
    spec_exp: f64,
};

const Light = struct {
    pos: Vec3,
    intensity: f64,
};

const HitRecord = struct {
    t: f64,
    point: Vec3,
    normal: Vec3,
    color: Vec3,
    reflectivity: f64,
    spec_exp: f64,
};

const spheres = [5]Sphere{
    .{ .center = .{ .x = -2, .y = 1, .z = 0 }, .radius = 1.0, .color = .{ .x = 0.9, .y = 0.2, .z = 0.2 }, .reflectivity = 0.3, .spec_exp = 50 },
    .{ .center = .{ .x = 0, .y = 0.75, .z = 0 }, .radius = 0.75, .color = .{ .x = 0.2, .y = 0.9, .z = 0.2 }, .reflectivity = 0.2, .spec_exp = 30 },
    .{ .center = .{ .x = 2, .y = 1, .z = 0 }, .radius = 1.0, .color = .{ .x = 0.2, .y = 0.2, .z = 0.9 }, .reflectivity = 0.4, .spec_exp = 80 },
    .{ .center = .{ .x = -0.75, .y = 0.4, .z = -1.5 }, .radius = 0.4, .color = .{ .x = 0.9, .y = 0.9, .z = 0.2 }, .reflectivity = 0.5, .spec_exp = 100 },
    .{ .center = .{ .x = 1.5, .y = 0.5, .z = -1 }, .radius = 0.5, .color = .{ .x = 0.9, .y = 0.2, .z = 0.9 }, .reflectivity = 0.6, .spec_exp = 60 },
};

const lights = [2]Light{
    .{ .pos = .{ .x = -3, .y = 5, .z = -3 }, .intensity = 0.7 },
    .{ .pos = .{ .x = 3, .y = 3, .z = -1 }, .intensity = 0.4 },
};

const ambient: f64 = 0.1;

fn intersectSphere(origin: Vec3, dir: Vec3, s: Sphere) f64 {
    const oc = Vec3.sub(origin, s.center);
    const a = Vec3.dot(dir, dir);
    const b = 2.0 * Vec3.dot(oc, dir);
    const c = Vec3.dot(oc, oc) - s.radius * s.radius;
    const disc = b * b - 4.0 * a * c;
    if (disc < 0) return -1.0;
    const sq = @sqrt(disc);
    const t1 = (-b - sq) / (2.0 * a);
    if (t1 > 1e-6) return t1;
    const t2 = (-b + sq) / (2.0 * a);
    if (t2 > 1e-6) return t2;
    return -1.0;
}

fn intersectPlane(origin: Vec3, dir: Vec3) f64 {
    if (@abs(dir.y) < 1e-12) return -1.0;
    const t = -origin.y / dir.y;
    if (t > 1e-6) return t;
    return -1.0;
}

fn checkerColor(p: Vec3) Vec3 {
    const fx: i64 = if (p.x < 0) @intFromFloat(@floor(p.x) - 1) else @intFromFloat(@floor(p.x));
    const fz: i64 = if (p.z < 0) @intFromFloat(@floor(p.z) - 1) else @intFromFloat(@floor(p.z));
    const check = @as(u64, @bitCast(fx +% fz)) & 1;
    if (check == 1) {
        return .{ .x = 0.3, .y = 0.3, .z = 0.3 };
    }
    return .{ .x = 0.8, .y = 0.8, .z = 0.8 };
}

fn traceRay(origin: Vec3, dir: Vec3) ?HitRecord {
    var closest_t: f64 = 1e30;
    var hit: ?HitRecord = null;

    for (&spheres) |*s| {
        const t = intersectSphere(origin, dir, s.*);
        if (t > 0 and t < closest_t) {
            closest_t = t;
            const p = Vec3.add(origin, dir.mul(t));
            const n = Vec3.sub(p, s.center).normalize();
            hit = .{
                .t = t,
                .point = p,
                .normal = n,
                .color = s.color,
                .reflectivity = s.reflectivity,
                .spec_exp = s.spec_exp,
            };
        }
    }

    const tp = intersectPlane(origin, dir);
    if (tp > 0 and tp < closest_t) {
        const p = Vec3.add(origin, dir.mul(tp));
        hit = .{
            .t = tp,
            .point = p,
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .color = checkerColor(p),
            .reflectivity = 0.3,
            .spec_exp = 10,
        };
    }

    return hit;
}

fn isInShadow(point: Vec3, lightDir: Vec3, lightDist: f64) bool {
    for (&spheres) |*s| {
        const t = intersectSphere(point, lightDir, s.*);
        if (t > 1e-6 and t < lightDist) return true;
    }
    const tp = intersectPlane(point, lightDir);
    if (tp > 1e-6 and tp < lightDist) return true;
    return false;
}

fn reflect(v: Vec3, n: Vec3) Vec3 {
    return Vec3.sub(v, n.mul(2.0 * Vec3.dot(v, n)));
}

fn sky(dir: Vec3) Vec3 {
    const d = dir.normalize();
    const t = 0.5 * (d.y + 1.0);
    const white = Vec3{ .x = 1, .y = 1, .z = 1 };
    const blue = Vec3{ .x = 0.5, .y = 0.7, .z = 1.0 };
    return Vec3.add(white.mul(1.0 - t), blue.mul(t));
}

fn shade(origin: Vec3, dir: Vec3, depth: u32) Vec3 {
    if (depth > 5) return sky(dir);

    const maybeHit = traceRay(origin, dir);
    if (maybeHit == null) return sky(dir);
    const hit = maybeHit.?;

    // Local shading
    var color = hit.color.mul(ambient);
    const viewDir = dir.mul(-1.0);

    for (&lights) |*light| {
        const toLight = Vec3.sub(light.pos, hit.point);
        const lightDist = toLight.length();
        const lightDir = toLight.normalize();
        const offsetPoint = Vec3.add(hit.point, hit.normal.mul(1e-4));

        if (isInShadow(offsetPoint, lightDir, lightDist)) continue;

        const nDotL = @max(0.0, Vec3.dot(hit.normal, lightDir));

        // Diffuse
        color = Vec3.add(color, hit.color.mul(nDotL * light.intensity));

        // Specular (white)
        if (nDotL > 0) {
            const reflDir = reflect(lightDir.mul(-1.0), hit.normal);
            const specAngle = @max(0.0, Vec3.dot(viewDir, reflDir));
            const specVal = math.pow(f64, specAngle, hit.spec_exp) * light.intensity;
            color = Vec3.add(color, .{ .x = specVal, .y = specVal, .z = specVal });
        }
    }

    // Reflection
    if (hit.reflectivity > 0 and depth < 5) {
        const reflDir = reflect(dir, hit.normal);
        const offsetPoint = Vec3.add(hit.point, hit.normal.mul(1e-4));
        const reflColor = shade(offsetPoint, reflDir, depth + 1);
        color = Vec3.add(color.mul(1.0 - hit.reflectivity), reflColor.mul(hit.reflectivity));
    }

    return color;
}

fn gamma(v: f64) f64 {
    return math.pow(f64, @max(0.0, @min(1.0, v)), 1.0 / 2.2);
}

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: solution WIDTH HEIGHT\n", .{});
        std.process.exit(1);
    }

    const width = try std.fmt.parseInt(u32, args[1], 10);
    const height = try std.fmt.parseInt(u32, args[2], 10);

    const camPos = Vec3{ .x = 0, .y = 1.5, .z = -5 };
    const lookAt = Vec3{ .x = 0, .y = 0.5, .z = 0 };
    const up = Vec3{ .x = 0, .y = 1, .z = 0 };
    const fov: f64 = 60.0 * math.pi / 180.0;

    const forward = Vec3.sub(lookAt, camPos).normalize();
    const right = Vec3.cross(forward, up).normalize();
    const camUp = Vec3.cross(right, forward).normalize();

    const halfHeight = @tan(fov / 2.0);
    const aspect = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(height));
    const halfWidth = aspect * halfHeight;

    const w_f: f64 = @floatFromInt(width);
    const h_f: f64 = @floatFromInt(height);

    // Allocate buffer
    const bufSize = @as(usize, width) * @as(usize, height) * 3;
    const pixels = try std.heap.page_allocator.alloc(u8, bufSize);
    defer std.heap.page_allocator.free(pixels);

    for (0..height) |j| {
        for (0..width) |i| {
            const u = (2.0 * ((@as(f64, @floatFromInt(i)) + 0.5) / w_f) - 1.0) * halfWidth;
            const v = (1.0 - 2.0 * ((@as(f64, @floatFromInt(j)) + 0.5) / h_f)) * halfHeight;

            const dir = Vec3.add(Vec3.add(forward, right.mul(u)), camUp.mul(v)).normalize();
            const color = shade(camPos, dir, 0);
            const clamped = color.clamp01();

            const idx = (j * @as(usize, width) + i) * 3;
            pixels[idx] = @intFromFloat(gamma(clamped.x) * 255.0 + 0.5);
            pixels[idx + 1] = @intFromFloat(gamma(clamped.y) * 255.0 + 0.5);
            pixels[idx + 2] = @intFromFloat(gamma(clamped.z) * 255.0 + 0.5);
        }
    }

    const stdout = std.io.getStdOut();
    var bw = std.io.bufferedWriter(stdout.writer());
    const writer = bw.writer();
    try writer.print("P6\n{d} {d}\n255\n", .{ width, height });
    try writer.writeAll(pixels);
    try bw.flush();
}
