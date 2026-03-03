import sys
import math
import struct

def main():
    width = int(sys.argv[1])
    height = int(sys.argv[2])

    # Local references for hot-path math
    sqrt = math.sqrt
    pow_ = math.pow
    tan = math.tan
    pi = math.pi
    floor = math.floor
    inf = float('inf')

    # --- Vector operations as inline functions on tuples ---
    def vadd(a, b):
        return (a[0] + b[0], a[1] + b[1], a[2] + b[2])

    def vsub(a, b):
        return (a[0] - b[0], a[1] - b[1], a[2] - b[2])

    def vmul(a, s):
        return (a[0] * s, a[1] * s, a[2] * s)

    def vdot(a, b):
        return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

    def vlength(a):
        return sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])

    def vnorm(a):
        l = sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
        if l == 0.0:
            return (0.0, 0.0, 0.0)
        inv = 1.0 / l
        return (a[0] * inv, a[1] * inv, a[2] * inv)

    def vmulv(a, b):
        return (a[0] * b[0], a[1] * b[1], a[2] * b[2])

    def vclamp(a):
        return (min(max(a[0], 0.0), 1.0), min(max(a[1], 0.0), 1.0), min(max(a[2], 0.0), 1.0))

    def vreflect(d, n):
        dn2 = 2.0 * (d[0] * n[0] + d[1] * n[1] + d[2] * n[2])
        return (d[0] - dn2 * n[0], d[1] - dn2 * n[1], d[2] - dn2 * n[2])

    # --- Scene definition ---
    # Spheres: (cx, cy, cz, radius, r, g, b, reflectivity, specular)
    spheres = [
        (-2.0, 1.0, 0.0, 1.0, 0.9, 0.2, 0.2, 0.3, 50.0),
        (0.0, 0.75, 0.0, 0.75, 0.2, 0.9, 0.2, 0.2, 30.0),
        (2.0, 1.0, 0.0, 1.0, 0.2, 0.2, 0.9, 0.4, 80.0),
        (-0.75, 0.4, -1.5, 0.4, 0.9, 0.9, 0.2, 0.5, 100.0),
        (1.5, 0.5, -1.0, 0.5, 0.9, 0.2, 0.9, 0.6, 60.0),
    ]

    # Lights: (px, py, pz, intensity)
    lights = [
        (-3.0, 5.0, -3.0, 0.7),
        (3.0, 3.0, -1.0, 0.4),
    ]

    ambient = 0.1
    max_depth = 5
    gamma_inv = 1.0 / 2.2
    eps = 1e-6

    # Ground plane at y=0
    ground_refl = 0.3

    # --- Camera setup ---
    cam_pos = (0.0, 1.5, -5.0)
    look_at = (0.0, 0.5, 0.0)
    up = (0.0, 1.0, 0.0)

    fov_rad = 60.0 * pi / 180.0
    half_h = tan(fov_rad / 2.0)
    aspect = width / height
    half_w = half_h * aspect

    forward = vnorm(vsub(look_at, cam_pos))
    right = vnorm((forward[1] * up[2] - forward[2] * up[1],
                    forward[2] * up[0] - forward[0] * up[2],
                    forward[0] * up[1] - forward[1] * up[0]))
    cam_up = (right[1] * forward[2] - right[2] * forward[1],
              right[2] * forward[0] - right[0] * forward[2],
              right[0] * forward[1] - right[1] * forward[0])

    # Pre-extract camera basis vectors
    rx, ry, rz = right
    ux, uy, uz = cam_up
    fx, fy, fz = forward
    cox, coy, coz = cam_pos

    # --- Ray-sphere intersection ---
    # Returns (t, sphere_index) or (inf, -1)
    def intersect_spheres(ox, oy, oz, dx, dy, dz):
        best_t = inf
        best_i = -1
        for i in range(5):
            s = spheres[i]
            ocx = ox - s[0]
            ocy = oy - s[1]
            ocz = oz - s[2]
            # a = 1 since d is normalized
            b = ocx * dx + ocy * dy + ocz * dz
            c = ocx * ocx + ocy * ocy + ocz * ocz - s[3] * s[3]
            disc = b * b - c
            if disc > 0.0:
                sq = sqrt(disc)
                t = -b - sq
                if t < eps:
                    t = -b + sq
                if eps < t < best_t:
                    best_t = t
                    best_i = i
        return best_t, best_i

    # --- Ray-ground intersection (y=0 plane) ---
    def intersect_ground(oy, dy):
        if dy >= -eps and dy <= eps:
            return inf
        t = -oy / dy
        if t < eps:
            return inf
        return t

    # --- Trace ray ---
    def trace(ox, oy, oz, dx, dy, dz, depth):
        if depth >= max_depth:
            return (0.0, 0.0, 0.0)

        # Find closest intersection
        t_sphere, si = intersect_spheres(ox, oy, oz, dx, dy, dz)
        t_ground = intersect_ground(oy, dy)

        if t_sphere >= inf and t_ground >= inf:
            # Sky gradient
            t_sky = 0.5 * (dy + 1.0)
            return (1.0 - 0.5 * t_sky, 1.0 - 0.3 * t_sky, 1.0)

        hit_ground = t_ground < t_sphere

        if hit_ground:
            t = t_ground
            hx = ox + dx * t
            hy = 0.0
            hz = oz + dz * t
            nx, ny, nz = 0.0, 1.0, 0.0

            # Checkerboard (handle negative coords like Rust reference)
            fx_ = floor(hx - 1.0) if hx < 0.0 else floor(hx)
            fz_ = floor(hz - 1.0) if hz < 0.0 else floor(hz)
            check = (int(fx_) + int(fz_)) & 1
            if check:
                cr, cg, cb = 0.3, 0.3, 0.3
            else:
                cr, cg, cb = 0.8, 0.8, 0.8
            refl = ground_refl
            spec_pow = 10.0
        else:
            t = t_sphere
            s = spheres[si]
            hx = ox + dx * t
            hy = oy + dy * t
            hz = oz + dz * t
            inv_r = 1.0 / s[3]
            nx = (hx - s[0]) * inv_r
            ny = (hy - s[1]) * inv_r
            nz = (hz - s[2]) * inv_r
            cr, cg, cb = s[4], s[5], s[6]
            refl = s[7]
            spec_pow = s[8]

        # Lighting
        lr, lg, lb = cr * ambient, cg * ambient, cb * ambient

        for light in lights:
            lx = light[0] - hx
            ly = light[1] - hy
            lz = light[2] - hz
            ld = sqrt(lx * lx + ly * ly + lz * lz)
            inv_ld = 1.0 / ld
            lx *= inv_ld
            ly *= inv_ld
            lz *= inv_ld

            # Shadow check
            st_sphere, _ = intersect_spheres(hx + nx * eps, hy + ny * eps, hz + nz * eps, lx, ly, lz)
            st_ground = intersect_ground(hy + ny * eps, ly)
            if st_sphere < ld or st_ground < ld:
                continue

            intensity = light[3]

            # Diffuse
            ndl = nx * lx + ny * ly + nz * lz
            if ndl > 0.0:
                diff = ndl * intensity
                lr += cr * diff
                lg += cg * diff
                lb += cb * diff

            # Specular (Phong)
            if spec_pow > 0.0 and ndl > 0.0:
                # Reflect -light_dir about normal: -L + 2*(N.L)*N
                dn2 = 2.0 * ndl
                ref_lx = -lx + dn2 * nx
                ref_ly = -ly + dn2 * ny
                ref_lz = -lz + dn2 * nz
                # View direction (from hit point to camera/ray origin)
                vdx = -dx
                vdy = -dy
                vdz = -dz
                rdv = ref_lx * vdx + ref_ly * vdy + ref_lz * vdz
                if rdv > 0.0:
                    sp = pow_(rdv, spec_pow) * intensity
                    lr += sp
                    lg += sp
                    lb += sp

        # Reflections
        if refl > 0.0 and depth < max_depth:
            # Reflect ray direction about normal
            dn2 = 2.0 * (dx * nx + dy * ny + dz * nz)
            rdx = dx - dn2 * nx
            rdy = dy - dn2 * ny
            rdz = dz - dn2 * nz
            ref_col = trace(hx + nx * eps, hy + ny * eps, hz + nz * eps,
                            rdx, rdy, rdz, depth + 1)
            one_minus_refl = 1.0 - refl
            lr = lr * one_minus_refl + ref_col[0] * refl
            lg = lg * one_minus_refl + ref_col[1] * refl
            lb = lb * one_minus_refl + ref_col[2] * refl

        return (lr, lg, lb)

    # --- Render ---
    pixels = bytearray(width * height * 3)
    idx = 0

    inv_w = 1.0 / width
    inv_h = 1.0 / height

    for j in range(height):
        v = 1.0 - 2.0 * (j + 0.5) * inv_h
        v_scaled = v * half_h
        for i in range(width):
            u = 2.0 * (i + 0.5) * inv_w - 1.0
            u_scaled = u * half_w

            # Ray direction
            dx = fx + u_scaled * rx + v_scaled * ux
            dy = fy + u_scaled * ry + v_scaled * uy
            dz = fz + u_scaled * rz + v_scaled * uz
            inv_len = 1.0 / sqrt(dx * dx + dy * dy + dz * dz)
            dx *= inv_len
            dy *= inv_len
            dz *= inv_len

            col = trace(cox, coy, coz, dx, dy, dz, 0)

            # Clamp and gamma correct
            r = col[0]
            g = col[1]
            b = col[2]
            if r > 1.0: r = 1.0
            elif r < 0.0: r = 0.0
            if g > 1.0: g = 1.0
            elif g < 0.0: g = 0.0
            if b > 1.0: b = 1.0
            elif b < 0.0: b = 0.0

            pixels[idx] = int(pow_(r, gamma_inv) * 255.0 + 0.5)
            pixels[idx + 1] = int(pow_(g, gamma_inv) * 255.0 + 0.5)
            pixels[idx + 2] = int(pow_(b, gamma_inv) * 255.0 + 0.5)
            idx += 3

    # Output PPM P6
    header = f"P6\n{width} {height}\n255\n".encode('ascii')
    out = sys.stdout.buffer
    out.write(header)
    out.write(pixels)

if __name__ == '__main__':
    main()
