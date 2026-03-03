import java.io.BufferedOutputStream

object solution {

  // ── Vector math ──────────────────────────────────────────────────
  final case class Vec3(x: Double, y: Double, z: Double) {
    @inline def +(o: Vec3): Vec3 = Vec3(x + o.x, y + o.y, z + o.z)
    @inline def -(o: Vec3): Vec3 = Vec3(x - o.x, y - o.y, z - o.z)
    @inline def *(s: Double): Vec3 = Vec3(x * s, y * s, z * s)
    @inline def *(o: Vec3): Vec3 = Vec3(x * o.x, y * o.y, z * o.z)
    @inline infix def dot(o: Vec3): Double = x * o.x + y * o.y + z * o.z
    @inline infix def cross(o: Vec3): Vec3 =
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    @inline def len: Double = math.sqrt(x * x + y * y + z * z)
    @inline def norm: Vec3 = { val l = len; Vec3(x / l, y / l, z / l) }
    @inline def reflect(n: Vec3): Vec3 = this - n * (2.0 * (this dot n))
  }

  // ── Scene objects ────────────────────────────────────────────────
  final case class Sphere(center: Vec3, radius: Double, color: Vec3,
                          reflectivity: Double, specular: Double)
  final case class Light(position: Vec3, intensity: Double)
  final case class Ray(origin: Vec3, dir: Vec3)

  final case class HitInfo(hit: Boolean, t: Double, point: Vec3, normal: Vec3,
                           color: Vec3, reflectivity: Double, specular: Double)

  val NoHit: HitInfo = HitInfo(false, 1e20, Vec3(0, 0, 0), Vec3(0, 0, 0),
                                Vec3(0, 0, 0), 0.0, 0.0)

  // ── Scene definition ────────────────────────────────────────────
  val spheres: Array[Sphere] = Array(
    Sphere(Vec3(-2.0, 1.0, 0.0), 1.0, Vec3(0.9, 0.2, 0.2), 0.3, 50.0),
    Sphere(Vec3(0.0, 0.75, 0.0), 0.75, Vec3(0.2, 0.9, 0.2), 0.2, 30.0),
    Sphere(Vec3(2.0, 1.0, 0.0), 1.0, Vec3(0.2, 0.2, 0.9), 0.4, 80.0),
    Sphere(Vec3(-0.75, 0.4, -1.5), 0.4, Vec3(0.9, 0.9, 0.2), 0.5, 100.0),
    Sphere(Vec3(1.5, 0.5, -1.0), 0.5, Vec3(0.9, 0.2, 0.9), 0.6, 60.0)
  )

  val lights: Array[Light] = Array(
    Light(Vec3(-3.0, 5.0, -3.0), 0.7),
    Light(Vec3(3.0, 3.0, -1.0), 0.4)
  )

  val Ambient: Double = 0.1
  val GroundY: Double = 0.0
  val GroundReflect: Double = 0.3
  val GroundSpecular: Double = 10.0
  val CheckSize: Double = 1.0
  val MaxDepth: Int = 5
  val Epsilon: Double = 1e-6
  val Inf: Double = 1e20

  // ── Intersection routines ────────────────────────────────────────
  @inline def intersectSphere(r: Ray, s: Sphere): Double = {
    val oc = r.origin - s.center
    val b = oc dot r.dir
    val c = (oc dot oc) - s.radius * s.radius
    val disc = b * b - c
    if (disc < 0.0) return Inf
    val sq = math.sqrt(disc)
    val t1 = -b - sq
    if (t1 > Epsilon) return t1
    val t2 = -b + sq
    if (t2 > Epsilon) t2 else Inf
  }

  @inline def intersectGround(r: Ray): Double = {
    if (math.abs(r.dir.y) < Epsilon) return Inf
    val t = (GroundY - r.origin.y) / r.dir.y
    if (t > Epsilon) t else Inf
  }

  // ── Scene intersection ──────────────────────────────────────────
  def sceneIntersect(r: Ray): HitInfo = {
    var bestT = Inf
    var bestHit = false
    var bestPoint = Vec3(0, 0, 0)
    var bestNormal = Vec3(0, 0, 0)
    var bestColor = Vec3(0, 0, 0)
    var bestRefl = 0.0
    var bestSpec = 0.0

    // spheres
    var i = 0
    while (i < spheres.length) {
      val s = spheres(i)
      val t = intersectSphere(r, s)
      if (t < bestT) {
        bestHit = true
        bestT = t
        bestPoint = r.origin + r.dir * t
        bestNormal = (bestPoint - s.center).norm
        bestColor = s.color
        bestRefl = s.reflectivity
        bestSpec = s.specular
      }
      i += 1
    }

    // ground plane
    val tg = intersectGround(r)
    if (tg < bestT) {
      bestHit = true
      bestT = tg
      bestPoint = r.origin + r.dir * tg
      bestNormal = Vec3(0.0, 1.0, 0.0)
      val px = bestPoint.x / CheckSize
      val pz = bestPoint.z / CheckSize
      val fx = if (px < 0.0) math.floor(px - 1.0) else math.floor(px)
      val fz = if (pz < 0.0) math.floor(pz - 1.0) else math.floor(pz)
      val check = (fx.toInt + fz.toInt) & 1
      bestColor = if (check != 0) Vec3(0.3, 0.3, 0.3) else Vec3(0.8, 0.8, 0.8)
      bestRefl = GroundReflect
      bestSpec = GroundSpecular
    }

    HitInfo(bestHit, bestT, bestPoint, bestNormal, bestColor, bestRefl, bestSpec)
  }

