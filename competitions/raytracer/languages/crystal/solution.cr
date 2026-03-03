EPSILON = 1e-6
INF     = 1e20
MAX_DEPTH = 5
AMBIENT   = 0.1

struct Vec3
  getter x : Float64
  getter y : Float64
  getter z : Float64

  def initialize(@x : Float64, @y : Float64, @z : Float64)
  end

  def +(o : Vec3) : Vec3
    Vec3.new(@x + o.x, @y + o.y, @z + o.z)
  end

  def -(o : Vec3) : Vec3
    Vec3.new(@x - o.x, @y - o.y, @z - o.z)
  end

  def *(t : Float64) : Vec3
    Vec3.new(@x * t, @y * t, @z * t)
  end

  def mul(o : Vec3) : Vec3
    Vec3.new(@x * o.x, @y * o.y, @z * o.z)
  end

  def dot(o : Vec3) : Float64
    @x * o.x + @y * o.y + @z * o.z
  end

  def cross(o : Vec3) : Vec3
    Vec3.new(@y * o.z - @z * o.y, @z * o.x - @x * o.z, @x * o.y - @y * o.x)
  end

  def length : Float64
    Math.sqrt(dot(self))
  end

  def norm : Vec3
    l = length
    Vec3.new(@x / l, @y / l, @z / l)
  end

  def reflect(n : Vec3) : Vec3
    self - n * (2.0 * dot(n))
  end
end

def clamp01(x : Float64) : Float64
  x < 0.0 ? 0.0 : (x > 1.0 ? 1.0 : x)
end

struct Sphere
  getter center : Vec3
  getter radius : Float64
  getter color : Vec3
  getter reflectivity : Float64
  getter specular : Float64

  def initialize(@center, @radius, @color, @reflectivity, @specular)
  end
end

struct PointLight
  getter position : Vec3
  getter intensity : Float64

  def initialize(@position, @intensity)
  end
end

SPHERES = [
  Sphere.new(Vec3.new(-2.0, 1.0, 0.0), 1.0, Vec3.new(0.9, 0.2, 0.2), 0.3, 50.0),
  Sphere.new(Vec3.new(0.0, 0.75, 0.0), 0.75, Vec3.new(0.2, 0.9, 0.2), 0.2, 30.0),
  Sphere.new(Vec3.new(2.0, 1.0, 0.0), 1.0, Vec3.new(0.2, 0.2, 0.9), 0.4, 80.0),
  Sphere.new(Vec3.new(-0.75, 0.4, -1.5), 0.4, Vec3.new(0.9, 0.9, 0.2), 0.5, 100.0),
  Sphere.new(Vec3.new(1.5, 0.5, -1.0), 0.5, Vec3.new(0.9, 0.2, 0.9), 0.6, 60.0),
]

LIGHTS = [
  PointLight.new(Vec3.new(-3.0, 5.0, -3.0), 0.7),
  PointLight.new(Vec3.new(3.0, 3.0, -1.0), 0.4),
]

GROUND_Y        = 0.0
GROUND_REFLECT  = 0.3
GROUND_SPECULAR = 10.0
CHECK_SIZE      = 1.0

def intersect_sphere(origin : Vec3, dir : Vec3, s : Sphere) : Float64
  oc = origin - s.center
  b = oc.dot(dir)
  c = oc.dot(oc) - s.radius * s.radius
  disc = b * b - c
  return INF if disc < 0.0
  sq = Math.sqrt(disc)
  t1 = -b - sq
  return t1 if t1 > EPSILON
  t2 = -b + sq
  return t2 if t2 > EPSILON
  INF
end

def intersect_ground(origin : Vec3, dir : Vec3) : Float64
  return INF if dir.y.abs < EPSILON
  t = (GROUND_Y - origin.y) / dir.y
  t > EPSILON ? t : INF
end

struct HitInfo
  property hit : Bool
  property t : Float64
  property point : Vec3
  property normal : Vec3
  property color : Vec3
  property reflectivity : Float64
  property specular : Float64

  def initialize
    @hit = false
    @t = INF
    @point = Vec3.new(0.0, 0.0, 0.0)
    @normal = Vec3.new(0.0, 0.0, 0.0)
    @color = Vec3.new(0.0, 0.0, 0.0)
    @reflectivity = 0.0
    @specular = 0.0
  end
end

