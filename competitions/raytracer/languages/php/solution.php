<?php

/* ── Vector math ──────────────────────────────────────────────── */

function vec3(float $x, float $y, float $z): array {
    return [$x, $y, $z];
}

function vadd(array $a, array $b): array {
    return [$a[0]+$b[0], $a[1]+$b[1], $a[2]+$b[2]];
}

function vsub(array $a, array $b): array {
    return [$a[0]-$b[0], $a[1]-$b[1], $a[2]-$b[2]];
}

function vmul(array $a, float $t): array {
    return [$a[0]*$t, $a[1]*$t, $a[2]*$t];
}

function vmulv(array $a, array $b): array {
    return [$a[0]*$b[0], $a[1]*$b[1], $a[2]*$b[2]];
}

function vdot(array $a, array $b): float {
    return $a[0]*$b[0] + $a[1]*$b[1] + $a[2]*$b[2];
}

function vcross(array $a, array $b): array {
    return [
        $a[1]*$b[2] - $a[2]*$b[1],
        $a[2]*$b[0] - $a[0]*$b[2],
        $a[0]*$b[1] - $a[1]*$b[0],
    ];
}

function vlen(array $v): float {
    return sqrt(vdot($v, $v));
}

function vnorm(array $v): array {
    $l = vlen($v);
    return [$v[0]/$l, $v[1]/$l, $v[2]/$l];
}

function vreflect(array $v, array $n): array {
    $d = 2.0 * vdot($v, $n);
    return [$v[0] - $n[0]*$d, $v[1] - $n[1]*$d, $v[2] - $n[2]*$d];
}

function clamp01(float $x): float {
    return $x < 0.0 ? 0.0 : ($x > 1.0 ? 1.0 : $x);
}

/* ── Scene definition ─────────────────────────────────────────── */

$SPHERES = [
    ['center' => [-2.0, 1.0, 0.0],    'radius' => 1.0,  'color' => [0.9, 0.2, 0.2], 'refl' => 0.3, 'spec' => 50.0],
    ['center' => [0.0, 0.75, 0.0],    'radius' => 0.75, 'color' => [0.2, 0.9, 0.2], 'refl' => 0.2, 'spec' => 30.0],
    ['center' => [2.0, 1.0, 0.0],     'radius' => 1.0,  'color' => [0.2, 0.2, 0.9], 'refl' => 0.4, 'spec' => 80.0],
    ['center' => [-0.75, 0.4, -1.5],  'radius' => 0.4,  'color' => [0.9, 0.9, 0.2], 'refl' => 0.5, 'spec' => 100.0],
    ['center' => [1.5, 0.5, -1.0],    'radius' => 0.5,  'color' => [0.9, 0.2, 0.9], 'refl' => 0.6, 'spec' => 60.0],
];

$LIGHTS = [
    ['pos' => [-3.0, 5.0, -3.0], 'intensity' => 0.7],
    ['pos' => [3.0, 3.0, -1.0],  'intensity' => 0.4],
];

define('AMBIENT', 0.1);
define('GROUND_Y', 0.0);
define('GROUND_REFLECT', 0.3);
define('GROUND_SPECULAR', 10.0);
define('CHECK_SIZE', 1.0);
define('MAX_DEPTH', 5);
define('EPSILON', 1e-6);
define('MY_INF', 1e20);

/* ── Intersection routines ────────────────────────────────────── */

function intersect_sphere(array $ro, array $rd, array $sphere): float {
    $oc = vsub($ro, $sphere['center']);
    $b = vdot($oc, $rd);
    $c = vdot($oc, $oc) - $sphere['radius'] * $sphere['radius'];
    $disc = $b * $b - $c;
    if ($disc < 0.0) return MY_INF;
    $sq = sqrt($disc);
    $t1 = -$b - $sq;
    if ($t1 > EPSILON) return $t1;
    $t2 = -$b + $sq;
    if ($t2 > EPSILON) return $t2;
    return MY_INF;
}

function intersect_ground(array $ro, array $rd): float {
    if (abs($rd[1]) < EPSILON) return MY_INF;
    $t = (GROUND_Y - $ro[1]) / $rd[1];
    return $t > EPSILON ? $t : MY_INF;
}

/* ── Scene intersection ───────────────────────────────────────── */

function scene_intersect(array $ro, array $rd): ?array {
    global $SPHERES;

    $best_t = MY_INF;
    $hit = null;

    /* spheres */
    for ($i = 0; $i < 5; $i++) {
        $t = intersect_sphere($ro, $rd, $SPHERES[$i]);
        if ($t < $best_t) {
            $best_t = $t;
            $point = vadd($ro, vmul($rd, $t));
            $normal = vnorm(vsub($point, $SPHERES[$i]['center']));
            $hit = [
                't' => $t,
                'point' => $point,
                'normal' => $normal,
                'color' => $SPHERES[$i]['color'],
                'refl' => $SPHERES[$i]['refl'],
                'spec' => $SPHERES[$i]['spec'],
            ];
        }
    }

    /* ground plane */
    $tg = intersect_ground($ro, $rd);
    if ($tg < $best_t) {
        $best_t = $tg;
        $point = vadd($ro, vmul($rd, $tg));
        $px = $point[0] / CHECK_SIZE;
        $pz = $point[2] / CHECK_SIZE;
        $fx = $px < 0.0 ? floor($px - 1.0) : floor($px);
        $fz = $pz < 0.0 ? floor($pz - 1.0) : floor($pz);
        $check = (intval($fx) + intval($fz)) & 1;
        $color = $check ? [0.3, 0.3, 0.3] : [0.8, 0.8, 0.8];
        $hit = [
            't' => $tg,
            'point' => $point,
            'normal' => [0.0, 1.0, 0.0],
            'color' => $color,
            'refl' => GROUND_REFLECT,
            'spec' => GROUND_SPECULAR,
        ];
    }

    return $hit;
}