  // ── Shadow check ────────────────────────────────────────────────
  def inShadow(point: Vec3, lightDir: Vec3, lightDist: Double): Boolean = {
    val shadowRay = Ray(point, lightDir)
    var i = 0
    while (i < spheres.length) {
      val t = intersectSphere(shadowRay, spheres(i))
      if (t < lightDist) return true
      i += 1
    }
    val tg = intersectGround(shadowRay)
    tg < lightDist
  }

  // ── Shading ─────────────────────────────────────────────────────
  def shade(h: HitInfo, r: Ray, depth: Int): Vec3 = {
    var result = h.color * Ambient

    val offsetPoint = h.point + h.normal * Epsilon

    var i = 0
    while (i < lights.length) {
      val light = lights(i)
      val toLight = light.position - h.point
      val dist = toLight.len
      val lightDir = toLight * (1.0 / dist)

      if (!inShadow(offsetPoint, lightDir, dist)) {
        val nDotL = h.normal dot lightDir
        if (nDotL > 0.0) {
          // diffuse
          result = result + h.color * (nDotL * light.intensity)

          // specular (Phong) - white specular
          val reflDir = (lightDir * -1.0).reflect(h.normal)
          val viewDir = r.dir * -1.0
          val specDot = viewDir dot reflDir
          if (specDot > 0.0) {
            val spec = math.pow(specDot, h.specular) * light.intensity
            result = result + Vec3(spec, spec, spec)
          }
        }
      }
      i += 1
    }

    // reflections
    if (depth < MaxDepth && h.reflectivity > 0.0) {
      val reflRay = Ray(offsetPoint, r.dir.reflect(h.normal))
      val reflColor = trace(reflRay, depth + 1)
      result = result * (1.0 - h.reflectivity) + reflColor * h.reflectivity
    }

    result
  }

  // ── Trace ───────────────────────────────────────────────────────
  def trace(r: Ray, depth: Int): Vec3 = {
    val h = sceneIntersect(r)
    if (!h.hit) {
      // sky gradient
      val t = 0.5 * (r.dir.norm.y + 1.0)
      return Vec3(1.0, 1.0, 1.0) * (1.0 - t) + Vec3(0.5, 0.7, 1.0) * t
    }
    shade(h, r, depth)
  }

  // ── Camera ──────────────────────────────────────────────────────
  final case class Camera(origin: Vec3, lowerLeft: Vec3,
                          horizontal: Vec3, vertical: Vec3)

  def makeCamera(from: Vec3, at: Vec3, vup: Vec3, vfov: Double,
                 aspect: Double): Camera = {
    val theta = vfov * math.Pi / 180.0
    val halfH = math.tan(theta / 2.0)
    val halfW = aspect * halfH

    val w = (from - at).norm
    val u = (vup cross w).norm
    val v = w cross u

    Camera(
      origin = from,
      horizontal = u * (2.0 * halfW),
      vertical = v * (2.0 * halfH),
      lowerLeft = from - u * halfW - v * halfH - w
    )
  }

  @inline def camRay(cam: Camera, s: Double, t: Double): Ray = {
    val target = cam.lowerLeft + cam.horizontal * s + cam.vertical * t
    Ray(cam.origin, (target - cam.origin).norm)
  }

  @inline def clamp01(x: Double): Double =
    if (x < 0.0) 0.0 else if (x > 1.0) 1.0 else x

  // ── Main ────────────────────────────────────────────────────────
  def main(args: Array[String]): Unit = {
    val width = args(0).toInt
    val height = args(1).toInt

    val aspect = width.toDouble / height.toDouble
    val cam = makeCamera(
      Vec3(0.0, 1.5, -5.0),
      Vec3(0.0, 0.5, 0.0),
      Vec3(0.0, 1.0, 0.0),
      60.0, aspect
    )

    val invGamma = 1.0 / 2.2

    val buf = new Array[Byte](width * height * 3)
    var idx = 0

    var j = height - 1
    while (j >= 0) {
      val v = (j.toDouble + 0.5) / height.toDouble
      var i = 0
      while (i < width) {
        val u = (i.toDouble + 0.5) / width.toDouble
        val r = camRay(cam, u, v)
        val col = trace(r, 0)

        val cr = math.pow(clamp01(col.x), invGamma)
        val cg = math.pow(clamp01(col.y), invGamma)
        val cb = math.pow(clamp01(col.z), invGamma)

        buf(idx) = (cr * 255.0 + 0.5).toInt.toByte; idx += 1
        buf(idx) = (cg * 255.0 + 0.5).toInt.toByte; idx += 1
        buf(idx) = (cb * 255.0 + 0.5).toInt.toByte; idx += 1

        i += 1
      }
      j -= 1
    }

    val out = new BufferedOutputStream(System.out)
    val header = s"P6\n${width} ${height}\n255\n".getBytes("ASCII")
    out.write(header)
    out.write(buf)
    out.flush()
  }
}
