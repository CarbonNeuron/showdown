#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>

struct Vec3 {
    double x, y, z;
    Vec3() : x(0), y(0), z(0) {}
    Vec3(double x, double y, double z) : x(x), y(y), z(z) {}
    Vec3 operator+(const Vec3& b) const { return {x+b.x, y+b.y, z+b.z}; }
    Vec3 operator-(const Vec3& b) const { return {x-b.x, y-b.y, z-b.z}; }
    Vec3 operator*(double t) const { return {x*t, y*t, z*t}; }
    double dot(const Vec3& b) const { return x*b.x + y*b.y + z*b.z; }
    Vec3 cross(const Vec3& b) const {
        return {y*b.z - z*b.y, z*b.x - x*b.z, x*b.y - y*b.x};
    }
    double length() const { return std::sqrt(x*x + y*y + z*z); }
    Vec3 norm() const { double l = length(); return {x/l, y/l, z/l}; }
    Vec3 clamp01() const {
        return {x<0?0:(x>1?1:x), y<0?0:(y>1?1:y), z<0?0:(z>1?1:z)};
    }
};

struct Ray { Vec3 origin, dir; };

struct Sphere {
    Vec3 center;
    double radius;
    Vec3 color;
    double refl;
    double specExp;
};

struct Light {
    Vec3 pos;
    double intensity;
};

static const double INF = 1e20;
static const double EPS = 1e-6;
static const int MAX_DEPTH = 5;
static const double AMBIENT = 0.1;

static const Vec3 camPos(0, 1.5, -5);
static const Vec3 lookAt(0, 0.5, 0);
static const Vec3 up(0, 1, 0);
static const double fov = 60.0;

static std::vector<Sphere> spheres = {
    {{-2, 1, 0}, 1.0, {0.9, 0.2, 0.2}, 0.3, 50},
    {{0, 0.75, 0}, 0.75, {0.2, 0.9, 0.2}, 0.2, 30},
    {{2, 1, 0}, 1.0, {0.2, 0.2, 0.9}, 0.4, 80},
    {{-0.75, 0.4, -1.5}, 0.4, {0.9, 0.9, 0.2}, 0.5, 100},
    {{1.5, 0.5, -1}, 0.5, {0.9, 0.2, 0.9}, 0.6, 60},
};

static std::vector<Light> lights = {
    {{-3, 5, -3}, 0.7},
    {{3, 3, -1}, 0.4},
};

static double intersectSphere(const Ray& ray, const Sphere& s) {
    Vec3 oc = ray.origin - s.center;
    double b = oc.dot(ray.dir);
    double c = oc.dot(oc) - s.radius * s.radius;
    double disc = b * b - c;
    if (disc < 0) return -1;
    double sq = std::sqrt(disc);
    double t0 = -b - sq;
    double t1 = -b + sq;
    if (t0 > EPS) return t0;
    if (t1 > EPS) return t1;
    return -1;
}

static double intersectGround(const Ray& ray) {
    if (std::fabs(ray.dir.y) < EPS) return -1;
    double t = -ray.origin.y / ray.dir.y;
    return t > EPS ? t : -1;
}

static Vec3 reflect(const Vec3& v, const Vec3& n) {
    return v - n * (2 * v.dot(n));
}

static bool inShadow(const Vec3& point, const Vec3& lightDir, double lightDist) {
    Ray shadowRay = {point, lightDir};
    for (auto& s : spheres) {
        double t = intersectSphere(shadowRay, s);
        if (t > 0 && t < lightDist) return true;
    }
    double t = intersectGround(shadowRay);
    if (t > 0 && t < lightDist) return true;
    return false;
}

static Vec3 sky(const Vec3& dir) {
    double t = 0.5 * (dir.y + 1.0);
    return Vec3(1, 1, 1) * (1.0 - t) + Vec3(0.5, 0.7, 1.0) * t;
}

static Vec3 checkerColor(double x, double z) {
    int fx = (int)std::floor(x < 0 ? x - 1 : x);
    int fz = (int)std::floor(z < 0 ? z - 1 : z);
    if ((fx + fz) & 1)
        return Vec3(0.3, 0.3, 0.3);
    else
        return Vec3(0.8, 0.8, 0.8);
}

