#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

/* ── Vector math ────────────────────────────────────────────────── */

typedef struct { double x, y, z; } Vec3;

static inline Vec3 vec3(double x, double y, double z) {
    return (Vec3){x, y, z};
}
static inline Vec3 vadd(Vec3 a, Vec3 b) {
    return (Vec3){a.x+b.x, a.y+b.y, a.z+b.z};
}
static inline Vec3 vsub(Vec3 a, Vec3 b) {
    return (Vec3){a.x-b.x, a.y-b.y, a.z-b.z};
}
static inline Vec3 vmul(Vec3 a, double t) {
    return (Vec3){a.x*t, a.y*t, a.z*t};
}
static inline Vec3 vmulv(Vec3 a, Vec3 b) {
    return (Vec3){a.x*b.x, a.y*b.y, a.z*b.z};
}
static inline double vdot(Vec3 a, Vec3 b) {
    return a.x*b.x + a.y*b.y + a.z*b.z;
}
static inline Vec3 vcross(Vec3 a, Vec3 b) {
    return (Vec3){a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x};
}
static inline double vlen(Vec3 v) {
    return sqrt(vdot(v, v));
}
static inline Vec3 vnorm(Vec3 v) {
    double l = vlen(v);
    return (Vec3){v.x/l, v.y/l, v.z/l};
}
static inline Vec3 vreflect(Vec3 v, Vec3 n) {
    return vsub(v, vmul(n, 2.0 * vdot(v, n)));
}
static inline double clamp01(double x) {
    return x < 0.0 ? 0.0 : (x > 1.0 ? 1.0 : x);
}

/* ── Scene objects ──────────────────────────────────────────────── */

typedef struct {
    Vec3 center;
    double radius;
    Vec3 color;
    double reflectivity;
    double specular;
} Sphere;

typedef struct {
    Vec3 position;
    double intensity;
} Light;

typedef struct {
    Vec3 origin;
    Vec3 dir;
} Ray;

/* ── Scene definition ───────────────────────────────────────────── */

static const Sphere spheres[] = {
    { {-2.0, 1.0, 0.0},   1.0,  {0.9, 0.2, 0.2}, 0.3, 50.0  },
    { { 0.0, 0.75, 0.0},  0.75, {0.2, 0.9, 0.2}, 0.2, 30.0  },
    { { 2.0, 1.0, 0.0},   1.0,  {0.2, 0.2, 0.9}, 0.4, 80.0  },
    { {-0.75, 0.4, -1.5}, 0.4,  {0.9, 0.9, 0.2}, 0.5, 100.0 },
    { { 1.5, 0.5, -1.0},  0.5,  {0.9, 0.2, 0.9}, 0.6, 60.0  },
};
#define NUM_SPHERES 5

static const Light lights[] = {
    { {-3.0, 5.0, -3.0}, 0.7 },
    { { 3.0, 3.0, -1.0}, 0.4 },
};
#define NUM_LIGHTS 2

static const double AMBIENT = 0.1;
static const double GROUND_Y = 0.0;
static const double GROUND_REFLECT = 0.3;
static const double GROUND_SPECULAR = 10.0;
static const double CHECK_SIZE = 1.0;
static const int MAX_DEPTH = 5;
static const double EPSILON = 1e-6;
static const double INF = 1e20;

/* ── Intersection routines ──────────────────────────────────────── */

static double intersect_sphere(Ray r, const Sphere *s) {
    Vec3 oc = vsub(r.origin, s->center);
    double b = vdot(oc, r.dir);
    double c = vdot(oc, oc) - s->radius * s->radius;
    double disc = b * b - c;
    if (disc < 0.0) return INF;
    double sq = sqrt(disc);
    double t1 = -b - sq;
    if (t1 > EPSILON) return t1;
    double t2 = -b + sq;
    if (t2 > EPSILON) return t2;
    return INF;
}

