import std.stdio;
import std.math;
import std.conv;

struct Vec3 {
    double x, y, z;

    Vec3 opBinary(string op)(Vec3 b) const if (op == "+") {
        return Vec3(x + b.x, y + b.y, z + b.z);
    }

    Vec3 opBinary(string op)(Vec3 b) const if (op == "-") {
        return Vec3(x - b.x, y - b.y, z - b.z);
    }

    Vec3 opBinary(string op)(double s) const if (op == "*") {
        return Vec3(x * s, y * s, z * s);
    }

    Vec3 opBinaryRight(string op)(double s) const if (op == "*") {
        return Vec3(s * x, s * y, s * z);
    }

    double dot(Vec3 b) const {
        return x * b.x + y * b.y + z * b.z;
    }

    Vec3 cross(Vec3 b) const {
        return Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);
    }

    double length() const {
        return sqrt(x * x + y * y + z * z);
    }

    Vec3 norm() const {
        double l = length();
        if (l == 0) return Vec3(0, 0, 0);
        return Vec3(x / l, y / l, z / l);
    }

    Vec3 mul(Vec3 b) const {
        return Vec3(x * b.x, y * b.y, z * b.z);
    }
}

struct Ray {
    Vec3 origin, dir;
}

struct Sphere {
    Vec3 center;
    double radius;
    Vec3 color;
    double refl;
    double specExp;
}

struct Light {
    Vec3 pos;
    double intensity;
}

struct HitRecord {
    double t;
    Vec3 point;
    Vec3 normal;
    Vec3 color;
    double refl;
    double specExp;
    bool hit;
}

immutable Sphere[5] spheres = [
    Sphere(Vec3(-2, 1, 0), 1.0, Vec3(0.9, 0.2, 0.2), 0.3, 50),
    Sphere(Vec3(0, 0.75, 0), 0.75, Vec3(0.2, 0.9, 0.2), 0.2, 30),
    Sphere(Vec3(2, 1, 0), 1.0, Vec3(0.2, 0.2, 0.9), 0.4, 80),
    Sphere(Vec3(-0.75, 0.4, -1.5), 0.4, Vec3(0.9, 0.9, 0.2), 0.5, 100),
    Sphere(Vec3(1.5, 0.5, -1), 0.5, Vec3(0.9, 0.2, 0.9), 0.6, 60),
];

immutable Light[2] lights = [
    Light(Vec3(-3, 5, -3), 0.7),
    Light(Vec3(3, 3, -1), 0.4),
];

double intersectSphere(Ray ray, Sphere s) {
    Vec3 oc = ray.origin - s.center;
    double a = ray.dir.dot(ray.dir);
    double b = 2.0 * oc.dot(ray.dir);
    double c = oc.dot(oc) - s.radius * s.radius;
    double disc = b * b - 4.0 * a * c;
    if (disc < 0) return -1.0;
    double sqrtDisc = sqrt(disc);
    double t1 = (-b - sqrtDisc) / (2.0 * a);
    if (t1 > 1e-6) return t1;
    double t2 = (-b + sqrtDisc) / (2.0 * a);
    if (t2 > 1e-6) return t2;
    return -1.0;
}

double intersectGround(Ray ray) {
    if (fabs(ray.dir.y) < 1e-10) return -1.0;
    double t = -ray.origin.y / ray.dir.y;
    if (t > 1e-6) return t;
    return -1.0;
}

Vec3 checkerboardColor(Vec3 point) {
    int fx = cast(int)floor(point.x < 0 ? point.x - 1 : point.x);
    int fz = cast(int)floor(point.z < 0 ? point.z - 1 : point.z);
    // Fix: for negative values, floor already handles correctly, but the spec says
    // fx = x<0 ? floor(x-1) : floor(x)
    // We need to recompute using the spec's formula exactly
    double rawFx = point.x < 0 ? floor(point.x - 1) : floor(point.x);
    double rawFz = point.z < 0 ? floor(point.z - 1) : floor(point.z);
    int ifx = cast(int)rawFx;
    int ifz = cast(int)rawFz;
    if ((ifx + ifz) & 1)
        return Vec3(0.3, 0.3, 0.3);
    else
        return Vec3(0.8, 0.8, 0.8);
}

HitRecord sceneIntersect(Ray ray) {
    HitRecord rec;
    rec.hit = false;
    rec.t = double.max;

    // Check spheres
    foreach (ref s; spheres) {
        double t = intersectSphere(ray, s);
        if (t > 1e-6 && t < rec.t) {
            rec.t = t;
            rec.point = ray.origin + ray.dir * t;
            rec.normal = (rec.point - s.center).norm();
            rec.color = s.color;
            rec.refl = s.refl;
            rec.specExp = s.specExp;
            rec.hit = true;
        }
    }

    // Check ground
    double tg = intersectGround(ray);
    if (tg > 1e-6 && tg < rec.t) {
        rec.t = tg;
        rec.point = ray.origin + ray.dir * tg;
        rec.normal = Vec3(0, 1, 0);
        rec.color = checkerboardColor(rec.point);
        rec.refl = 0.3;
        rec.specExp = 10;
        rec.hit = true;
    }

    return rec;
}

