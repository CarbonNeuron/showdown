$stdout.binmode

width = ARGV[0].to_i
height = ARGV[1].to_i

INF = 1e18
MAX_DEPTH = 5
AMBIENT = 0.1
EPSILON = 1e-6

# Vector class
class Vec
  attr_accessor :x, :y, :z
  def initialize(x=0.0, y=0.0, z=0.0)
    @x = x.to_f; @y = y.to_f; @z = z.to_f
  end
  def +(o) Vec.new(@x+o.x, @y+o.y, @z+o.z) end
  def -(o) Vec.new(@x-o.x, @y-o.y, @z-o.z) end
  def *(s)
    if s.is_a?(Vec)
      Vec.new(@x*s.x, @y*s.y, @z*s.z)
    else
      Vec.new(@x*s, @y*s, @z*s)
    end
  end
  def dot(o) @x*o.x + @y*o.y + @z*o.z end
  def cross(o) Vec.new(@y*o.z - @z*o.y, @z*o.x - @x*o.z, @x*o.y - @y*o.x) end
  def length() Math.sqrt(@x*@x + @y*@y + @z*@z) end
  def norm() l = length; l > 0 ? Vec.new(@x/l, @y/l, @z/l) : Vec.new end
  def clamp() Vec.new([[0,@x].max,1].min, [[0,@y].max,1].min, [[0,@z].max,1].min) end
end

Sphere = Struct.new(:center, :radius, :color, :refl, :spec_exp)
Light = Struct.new(:pos, :intensity)

spheres = [
  Sphere.new(Vec.new(-2,1,0), 1.0, Vec.new(0.9,0.2,0.2), 0.3, 50),
  Sphere.new(Vec.new(0,0.75,0), 0.75, Vec.new(0.2,0.9,0.2), 0.2, 30),
  Sphere.new(Vec.new(2,1,0), 1.0, Vec.new(0.2,0.2,0.9), 0.4, 80),
  Sphere.new(Vec.new(-0.75,0.4,-1.5), 0.4, Vec.new(0.9,0.9,0.2), 0.5, 100),
  Sphere.new(Vec.new(1.5,0.5,-1), 0.5, Vec.new(0.9,0.2,0.9), 0.6, 60),
]

lights = [
  Light.new(Vec.new(-3,5,-3), 0.7),
  Light.new(Vec.new(3,3,-1), 0.4),
]

# Ground plane y=0
GROUND_REFL = 0.3
GROUND_SPEC = 10

cam_pos = Vec.new(0, 1.5, -5)
look_at = Vec.new(0, 0.5, 0)
up = Vec.new(0, 1, 0)
fov = 60.0

forward = (look_at - cam_pos).norm
right = forward.cross(up).norm
cam_up = right.cross(forward).norm

aspect = width.to_f / height
half_fov = Math.tan(fov * Math::PI / 360.0)

def reflect_vec(v, n)
  v - n * (2.0 * v.dot(n))
end

def intersect_sphere(orig, dir, sph)
  oc = orig - sph.center
  a = dir.dot(dir)
  b = 2.0 * oc.dot(dir)
  c = oc.dot(oc) - sph.radius * sph.radius
  disc = b * b - 4.0 * a * c
  return INF if disc < 0
  sq = Math.sqrt(disc)
  t1 = (-b - sq) / (2.0 * a)
  return t1 if t1 > EPSILON
  t2 = (-b + sq) / (2.0 * a)
  return t2 if t2 > EPSILON
  INF
end

def intersect_ground(orig, dir)
  return INF if dir.y.abs < EPSILON
  t = -orig.y / dir.y
  t > EPSILON ? t : INF
end

def sky_color(dir)
  t = 0.5 * (dir.y + 1.0)
  Vec.new(1,1,1) * (1.0 - t) + Vec.new(0.5, 0.7, 1.0) * t
end

def checkerboard_color(x, z)
  fx = x < 0 ? (x - 1).floor : x.floor
  fz = z < 0 ? (z - 1).floor : z.floor
  if (fx.to_i + fz.to_i) & 1 == 0
    Vec.new(0.8, 0.8, 0.8)
  else
    Vec.new(0.3, 0.3, 0.3)
  end
end

def trace(orig, dir, depth, spheres, lights)
  return sky_color(dir) if depth > MAX_DEPTH

  min_t = INF
  hit_sphere = nil
  hit_ground = false

  spheres.each do |sph|
    t = intersect_sphere(orig, dir, sph)
    if t < min_t
      min_t = t
      hit_sphere = sph
      hit_ground = false
    end
  end

  gt = intersect_ground(orig, dir)
  if gt < min_t
    min_t = gt
    hit_sphere = nil
    hit_ground = true
  end

  return sky_color(dir) if min_t >= INF

  hit_point = orig + dir * min_t

  if hit_ground
    normal = Vec.new(0, 1, 0)
    color = checkerboard_color(hit_point.x, hit_point.z)
    refl = GROUND_REFL
    spec_exp = GROUND_SPEC
  else
    normal = (hit_point - hit_sphere.center).norm
    color = hit_sphere.color
    refl = hit_sphere.refl
    spec_exp = hit_sphere.spec_exp
  end

  # Phong shading
  local = color * AMBIENT

  lights.each do |light|
    light_dir = (light.pos - hit_point).norm
    n_dot_l = normal.dot(light_dir)
    next if n_dot_l <= 0

    # Shadow check
    shadow_orig = hit_point + normal * EPSILON
    in_shadow = false

    light_dist = (light.pos - hit_point).length

    spheres.each do |sph|
      st = intersect_sphere(shadow_orig, light_dir, sph)
      if st < light_dist
        in_shadow = true
        break
      end
    end

    unless in_shadow
      sgt = intersect_ground(shadow_orig, light_dir)
      in_shadow = true if sgt < light_dist
    end

    next if in_shadow

    # Diffuse
    diffuse = color * (n_dot_l * light.intensity)
    local = local + diffuse

    # Specular (white)
    reflect_dir = reflect_vec(light_dir * -1.0, normal)
    r_dot_v = [0.0, dir.dot(reflect_dir) * -1.0].max
    if r_dot_v > 0
      spec_val = (r_dot_v ** spec_exp) * light.intensity
      local = local + Vec.new(spec_val, spec_val, spec_val)
    end
  end

  if refl > 0 && depth < MAX_DEPTH
    reflect_dir = reflect_vec(dir, normal)
    reflect_orig = hit_point + normal * EPSILON
    reflected = trace(reflect_orig, reflect_dir, depth + 1, spheres, lights)
    final = local * (1.0 - refl) + reflected * refl
  else
    final = local
  end

  final
end

# Render
header = "P6\n#{width} #{height}\n255\n"
$stdout.write(header)

pixels = String.new(capacity: width * 3)

height.times do |j|
  pixels.clear
  width.times do |i|
    px = (2.0 * (i + 0.5) / width - 1.0) * aspect * half_fov
    py = (1.0 - 2.0 * (j + 0.5) / height) * half_fov
    ray_dir = (forward + right * px + cam_up * py).norm
    col = trace(cam_pos, ray_dir, 0, spheres, lights)
    c = col.clamp
    r = ((c.x ** (1.0/2.2)) * 255 + 0.5).to_i
    g = ((c.y ** (1.0/2.2)) * 255 + 0.5).to_i
    b = ((c.z ** (1.0/2.2)) * 255 + 0.5).to_i
    pixels << r.chr << g.chr << b.chr
  end
  $stdout.write(pixels)
end