static double intersect_ground(Ray r) {
    if (fabs(r.dir.y) < EPSILON) return INF;
    double t = (GROUND_Y - r.origin.y) / r.dir.y;
    return t > EPSILON ? t : INF;
}

/* ── Hit info ───────────────────────────────────────────────────── */

typedef struct {
    int hit;
    double t;
    Vec3 point;
    Vec3 normal;
    Vec3 color;
    double reflectivity;
    double specular;
} HitInfo;

static HitInfo scene_intersect(Ray r) {
    HitInfo best;
    best.hit = 0;
    best.t = INF;

    /* spheres */
    for (int i = 0; i < NUM_SPHERES; i++) {
        double t = intersect_sphere(r, &spheres[i]);
        if (t < best.t) {
            best.hit = 1;
            best.t = t;
            best.point = vadd(r.origin, vmul(r.dir, t));
            best.normal = vnorm(vsub(best.point, spheres[i].center));
            best.color = spheres[i].color;
            best.reflectivity = spheres[i].reflectivity;
            best.specular = spheres[i].specular;
        }
    }

    /* ground plane */
    double tg = intersect_ground(r);
    if (tg < best.t) {
        best.hit = 1;
        best.t = tg;
        best.point = vadd(r.origin, vmul(r.dir, tg));
        best.normal = vec3(0.0, 1.0, 0.0);
        /* checkerboard – match reference: shift negative coords by -1 */
        double px = best.point.x / CHECK_SIZE;
        double pz = best.point.z / CHECK_SIZE;
        double fx = px < 0.0 ? floor(px - 1.0) : floor(px);
        double fz = pz < 0.0 ? floor(pz - 1.0) : floor(pz);
        int check = ((int)fx + (int)fz) & 1;
        if (check)
            best.color = vec3(0.3, 0.3, 0.3);
        else
            best.color = vec3(0.8, 0.8, 0.8);
        best.reflectivity = GROUND_REFLECT;
        best.specular = GROUND_SPECULAR;
    }

    return best;
}

/* ── Shading ────────────────────────────────────────────────────── */

static Vec3 trace(Ray r, int depth);

static int in_shadow(Vec3 point, Vec3 light_dir, double light_dist) {
    Ray shadow_ray;
    shadow_ray.origin = point;
    shadow_ray.dir = light_dir;
    for (int i = 0; i < NUM_SPHERES; i++) {
        double t = intersect_sphere(shadow_ray, &spheres[i]);
        if (t < light_dist) return 1;
    }
    /* check ground */
    double tg = intersect_ground(shadow_ray);
    if (tg < light_dist) return 1;
    return 0;
}

static Vec3 shade(HitInfo h, Ray r, int depth) {
    Vec3 result = vmul(h.color, AMBIENT);

    Vec3 offset_point = vadd(h.point, vmul(h.normal, EPSILON));

    for (int i = 0; i < NUM_LIGHTS; i++) {
        Vec3 to_light = vsub(lights[i].position, h.point);
        double dist = vlen(to_light);
        Vec3 light_dir = vmul(to_light, 1.0 / dist);

        if (in_shadow(offset_point, light_dir, dist))
            continue;

        /* diffuse */
        double n_dot_l = vdot(h.normal, light_dir);
        if (n_dot_l > 0.0) {
            result = vadd(result, vmul(h.color, n_dot_l * lights[i].intensity));

            /* specular (Phong) – only when surface faces light */
            Vec3 refl_dir = vreflect(vmul(light_dir, -1.0), h.normal);
            Vec3 view_dir = vmul(r.dir, -1.0);
            double spec_dot = vdot(view_dir, refl_dir);
            if (spec_dot > 0.0) {
                double spec = pow(spec_dot, h.specular) * lights[i].intensity;
                result = vadd(result, vec3(spec, spec, spec));
            }
        }
    }

    /* reflections */
    if (depth < MAX_DEPTH && h.reflectivity > 0.0) {
        Ray refl_ray;
        refl_ray.origin = offset_point;
        refl_ray.dir = vreflect(r.dir, h.normal);
        Vec3 refl_color = trace(refl_ray, depth + 1);
        result = vadd(vmul(result, 1.0 - h.reflectivity),
                       vmul(refl_color, h.reflectivity));
    }

    return result;
}