static Vec3 trace(const Ray& ray, int depth) {
    if (depth > MAX_DEPTH) return sky(ray.dir);

    double closestT = INF;
    int hitSphere = -1;
    bool hitGround = false;

    for (int i = 0; i < (int)spheres.size(); i++) {
        double t = intersectSphere(ray, spheres[i]);
        if (t > 0 && t < closestT) {
            closestT = t;
            hitSphere = i;
            hitGround = false;
        }
    }

    double tGround = intersectGround(ray);
    if (tGround > 0 && tGround < closestT) {
        closestT = tGround;
        hitGround = true;
        hitSphere = -1;
    }

    if (hitSphere < 0 && !hitGround) return sky(ray.dir);

    Vec3 hitPoint = ray.origin + ray.dir * closestT;
    Vec3 normal, color;
    double refl, specExp;

    if (hitGround) {
        normal = Vec3(0, 1, 0);
        color = checkerColor(hitPoint.x, hitPoint.z);
        refl = 0.3;
        specExp = 10;
    } else {
        const Sphere& s = spheres[hitSphere];
        normal = (hitPoint - s.center).norm();
        color = s.color;
        refl = s.refl;
        specExp = s.specExp;
    }

    Vec3 localColor = color * AMBIENT;

    for (auto& light : lights) {
        Vec3 toLight = light.pos - hitPoint;
        double lightDist = toLight.length();
        Vec3 lightDir = toLight.norm();
        double nDotL = normal.dot(lightDir);

        Vec3 shadowOrigin = hitPoint + normal * EPS;
        if (inShadow(shadowOrigin, lightDir, lightDist)) continue;

        if (nDotL > 0) {
            Vec3 diffuse = color * (nDotL * light.intensity);
            localColor = localColor + diffuse;

            Vec3 reflDir = reflect(lightDir * -1, normal);
            double spec = std::pow(std::fmax(0.0, (ray.dir * -1).dot(reflDir)), specExp);
            double sv = spec * light.intensity;
            localColor = localColor + Vec3(sv, sv, sv);
        }
    }

    if (refl > 0 && depth < MAX_DEPTH) {
        Vec3 reflDir = reflect(ray.dir, normal);
        Ray reflRay = {hitPoint + normal * EPS, reflDir};
        Vec3 reflColor = trace(reflRay, depth + 1);
        return localColor * (1.0 - refl) + reflColor * refl;
    }

    return localColor;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        std::fprintf(stderr, "Usage: solution WIDTH HEIGHT\n");
        return 1;
    }
    int W = std::atoi(argv[1]);
    int H = std::atoi(argv[2]);
    double aspect = (double)W / (double)H;
    double fovRad = fov * M_PI / 180.0;
    double halfHeight = std::tan(fovRad / 2.0);
    double halfWidth = aspect * halfHeight;

    Vec3 forward = (lookAt - camPos).norm();
    Vec3 right = forward.cross(up).norm();
    Vec3 camUp = right.cross(forward).norm();

    std::vector<uint8_t> pixels(W * H * 3);

    for (int j = 0; j < H; j++) {
        for (int i = 0; i < W; i++) {
            double u = (2.0 * ((i + 0.5) / W) - 1.0) * halfWidth;
            double v = (1.0 - 2.0 * ((j + 0.5) / H)) * halfHeight;
            Vec3 dir = (forward + right * u + camUp * v).norm();
            Ray ray = {camPos, dir};
            Vec3 col = trace(ray, 0);
            col = col.clamp01();
            double r = std::pow(col.x, 1.0 / 2.2);
            double g = std::pow(col.y, 1.0 / 2.2);
            double b = std::pow(col.z, 1.0 / 2.2);
            int idx = (j * W + i) * 3;
            pixels[idx]     = (uint8_t)(r * 255.0 + 0.5);
            pixels[idx + 1] = (uint8_t)(g * 255.0 + 0.5);
            pixels[idx + 2] = (uint8_t)(b * 255.0 + 0.5);
        }
    }

#ifdef _WIN32
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    std::fprintf(stdout, "P6\n%d %d\n255\n", W, H);
    std::fwrite(pixels.data(), 1, pixels.size(), stdout);
    return 0;
}
