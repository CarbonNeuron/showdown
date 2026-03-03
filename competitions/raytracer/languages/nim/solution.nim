import std/[math, os, strutils]

type
  Vec3 = object
    x, y, z: float64

  Ray = object
    origin, dir: Vec3

  Material = object
    color: Vec3
    reflectivity: float64
    specExp: float64

  Sphere = object
    center: Vec3
    radius: float64
    mat: Material

  Light = object
    pos: Vec3
    intensity: float64

  HitRecord = object
    t: float64
    point, normal: Vec3
    mat: Material
    hit: bool

proc vec3(x, y, z: float64): Vec3 =
  Vec3(x: x, y: y, z: z)

proc `+`(a, b: Vec3): Vec3 =
  vec3(a.x + b.x, a.y + b.y, a.z + b.z)

proc `-`(a, b: Vec3): Vec3 =
  vec3(a.x - b.x, a.y - b.y, a.z - b.z)

proc `*`(a: Vec3, s: float64): Vec3 =
  vec3(a.x * s, a.y * s, a.z * s)

proc `*`(a, b: Vec3): Vec3 =
  vec3(a.x * b.x, a.y * b.y, a.z * b.z)

proc dot(a, b: Vec3): float64 =
  a.x * b.x + a.y * b.y + a.z * b.z

proc cross(a, b: Vec3): Vec3 =
  vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)

proc length(a: Vec3): float64 =
  sqrt(dot(a, a))

proc norm(a: Vec3): Vec3 =
  let l = length(a)
  if l > 0.0: a * (1.0 / l) else: a

proc neg(a: Vec3): Vec3 =
  vec3(-a.x, -a.y, -a.z)

proc clamp01(v: float64): float64 =
  if v < 0.0: 0.0 elif v > 1.0: 1.0 else: v

proc reflect(v, n: Vec3): Vec3 =
  v - n * (2.0 * dot(v, n))

# Scene
let spheres = [
  Sphere(center: vec3(-2.0, 1.0, 0.0), radius: 1.0,
         mat: Material(color: vec3(0.9, 0.2, 0.2), reflectivity: 0.3, specExp: 50.0)),
  Sphere(center: vec3(0.0, 0.75, 0.0), radius: 0.75,
         mat: Material(color: vec3(0.2, 0.9, 0.2), reflectivity: 0.2, specExp: 30.0)),
  Sphere(center: vec3(2.0, 1.0, 0.0), radius: 1.0,
         mat: Material(color: vec3(0.2, 0.2, 0.9), reflectivity: 0.4, specExp: 80.0)),
  Sphere(center: vec3(-0.75, 0.4, -1.5), radius: 0.4,
         mat: Material(color: vec3(0.9, 0.9, 0.2), reflectivity: 0.5, specExp: 100.0)),
  Sphere(center: vec3(1.5, 0.5, -1.0), radius: 0.5,
         mat: Material(color: vec3(0.9, 0.2, 0.9), reflectivity: 0.6, specExp: 60.0))
]

let lights = [
  Light(pos: vec3(-3.0, 5.0, -3.0), intensity: 0.7),
  Light(pos: vec3(3.0, 3.0, -1.0), intensity: 0.4)
]

const ambient = 0.1

proc intersectSphere(ray: Ray, s: Sphere, tMin, tMax: float64, rec: var HitRecord): bool =
  let oc = ray.origin - s.center
  let a = dot(ray.dir, ray.dir)
  let b = dot(oc, ray.dir)
  let c = dot(oc, oc) - s.radius * s.radius
  let disc = b * b - a * c
  if disc < 0.0:
    return false
  let sqrtDisc = sqrt(disc)
  var t = (-b - sqrtDisc) / a
  if t < tMin or t > tMax:
    t = (-b + sqrtDisc) / a
    if t < tMin or t > tMax:
      return false
  rec.t = t
  rec.point = ray.origin + ray.dir * t
  rec.normal = norm(rec.point - s.center)
  rec.mat = s.mat
  rec.hit = true
  return true

proc intersectGround(ray: Ray, tMin, tMax: float64, rec: var HitRecord): bool =
  # Ground plane at y=0
  if abs(ray.dir.y) < 1e-8:
    return false
  let t = -ray.origin.y / ray.dir.y
  if t < tMin or t > tMax:
    return false
  let p = ray.origin + ray.dir * t
  rec.t = t
  rec.point = p
  rec.normal = vec3(0.0, 1.0, 0.0)
  # Checkerboard
  let fx = if p.x < 0.0: floor(p.x) - 1.0 else: floor(p.x)
  let fz = if p.z < 0.0: floor(p.z) - 1.0 else: floor(p.z)
  let check = (int(fx) + int(fz)) and 1
  if check == 0:
    rec.mat = Material(color: vec3(0.8, 0.8, 0.8), reflectivity: 0.3, specExp: 10.0)
  else:
    rec.mat = Material(color: vec3(0.3, 0.3, 0.3), reflectivity: 0.3, specExp: 10.0)
  rec.hit = true
  return true

