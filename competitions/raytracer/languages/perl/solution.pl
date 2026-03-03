use strict;
use warnings;
use POSIX qw(floor tan);

my $WIDTH  = $ARGV[0] || 800;
my $HEIGHT = $ARGV[1] || 600;

# --- Vector ops ---
sub vadd { [$_[0][0]+$_[1][0], $_[0][1]+$_[1][1], $_[0][2]+$_[1][2]] }
sub vsub { [$_[0][0]-$_[1][0], $_[0][1]-$_[1][1], $_[0][2]-$_[1][2]] }
sub vmul { [$_[0][0]*$_[1], $_[0][1]*$_[1], $_[0][2]*$_[1]] }
sub vdot { $_[0][0]*$_[1][0] + $_[0][1]*$_[1][1] + $_[0][2]*$_[1][2] }
sub vlen { sqrt(vdot($_[0],$_[0])) }
sub vnorm { my $l=vlen($_[0]); $l>0 ? vmul($_[0],1/$l) : [0,0,0] }
sub vcross { [$_[0][1]*$_[1][2]-$_[0][2]*$_[1][1], $_[0][2]*$_[1][0]-$_[0][0]*$_[1][2], $_[0][0]*$_[1][1]-$_[0][1]*$_[1][0]] }
sub vmulv { [$_[0][0]*$_[1][0], $_[0][1]*$_[1][1], $_[0][2]*$_[1][2]] }

# --- Scene ---
my $cam_pos = [0, 1.5, -5];
my $look_at = [0, 0.5, 0];
my $up      = [0, 1, 0];
my $fov     = 60;

my @spheres = (
    { center => [-2, 1, 0],       radius => 1,    color => [0.9, 0.2, 0.2], refl => 0.3, spec => 50  },
    { center => [0, 0.75, 0],     radius => 0.75, color => [0.2, 0.9, 0.2], refl => 0.2, spec => 30  },
    { center => [2, 1, 0],        radius => 1,    color => [0.2, 0.2, 0.9], refl => 0.4, spec => 80  },
    { center => [-0.75, 0.4, -1.5], radius => 0.4, color => [0.9, 0.9, 0.2], refl => 0.5, spec => 100 },
    { center => [1.5, 0.5, -1],   radius => 0.5,  color => [0.9, 0.2, 0.9], refl => 0.6, spec => 60  },
);

my @lights = (
    { pos => [-3, 5, -3], intensity => 0.7 },
    { pos => [3, 3, -1],  intensity => 0.4 },
);

my $ambient = 0.1;
my $max_depth = 5;

# Ground: y=0, checkerboard, refl=0.3, spec=10
my $ground_refl = 0.3;
my $ground_spec = 10;

# --- Camera setup ---
my $forward = vnorm(vsub($look_at, $cam_pos));
my $right   = vnorm(vcross($forward, $up));
my $cam_up  = vcross($right, $forward);

my $aspect = $WIDTH / $HEIGHT;
my $half_h = tan($fov * 3.14159265358979323846 / 360.0);
my $half_w = $half_h * $aspect;

# --- Intersection: sphere ---
sub intersect_sphere {
    my ($orig, $dir, $sp) = @_;
    my $oc = vsub($orig, $sp->{center});
    my $a  = vdot($dir, $dir);
    my $b  = 2.0 * vdot($oc, $dir);
    my $c  = vdot($oc, $oc) - $sp->{radius} * $sp->{radius};
    my $disc = $b*$b - 4*$a*$c;
    return -1 if $disc < 0;
    my $sq = sqrt($disc);
    my $t0 = (-$b - $sq) / (2*$a);
    return $t0 if $t0 > 1e-4;
    my $t1 = (-$b + $sq) / (2*$a);
    return $t1 if $t1 > 1e-4;
    return -1;
}

# --- Intersection: ground plane y=0 ---
sub intersect_ground {
    my ($orig, $dir) = @_;
    return -1 if abs($dir->[1]) < 1e-8;
    my $t = -$orig->[1] / $dir->[1];
    return ($t > 1e-4) ? $t : -1;
}

# --- Checkerboard color ---
sub checker_color {
    my ($x, $z) = @_;
    my $fx = $x < 0 ? floor($x - 1) : floor($x);
    my $fz = $z < 0 ? floor($z - 1) : floor($z);
    my $check = (int($fx) + int($fz)) % 2;
    $check += 2 if $check < 0;
    $check %= 2;
    return $check == 0 ? [0.8, 0.8, 0.8] : [0.3, 0.3, 0.3];
}

# --- Shadow test ---
sub in_shadow {
    my ($point, $light_pos) = @_;
    my $to_light = vsub($light_pos, $point);
    my $dist     = vlen($to_light);
    my $dir      = vnorm($to_light);

    # Check spheres
    for my $sp (@spheres) {
        my $t = intersect_sphere($point, $dir, $sp);
        return 1 if $t > 1e-4 && $t < $dist;
    }

    # Check ground
    my $t = intersect_ground($point, $dir);
    return 1 if $t > 1e-4 && $t < $dist;

    return 0;
}