def scene_intersect(origin : Vec3, dir : Vec3) : HitInfo
  best = HitInfo.new

  SPHERES.each do |s|
    t = intersect_sphere(origin, dir, s)
    if t < best.t
      best.hit = true
      best.t = t
      best.point = origin + dir * t
      best.normal = (best.point - s.center).norm
      best.color = s.color
      best.reflectivity = s.reflectivity
      best.specular = s.specular
    end
  end

  tg = intersect_ground(origin, dir)
  if tg < best.t
    best.hit = true
    best.t = tg
    best.point = origin + dir * tg
    best.normal = Vec3.new(0.0, 1.0, 0.0)
    px = best.point.x / CHECK_SIZE
    pz = best.point.z / CHECK_SIZE
    fx = px < 0.0 ? (px - 1.0).floor : px.floor
    fz = pz < 0.0 ? (pz - 1.0).floor : pz.floor
    check = (fx.to_i &+ fz.to_i) & 1
    if check != 0
      best.color = Vec3.new(0.3, 0.3, 0.3)
    else
      best.color = Vec3.new(0.8, 0.8, 0.8)
    end
    best.reflectivity = GROUND_REFLECT
    best.specular = GROUND_SPECULAR
  end

  best
end

def in_shadow(point : Vec3, light_dir : Vec3, light_dist : Float64) : Bool
  SPHERES.each do |s|
    t = intersect_sphere(point, light_dir, s)
    return true if t < light_dist
  end
  tg = intersect_ground(point, light_dir)
  return true if tg < light_dist
  false
end

def trace(origin : Vec3, dir : Vec3, depth : Int32) : Vec3
  h = scene_intersect(origin, dir)
  unless h.hit
    t = 0.5 * (dir.norm.y + 1.0)
    return Vec3.new(1.0, 1.0, 1.0) * (1.0 - t) + Vec3.new(0.5, 0.7, 1.0) * t
  end

  result = h.color * AMBIENT
  offset_point = h.point + h.normal * EPSILON

  LIGHTS.each do |light|
    to_light = light.position - h.point
    dist = to_light.length
    light_dir = to_light * (1.0 / dist)

    next if in_shadow(offset_point, light_dir, dist)

    n_dot_l = h.normal.dot(light_dir)
    if n_dot_l > 0.0
      result = result + h.color * (n_dot_l * light.intensity)

      refl_dir = (light_dir * -1.0).reflect(h.normal)
      view_dir = dir * -1.0
      spec_dot = view_dir.dot(refl_dir)
      if spec_dot > 0.0
        spec = spec_dot ** h.specular * light.intensity
        result = result + Vec3.new(spec, spec, spec)
      end
    end
  end

  if depth < MAX_DEPTH && h.reflectivity > 0.0
    refl_dir = dir.reflect(h.normal)
    refl_color = trace(offset_point, refl_dir, depth + 1)
    result = result * (1.0 - h.reflectivity) + refl_color * h.reflectivity
  end

  result
end

struct Camera
  getter origin : Vec3
  getter lower_left : Vec3
  getter horizontal : Vec3
  getter vertical : Vec3

  def initialize(from : Vec3, at : Vec3, vup : Vec3, vfov : Float64, aspect : Float64)
    theta = vfov * Math::PI / 180.0
    half_h = Math.tan(theta / 2.0)
    half_w = aspect * half_h

    w = (from - at).norm
    u = vup.cross(w).norm
    v = w.cross(u)

    @origin = from
    @horizontal = u * (2.0 * half_w)
    @vertical = v * (2.0 * half_h)
    @lower_left = from - u * half_w - v * half_h - w
  end

  def ray(s : Float64, t : Float64) : {Vec3, Vec3}
    target = @lower_left + @horizontal * s + @vertical * t
    {@origin, (target - @origin).norm}
  end
end

# ── Main ──

width = ARGV[0].to_i
height = ARGV[1].to_i

if width <= 0 || height <= 0
  STDERR.puts "Invalid dimensions"
  exit 1
end

aspect = width.to_f64 / height.to_f64
cam = Camera.new(
  Vec3.new(0.0, 1.5, -5.0),
  Vec3.new(0.0, 0.5, 0.0),
  Vec3.new(0.0, 1.0, 0.0),
  60.0, aspect
)

inv_gamma = 1.0 / 2.2

buf = Bytes.new(width * height * 3)
idx = 0

(height - 1).downto(0) do |j|
  v = (j.to_f64 + 0.5) / height.to_f64
  0.upto(width - 1) do |i|
    u = (i.to_f64 + 0.5) / width.to_f64
    origin, dir = cam.ray(u, v)
    col = trace(origin, dir, 0)

    r = (clamp01(col.x) ** inv_gamma * 255.0 + 0.5).to_i.clamp(0, 255).to_u8
    g = (clamp01(col.y) ** inv_gamma * 255.0 + 0.5).to_i.clamp(0, 255).to_u8
    b = (clamp01(col.z) ** inv_gamma * 255.0 + 0.5).to_i.clamp(0, 255).to_u8

    buf[idx] = r; idx += 1
    buf[idx] = g; idx += 1
    buf[idx] = b; idx += 1
  end
end

header = "P6\n#{width} #{height}\n255\n"
STDOUT.write(header.to_slice)
STDOUT.write(buf)
STDOUT.flush