proc sceneIntersect(ray: Ray, tMin, tMax: float64, rec: var HitRecord): bool =
  var closest = tMax
  var tempRec: HitRecord
  result = false
  for s in spheres:
    if intersectSphere(ray, s, tMin, closest, tempRec):
      closest = tempRec.t
      rec = tempRec
      result = true
  if intersectGround(ray, tMin, closest, tempRec):
    closest = tempRec.t
    rec = tempRec
    result = true

proc sky(dir: Vec3): Vec3 =
  let t = 0.5 * (dir.y + 1.0)
  vec3(1.0, 1.0, 1.0) * (1.0 - t) + vec3(0.5, 0.7, 1.0) * t

proc trace(ray: Ray, depth: int): Vec3 =
  if depth <= 0:
    return vec3(0.0, 0.0, 0.0)

  var rec: HitRecord
  if not sceneIntersect(ray, 0.001, 1e20, rec):
    return sky(ray.dir)

  # Ambient
  var localColor = rec.mat.color * ambient

  # Lighting
  for light in lights:
    let toLight = light.pos - rec.point
    let lightDist = length(toLight)
    let lightDir = norm(toLight)
    let nDotL = dot(rec.normal, lightDir)

    # Shadow ray - check both spheres and ground
    let shadowRay = Ray(origin: rec.point + rec.normal * 0.001, dir: lightDir)
    var shadowRec: HitRecord
    let inShadow = sceneIntersect(shadowRay, 0.001, lightDist, shadowRec)

    if not inShadow:
      # Diffuse
      if nDotL > 0.0:
        localColor = localColor + rec.mat.color * (nDotL * light.intensity)
        # Specular (Phong)
        let reflectedLight = reflect(neg(lightDir), rec.normal)
        let specAngle = max(0.0, dot(neg(ray.dir), reflectedLight))
        let spec = pow(specAngle, rec.mat.specExp) * light.intensity
        localColor = localColor + vec3(1.0, 1.0, 1.0) * spec

  # Reflection
  let refl = rec.mat.reflectivity
  if refl > 0.0 and depth > 1:
    let reflDir = reflect(ray.dir, rec.normal)
    let reflRay = Ray(origin: rec.point + rec.normal * 0.001, dir: norm(reflDir))
    let reflColor = trace(reflRay, depth - 1)
    return localColor * (1.0 - refl) + reflColor * refl
  else:
    return localColor

proc main() =
  let params = commandLineParams()
  if params.len < 2:
    quit("Usage: solution WIDTH HEIGHT")
  let width = parseInt(params[0])
  let height = parseInt(params[1])

  # Camera
  let camPos = vec3(0.0, 1.5, -5.0)
  let lookAt = vec3(0.0, 0.5, 0.0)
  let up = vec3(0.0, 1.0, 0.0)

  let forward = norm(lookAt - camPos)
  let right = norm(cross(forward, up))
  let camUp = cross(right, forward)

  let fovRad = 60.0 * PI / 180.0
  let halfH = tan(fovRad / 2.0)
  let aspect = float64(width) / float64(height)
  let halfW = aspect * halfH

  # PPM header
  let header = "P6\n" & $width & " " & $height & "\n255\n"
  stdout.write(header)

  # Allocate buffer for one row
  var rowBuf = newSeq[uint8](width * 3)

  for j in 0 ..< height:
    for i in 0 ..< width:
      let u = (2.0 * ((float64(i) + 0.5) / float64(width)) - 1.0) * halfW
      let v = (1.0 - 2.0 * ((float64(j) + 0.5) / float64(height))) * halfH
      let dir = norm(forward + right * u + camUp * v)
      let ray = Ray(origin: camPos, dir: dir)
      let color = trace(ray, 5)

      # Gamma correction and output
      let r = pow(clamp01(color.x), 1.0 / 2.2)
      let g = pow(clamp01(color.y), 1.0 / 2.2)
      let b = pow(clamp01(color.z), 1.0 / 2.2)
      let idx = i * 3
      rowBuf[idx] = uint8(r * 255.0 + 0.5)
      rowBuf[idx + 1] = uint8(g * 255.0 + 0.5)
      rowBuf[idx + 2] = uint8(b * 255.0 + 0.5)

    let written = stdout.writeBuffer(addr rowBuf[0], width * 3)
    if written != width * 3:
      quit("Failed to write row")

  flushFile(stdout)

main()