bool isShadowed(Vec3 point, Vec3 lightDir, double lightDist) {
    Ray shadowRay = Ray(point + lightDir * 1e-4, lightDir);

    foreach (ref s; spheres) {
        double t = intersectSphere(shadowRay, s);
        if (t > 1e-6 && t < lightDist) return true;
    }

    double tg = intersectGround(shadowRay);
    if (tg > 1e-6 && tg < lightDist) return true;

    return false;
}

Vec3 reflectVec(Vec3 v, Vec3 n) {
    return v - n * (2.0 * v.dot(n));
}

Vec3 sky(Vec3 dir) {
    double t = 0.5 * (dir.y + 1.0);
    return Vec3(1, 1, 1) * (1.0 - t) + Vec3(0.5, 0.7, 1.0) * t;
}

Vec3 trace(Ray ray, int depth) {
    if (depth > 5) return sky(ray.dir);

    HitRecord rec = sceneIntersect(ray);
    if (!rec.hit) return sky(ray.dir);

    // Ambient
    Vec3 localColor = rec.color * 0.1;

    // Lighting
    foreach (ref light; lights) {
        Vec3 toLight = light.pos - rec.point;
        double lightDist = toLight.length();
        Vec3 lightDir = toLight.norm();
        double nDotL = rec.normal.dot(lightDir);

        if (isShadowed(rec.point, lightDir, lightDist)) continue;

        if (nDotL > 0) {
            // Diffuse
            localColor = localColor + rec.color * (nDotL * light.intensity);

            // Specular
            Vec3 negLightDir = lightDir * -1.0;
            Vec3 refl = reflectVec(negLightDir, rec.normal);
            Vec3 negRayDir = ray.dir * -1.0;
            double specAngle = fmax(0.0, negRayDir.dot(refl));
            double specPow = pow(specAngle, rec.specExp) * light.intensity;
            localColor = localColor + Vec3(1, 1, 1) * specPow;
        }
    }

    // Reflection
    if (rec.refl > 0 && depth < 5) {
        Vec3 reflDir = reflectVec(ray.dir, rec.normal);
        Ray reflRay = Ray(rec.point + reflDir * 1e-4, reflDir);
        Vec3 reflColor = trace(reflRay, depth + 1);
        return localColor * (1.0 - rec.refl) + reflColor * rec.refl;
    }

    return localColor;
}

double clamp01(double v) {
    if (v < 0) return 0;
    if (v > 1) return 1;
    return v;
}

void main(string[] args) {
    int width = 800;
    int height = 600;
    if (args.length >= 3) {
        width = to!int(args[1]);
        height = to!int(args[2]);
    }

    Vec3 camPos = Vec3(0, 1.5, -5);
    Vec3 lookAt = Vec3(0, 0.5, 0);
    Vec3 up = Vec3(0, 1, 0);
    double fov = 60.0;

    Vec3 forward = (lookAt - camPos).norm();
    Vec3 right = forward.cross(up).norm();
    Vec3 camUp = right.cross(forward).norm();

    double fovRad = fov * PI / 180.0;
    double halfH = tan(fovRad / 2.0);
    double halfW = (cast(double)width / cast(double)height) * halfH;

    auto writer = stdout;

    // Write PPM header
    writer.writef("P6\n%d %d\n255\n", width, height);

    // Render
    ubyte[3] pixel;
    for (int j = 0; j < height; j++) {
        for (int i = 0; i < width; i++) {
            double u = (2.0 * ((cast(double)i + 0.5) / cast(double)width) - 1.0) * halfW;
            double v = (1.0 - 2.0 * ((cast(double)j + 0.5) / cast(double)height)) * halfH;

            Vec3 dir = (forward + right * u + camUp * v).norm();
            Ray ray = Ray(camPos, dir);

            Vec3 col = trace(ray, 0);

            // Gamma correction
            col.x = pow(clamp01(col.x), 1.0 / 2.2);
            col.y = pow(clamp01(col.y), 1.0 / 2.2);
            col.z = pow(clamp01(col.z), 1.0 / 2.2);

            pixel[0] = cast(ubyte)(col.x * 255.0 + 0.5);
            pixel[1] = cast(ubyte)(col.y * 255.0 + 0.5);
            pixel[2] = cast(ubyte)(col.z * 255.0 + 0.5);

            writer.rawWrite(pixel[]);
        }
    }
}