# --- Trace ray ---
sub trace {
    my ($orig, $dir, $depth) = @_;

    return sky_color($dir) if $depth > $max_depth;

    my $closest_t = 1e30;
    my $hit_type  = 0; # 0=none, 1=sphere, 2=ground
    my $hit_sphere;

    # Test spheres
    for my $sp (@spheres) {
        my $t = intersect_sphere($orig, $dir, $sp);
        if ($t > 1e-4 && $t < $closest_t) {
            $closest_t  = $t;
            $hit_type   = 1;
            $hit_sphere = $sp;
        }
    }

    # Test ground
    my $tg = intersect_ground($orig, $dir);
    if ($tg > 1e-4 && $tg < $closest_t) {
        $closest_t = $tg;
        $hit_type  = 2;
    }

    return sky_color($dir) if $hit_type == 0;

    my $hit_point = vadd($orig, vmul($dir, $closest_t));
    my ($normal, $obj_color, $refl, $spec_power);

    if ($hit_type == 1) {
        $normal     = vnorm(vsub($hit_point, $hit_sphere->{center}));
        $obj_color  = $hit_sphere->{color};
        $refl       = $hit_sphere->{refl};
        $spec_power = $hit_sphere->{spec};
    } else {
        $normal     = [0, 1, 0];
        $obj_color  = checker_color($hit_point->[0], $hit_point->[2]);
        $refl       = $ground_refl;
        $spec_power = $ground_spec;
    }

    # Phong shading
    my $local = vmul($obj_color, $ambient);

    my $view_dir = vnorm(vmul($dir, -1));

    for my $light (@lights) {
        my $offset = vadd($hit_point, vmul($normal, 1e-4));
        next if in_shadow($offset, $light->{pos});

        my $l_dir = vnorm(vsub($light->{pos}, $hit_point));
        my $n_dot_l = vdot($normal, $l_dir);
        next if $n_dot_l <= 0;

        # Diffuse
        my $diff = vmul($obj_color, $n_dot_l * $light->{intensity});
        $local = vadd($local, $diff);

        # Specular (white)
        my $reflect_l = vsub(vmul($normal, 2.0 * $n_dot_l), $l_dir);
        my $r_dot_v = vdot($reflect_l, $view_dir);
        if ($r_dot_v > 0) {
            my $sp = ($r_dot_v ** $spec_power) * $light->{intensity};
            $local = vadd($local, [$sp, $sp, $sp]);
        }
    }

    # Reflection
    if ($refl > 0 && $depth < $max_depth) {
        my $d_dot_n = vdot($dir, $normal);
        my $refl_dir = vsub($dir, vmul($normal, 2.0 * $d_dot_n));
        my $refl_orig = vadd($hit_point, vmul($normal, 1e-4));
        my $refl_color = trace($refl_orig, $refl_dir, $depth + 1);
        $local = vadd(vmul($local, 1.0 - $refl), vmul($refl_color, $refl));
    }

    return $local;
}

# --- Sky gradient ---
sub sky_color {
    my ($dir) = @_;
    my $d = vnorm($dir);
    my $t = 0.5 * ($d->[1] + 1.0);
    my $white = [1, 1, 1];
    my $blue  = [0.5, 0.7, 1.0];
    return vadd(vmul($white, 1.0 - $t), vmul($blue, $t));
}

# --- Clamp ---
sub clamp {
    my ($v, $lo, $hi) = @_;
    return $v < $lo ? $lo : ($v > $hi ? $hi : $v);
}

# --- Render ---
my $gamma_inv = 1.0 / 2.2;
my $buffer = '';

for my $j (0 .. $HEIGHT - 1) {
    for my $i (0 .. $WIDTH - 1) {
        my $u = (2.0 * ($i + 0.5) / $WIDTH - 1.0) * $half_w;
        my $v = (1.0 - 2.0 * ($j + 0.5) / $HEIGHT) * $half_h;

        my $dir = vnorm(vadd(vadd(vmul($right, $u), vmul($cam_up, $v)), $forward));
        my $color = trace($cam_pos, $dir, 0);

        my $r = int(clamp($color->[0], 0, 1) ** $gamma_inv * 255 + 0.5);
        my $g = int(clamp($color->[1], 0, 1) ** $gamma_inv * 255 + 0.5);
        my $b = int(clamp($color->[2], 0, 1) ** $gamma_inv * 255 + 0.5);

        $buffer .= pack("CCC", $r, $g, $b);
    }
}

# --- Output PPM P6 ---
binmode STDOUT;
print "P6\n$WIDTH $HEIGHT\n255\n";
print $buffer;
