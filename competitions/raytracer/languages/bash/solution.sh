#!/bin/bash
# Bash raytracer — all computation done in awk (standard Unix tool with native floats)
export LC_ALL=C
exec gawk -v WIDTH="$1" -v HEIGHT="$2" 'BEGIN {
    # Scene constants
    PI = 3.14159265358979323846
    INF = 1e30
    EPS = 1e-6
    AMBIENT = 0.1
    MAX_DEPTH = 5
    GAMMA_INV = 1.0 / 2.2

    # Camera
    cam_x = 0; cam_y = 1.5; cam_z = -5
    look_x = 0; look_y = 0.5; look_z = 0
    up_x = 0; up_y = 1; up_z = 0

    # FOV
    fov_rad = 60.0 * PI / 180.0
    half_h = sin(fov_rad / 2.0) / cos(fov_rad / 2.0)
    aspect = WIDTH / HEIGHT
    half_w = half_h * aspect

    # Camera basis
    fw_x = look_x - cam_x; fw_y = look_y - cam_y; fw_z = look_z - cam_z
    l = sqrt(fw_x*fw_x + fw_y*fw_y + fw_z*fw_z)
    fw_x /= l; fw_y /= l; fw_z /= l

    ri_x = fw_y*up_z - fw_z*up_y
    ri_y = fw_z*up_x - fw_x*up_z
    ri_z = fw_x*up_y - fw_y*up_x
    l = sqrt(ri_x*ri_x + ri_y*ri_y + ri_z*ri_z)
    ri_x /= l; ri_y /= l; ri_z /= l

    cu_x = ri_y*fw_z - ri_z*fw_y
    cu_y = ri_z*fw_x - ri_x*fw_z
    cu_z = ri_x*fw_y - ri_y*fw_x

    # Spheres: cx,cy,cz,radius,r,g,b,refl,spec
    NSPH = 5
    split("-2 1 0 1 0.9 0.2 0.2 0.3 50", a)
    for(i=1;i<=9;i++) sph[0,i]=a[i]+0
    split("0 0.75 0 0.75 0.2 0.9 0.2 0.2 30", a)
    for(i=1;i<=9;i++) sph[1,i]=a[i]+0
    split("2 1 0 1 0.2 0.2 0.9 0.4 80", a)
    for(i=1;i<=9;i++) sph[2,i]=a[i]+0
    split("-0.75 0.4 -1.5 0.4 0.9 0.9 0.2 0.5 100", a)
    for(i=1;i<=9;i++) sph[3,i]=a[i]+0
    split("1.5 0.5 -1 0.5 0.9 0.2 0.9 0.6 60", a)
    for(i=1;i<=9;i++) sph[4,i]=a[i]+0

    # Lights: px,py,pz,intensity
    NLIGHT = 2
    lt[0,1]=-3; lt[0,2]=5; lt[0,3]=-3; lt[0,4]=0.7
    lt[1,1]=3;  lt[1,2]=3; lt[1,3]=-1; lt[1,4]=0.4

    ground_refl = 0.3
    ground_spec = 10.0

    # Output PPM header
    printf "P6\n%d %d\n255\n", WIDTH, HEIGHT

    inv_w = 1.0 / WIDTH
    inv_h = 1.0 / HEIGHT

    for (j = 0; j < HEIGHT; j++) {
        v = 1.0 - 2.0 * (j + 0.5) * inv_h
        v_scaled = v * half_h
        for (i = 0; i < WIDTH; i++) {
            u = 2.0 * (i + 0.5) * inv_w - 1.0
            u_scaled = u * half_w

            dx = fw_x + u_scaled * ri_x + v_scaled * cu_x
            dy = fw_y + u_scaled * ri_y + v_scaled * cu_y
            dz = fw_z + u_scaled * ri_z + v_scaled * cu_z
            il = 1.0 / sqrt(dx*dx + dy*dy + dz*dz)
            dx *= il; dy *= il; dz *= il

            # Trace ray - iterative with stack
            # Stack: depth, ox, oy, oz, dx, dy, dz
            sp = 0
            stk_ox[0] = cam_x; stk_oy[0] = cam_y; stk_oz[0] = cam_z
            stk_dx[0] = dx; stk_dy[0] = dy; stk_dz[0] = dz
            stk_depth[0] = 0
            stk_refl[0] = 0
            sp = 1

            fin_r = 0; fin_g = 0; fin_b = 0
            # We accumulate: final = sum of (product of refl factors) * local color
            # weight[depth] tracks the multiplied reflection weight at that depth
            weight[0] = 1.0

            while (sp > 0) {
                sp--
                _ox = stk_ox[sp]; _oy = stk_oy[sp]; _oz = stk_oz[sp]
                _dx = stk_dx[sp]; _dy = stk_dy[sp]; _dz = stk_dz[sp]
                _depth = stk_depth[sp]
                _w = weight[sp]

                if (_depth >= MAX_DEPTH) {
                    # Return black for max depth
                    continue
                }

                # Intersect spheres
                best_t = INF; best_si = -1
                for (si = 0; si < NSPH; si++) {
                    ocx = _ox - sph[si,1]; ocy = _oy - sph[si,2]; ocz = _oz - sph[si,3]
                    rad = sph[si,4]
                    b_half = ocx*_dx + ocy*_dy + ocz*_dz
                    c_val = ocx*ocx + ocy*ocy + ocz*ocz - rad*rad
                    disc = b_half*b_half - c_val
                    if (disc > 0) {
                        sq = sqrt(disc)
                        t1 = -b_half - sq
                        if (t1 < EPS) t1 = -b_half + sq
                        if (t1 > EPS && t1 < best_t) {
                            best_t = t1; best_si = si
                        }
                    }
                }

                # Intersect ground y=0
                t_ground = INF
                if (_dy < -EPS || _dy > EPS) {
                    tg = -_oy / _dy
                    if (tg > EPS) t_ground = tg
                }

                if (best_t >= INF && t_ground >= INF) {
                    # Sky
                    t_sky = 0.5 * (_dy + 1.0)
                    fin_r += _w * (1.0 - 0.5 * t_sky)
                    fin_g += _w * (1.0 - 0.3 * t_sky)
                    fin_b += _w * 1.0
                    continue
                }

                hit_ground = (t_ground < best_t) ? 1 : 0

                if (hit_ground) {
                    t = t_ground
                    hx = _ox + _dx * t; hy = 0; hz = _oz + _dz * t
                    nx_n = 0; ny_n = 1; nz_n = 0

                    # Checkerboard - match reference floor behavior
                    # Python: floor(x-1) if x<0 else floor(x)
                    # awk int() truncates toward zero; floor(x) = int(x) if x>=0, int(x)-1 if x<0 and x!=int(x)
                    if (hx < 0) {
                        _tmp = hx - 1.0
                        fx_c = int(_tmp)
                        if (_tmp < 0 && _tmp != int(_tmp)) fx_c = int(_tmp) - 1
                    } else {
                        fx_c = int(hx)
                    }
                    if (hz < 0) {
                        _tmp = hz - 1.0
                        fz_c = int(_tmp)
                        if (_tmp < 0 && _tmp != int(_tmp)) fz_c = int(_tmp) - 1
                    } else {
                        fz_c = int(hz)
                    }

                    chk = (fx_c + fz_c) % 2
                    if (chk < 0) chk = -chk
                    if (chk) {
                        cr = 0.3; cg = 0.3; cb = 0.3
                    } else {
                        cr = 0.8; cg = 0.8; cb = 0.8
                    }
                    h_refl = ground_refl
                    h_spec = ground_spec
                } else {
                    t = best_t
                    si = best_si
                    hx = _ox + _dx * t
                    hy = _oy + _dy * t
                    hz = _oz + _dz * t
                    inv_r = 1.0 / sph[si,4]
                    nx_n = (hx - sph[si,1]) * inv_r
                    ny_n = (hy - sph[si,2]) * inv_r
                    nz_n = (hz - sph[si,3]) * inv_r
                    cr = sph[si,5]; cg = sph[si,6]; cb = sph[si,7]
                    h_refl = sph[si,8]; h_spec = sph[si,9]
                }

                # Lighting
                lr = cr * AMBIENT; lg = cg * AMBIENT; lb = cb * AMBIENT

                for (li = 0; li < NLIGHT; li++) {
                    lx = lt[li,1] - hx; ly = lt[li,2] - hy; lz = lt[li,3] - hz
                    ld = sqrt(lx*lx + ly*ly + lz*lz)
                    inv_ld = 1.0 / ld
                    lx *= inv_ld; ly *= inv_ld; lz *= inv_ld

                    # Shadow: offset point
                    sox = hx + nx_n * EPS; soy = hy + ny_n * EPS; soz = hz + nz_n * EPS

                    # Shadow spheres
                    shadowed = 0
                    for (ssi = 0; ssi < NSPH; ssi++) {
                        ocx = sox - sph[ssi,1]; ocy = soy - sph[ssi,2]; ocz = soz - sph[ssi,3]
                        rad = sph[ssi,4]
                        b_half = ocx*lx + ocy*ly + ocz*lz
                        c_val = ocx*ocx + ocy*ocy + ocz*ocz - rad*rad
                        disc = b_half*b_half - c_val
                        if (disc > 0) {
                            sq = sqrt(disc)
                            t1 = -b_half - sq
                            if (t1 < EPS) t1 = -b_half + sq
                            if (t1 > EPS && t1 < ld) { shadowed = 1; break }
                        }
                    }
                    # Shadow ground
                    if (!shadowed && (ly < -EPS || ly > EPS)) {
                        tg = -soy / ly
                        if (tg > EPS && tg < ld) shadowed = 1
                    }
                    if (shadowed) continue

                    intensity = lt[li,4]
                    ndl = nx_n*lx + ny_n*ly + nz_n*lz

                    if (ndl > 0) {
                        diff = ndl * intensity
                        lr += cr * diff; lg += cg * diff; lb += cb * diff

                        # Specular
                        if (h_spec > 0) {
                            dn2 = 2.0 * ndl
                            rlx = -lx + dn2*nx_n; rly = -ly + dn2*ny_n; rlz = -lz + dn2*nz_n
                            rdv = rlx*(-_dx) + rly*(-_dy) + rlz*(-_dz)
                            if (rdv > 0) {
                                sp_val = (rdv ^ h_spec) * intensity
                                lr += sp_val; lg += sp_val; lb += sp_val
                            }
                        }
                    }
                }

                # Reflection
                if (h_refl > 0 && _depth < MAX_DEPTH - 1) {
                    one_minus = 1.0 - h_refl
                    fin_r += _w * one_minus * lr
                    fin_g += _w * one_minus * lg
                    fin_b += _w * one_minus * lb

                    # Push reflected ray
                    dn2 = 2.0 * (_dx*nx_n + _dy*ny_n + _dz*nz_n)
                    stk_ox[sp] = hx + nx_n*EPS
                    stk_oy[sp] = hy + ny_n*EPS
                    stk_oz[sp] = hz + nz_n*EPS
                    stk_dx[sp] = _dx - dn2*nx_n
                    stk_dy[sp] = _dy - dn2*ny_n
                    stk_dz[sp] = _dz - dn2*nz_n
                    stk_depth[sp] = _depth + 1
                    weight[sp] = _w * h_refl
                    sp++
                } else {
                    fin_r += _w * lr
                    fin_g += _w * lg
                    fin_b += _w * lb
                }
            }

            # Clamp and gamma
            if (fin_r > 1) fin_r = 1; if (fin_r < 0) fin_r = 0
            if (fin_g > 1) fin_g = 1; if (fin_g < 0) fin_g = 0
            if (fin_b > 1) fin_b = 1; if (fin_b < 0) fin_b = 0

            rb = int(exp(log(fin_r) * GAMMA_INV) * 255 + 0.5)
            gb = int(exp(log(fin_g) * GAMMA_INV) * 255 + 0.5)
            bb = int(exp(log(fin_b) * GAMMA_INV) * 255 + 0.5)

            # Handle zero values (log(0) is -inf)
            if (fin_r <= 0) rb = 0
            if (fin_g <= 0) gb = 0
            if (fin_b <= 0) bb = 0
            if (rb > 255) rb = 255
            if (gb > 255) gb = 255
            if (bb > 255) bb = 255

            printf "%c%c%c", rb, gb, bb
        }
    }
}' /dev/null