static Vec3 trace(Ray r, int depth) {
    HitInfo h = scene_intersect(r);
    if (!h.hit) {
        /* sky gradient */
        double t = 0.5 * (vnorm(r.dir).y + 1.0);
        return vadd(vmul(vec3(1.0, 1.0, 1.0), 1.0 - t),
                     vmul(vec3(0.5, 0.7, 1.0), t));
    }
    return shade(h, r, depth);
}

/* ── Camera ─────────────────────────────────────────────────────── */

typedef struct {
    Vec3 origin;
    Vec3 lower_left;
    Vec3 horizontal;
    Vec3 vertical;
} Camera;

static Camera make_camera(Vec3 from, Vec3 at, Vec3 vup, double vfov,
                           double aspect) {
    Camera cam;
    double theta = vfov * M_PI / 180.0;
    double half_h = tan(theta / 2.0);
    double half_w = aspect * half_h;

    Vec3 w = vnorm(vsub(from, at));
    Vec3 u = vnorm(vcross(vup, w));
    Vec3 v = vcross(w, u);

    cam.origin = from;
    cam.horizontal = vmul(u, 2.0 * half_w);
    cam.vertical = vmul(v, 2.0 * half_h);
    cam.lower_left = vsub(vsub(vsub(from, vmul(u, half_w)),
                                vmul(v, half_h)), w);
    return cam;
}

static Ray cam_ray(const Camera *cam, double s, double t) {
    Ray r;
    r.origin = cam->origin;
    Vec3 target = vadd(vadd(cam->lower_left, vmul(cam->horizontal, s)),
                        vmul(cam->vertical, t));
    r.dir = vnorm(vsub(target, cam->origin));
    return r;
}

/* ── Main ───────────────────────────────────────────────────────── */

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s WIDTH HEIGHT\n", argv[0]);
        return 1;
    }
    int width = atoi(argv[1]);
    int height = atoi(argv[2]);
    if (width <= 0 || height <= 0) {
        fprintf(stderr, "Invalid dimensions\n");
        return 1;
    }

    double aspect = (double)width / (double)height;
    Camera cam = make_camera(vec3(0.0, 1.5, -5.0),
                              vec3(0.0, 0.5, 0.0),
                              vec3(0.0, 1.0, 0.0),
                              60.0, aspect);

    double inv_gamma = 1.0 / 2.2;

    /* allocate pixel buffer */
    size_t buf_size = (size_t)width * (size_t)height * 3;
    unsigned char *buf = (unsigned char *)malloc(buf_size);
    if (!buf) {
        fprintf(stderr, "Out of memory\n");
        return 1;
    }

    /* render */
    unsigned char *p = buf;
    for (int j = height - 1; j >= 0; j--) {
        double v = ((double)j + 0.5) / (double)height;
        for (int i = 0; i < width; i++) {
            double u = ((double)i + 0.5) / (double)width;
            Ray r = cam_ray(&cam, u, v);
            Vec3 col = trace(r, 0);

            /* gamma correction */
            col.x = pow(clamp01(col.x), inv_gamma);
            col.y = pow(clamp01(col.y), inv_gamma);
            col.z = pow(clamp01(col.z), inv_gamma);

            *p++ = (unsigned char)(col.x * 255.0 + 0.5);
            *p++ = (unsigned char)(col.y * 255.0 + 0.5);
            *p++ = (unsigned char)(col.z * 255.0 + 0.5);
        }
    }

    /* write PPM P6 */
    fprintf(stdout, "P6\n%d %d\n255\n", width, height);
    fwrite(buf, 1, buf_size, stdout);
    fflush(stdout);

    free(buf);
    return 0;
}