/* ── Shadow check ─────────────────────────────────────────────── */

function in_shadow(array $point, array $light_dir, float $light_dist): bool {
    global $SPHERES;

    for ($i = 0; $i < 5; $i++) {
        $t = intersect_sphere($point, $light_dir, $SPHERES[$i]);
        if ($t < $light_dist) return true;
    }
    $tg = intersect_ground($point, $light_dir);
    if ($tg < $light_dist) return true;
    return false;
}

/* ── Trace ────────────────────────────────────────────────────── */

function trace(array $ro, array $rd, int $depth): array {
    global $LIGHTS;

    $hit = scene_intersect($ro, $rd);

    if ($hit === null) {
        /* sky gradient */
        $nd = vnorm($rd);
        $t = 0.5 * ($nd[1] + 1.0);
        return vadd(vmul([1.0, 1.0, 1.0], 1.0 - $t), vmul([0.5, 0.7, 1.0], $t));
    }

    /* Phong shading */
    $result = vmul($hit['color'], AMBIENT);
    $offset_point = vadd($hit['point'], vmul($hit['normal'], EPSILON));

    for ($i = 0; $i < 2; $i++) {
        $to_light = vsub($LIGHTS[$i]['pos'], $hit['point']);
        $dist = vlen($to_light);
        $light_dir = vmul($to_light, 1.0 / $dist);

        if (in_shadow($offset_point, $light_dir, $dist)) {
            continue;
        }

        $n_dot_l = vdot($hit['normal'], $light_dir);
        if ($n_dot_l > 0.0) {
            /* diffuse */
            $result = vadd($result, vmul($hit['color'], $n_dot_l * $LIGHTS[$i]['intensity']));

            /* specular (Phong) – white, only when surface faces light */
            $refl_dir = vreflect(vmul($light_dir, -1.0), $hit['normal']);
            $view_dir = vmul($rd, -1.0);
            $spec_dot = vdot($view_dir, $refl_dir);
            if ($spec_dot > 0.0) {
                $spec = pow($spec_dot, $hit['spec']) * $LIGHTS[$i]['intensity'];
                $result = vadd($result, [$spec, $spec, $spec]);
            }
        }
    }

    /* reflections */
    if ($depth < MAX_DEPTH && $hit['refl'] > 0.0) {
        $refl_rd = vreflect($rd, $hit['normal']);
        $refl_color = trace($offset_point, $refl_rd, $depth + 1);
        $result = vadd(vmul($result, 1.0 - $hit['refl']), vmul($refl_color, $hit['refl']));
    }

    return $result;
}

/* ── Camera ───────────────────────────────────────────────────── */

function make_camera(array $from, array $at, array $vup, float $vfov, float $aspect): array {
    $theta = $vfov * M_PI / 180.0;
    $half_h = tan($theta / 2.0);
    $half_w = $aspect * $half_h;

    $w = vnorm(vsub($from, $at));
    $u = vnorm(vcross($vup, $w));
    $v = vcross($w, $u);

    $horizontal = vmul($u, 2.0 * $half_w);
    $vertical = vmul($v, 2.0 * $half_h);
    $lower_left = vsub(vsub(vsub($from, vmul($u, $half_w)), vmul($v, $half_h)), $w);

    return [
        'origin' => $from,
        'lower_left' => $lower_left,
        'horizontal' => $horizontal,
        'vertical' => $vertical,
    ];
}

function cam_ray(array $cam, float $s, float $t): array {
    $target = vadd(vadd($cam['lower_left'], vmul($cam['horizontal'], $s)), vmul($cam['vertical'], $t));
    $dir = vnorm(vsub($target, $cam['origin']));
    return ['origin' => $cam['origin'], 'dir' => $dir];
}

/* ── Main ─────────────────────────────────────────────────────── */

if ($argc < 3) {
    fwrite(STDERR, "Usage: php solution.php WIDTH HEIGHT\n");
    exit(1);
}

$width = intval($argv[1]);
$height = intval($argv[2]);
if ($width <= 0 || $height <= 0) {
    fwrite(STDERR, "Invalid dimensions\n");
    exit(1);
}

$aspect = (float)$width / (float)$height;
$cam = make_camera([0.0, 1.5, -5.0], [0.0, 0.5, 0.0], [0.0, 1.0, 0.0], 60.0, $aspect);

$inv_gamma = 1.0 / 2.2;

/* allocate pixel buffer */
$buf = '';

/* render */
for ($j = $height - 1; $j >= 0; $j--) {
    $v = ((float)$j + 0.5) / (float)$height;
    for ($i = 0; $i < $width; $i++) {
        $u = ((float)$i + 0.5) / (float)$width;
        $ray = cam_ray($cam, $u, $v);
        $col = trace($ray['origin'], $ray['dir'], 0);

        /* gamma correction */
        $cr = pow(clamp01($col[0]), $inv_gamma);
        $cg = pow(clamp01($col[1]), $inv_gamma);
        $cb = pow(clamp01($col[2]), $inv_gamma);

        $buf .= chr((int)($cr * 255.0 + 0.5));
        $buf .= chr((int)($cg * 255.0 + 0.5));
        $buf .= chr((int)($cb * 255.0 + 0.5));
    }
}

/* write PPM P6 */
$stdout = fopen('php://stdout', 'wb');
fwrite($stdout, "P6\n{$width} {$height}\n255\n");
fwrite($stdout, $buf);
fclose($stdout);
