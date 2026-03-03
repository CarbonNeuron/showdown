import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator /(double s) => Vec3(x / s, y / s, z / s);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  double get length => sqrt(x * x + y * y + z * z);

  Vec3 get norm {
    final l = length;
    return l > 0 ? this / l : this;
  }

  Vec3 reflect(Vec3 n) => this - n * (2.0 * this.dot(n));

  Vec3 clamp01() => Vec3(
      x < 0 ? 0 : (x > 1 ? 1 : x),
      y < 0 ? 0 : (y > 1 ? 1 : y),
      z < 0 ? 0 : (z > 1 ? 1 : z));

  Vec3 mul(Vec3 o) => Vec3(x * o.x, y * o.y, z * o.z);
}

class Ray {
  final Vec3 origin, dir;
  const Ray(this.origin, this.dir);
}

class Sphere {
  final Vec3 center, color;
  final double radius, refl, specExp;
  const Sphere(this.center, this.radius, this.color, this.refl, this.specExp);
}

class Light {
  final Vec3 pos;
  final double intensity;
  const Light(this.pos, this.intensity);
}

class Hit {
  final double t;
  final Vec3 point, normal, color;
  final double refl, specExp;
  const Hit(this.t, this.point, this.normal, this.color, this.refl, this.specExp);
}

final List<Sphere> spheres = [
  Sphere(Vec3(-2, 1, 0), 1.0, Vec3(0.9, 0.2, 0.2), 0.3, 50),
  Sphere(Vec3(0, 0.75, 0), 0.75, Vec3(0.2, 0.9, 0.2), 0.2, 30),
  Sphere(Vec3(2, 1, 0), 1.0, Vec3(0.2, 0.2, 0.9), 0.4, 80),
  Sphere(Vec3(-0.75, 0.4, -1.5), 0.4, Vec3(0.9, 0.9, 0.2), 0.5, 100),
  Sphere(Vec3(1.5, 0.5, -1), 0.5, Vec3(0.9, 0.2, 0.9), 0.6, 60),
];

final List<Light> lights = [
  Light(Vec3(-3, 5, -3), 0.7),
  Light(Vec3(3, 3, -1), 0.4),
];

const double ambient = 0.1;
const int maxDepth = 5;

double? intersectSphere(Ray ray, Sphere s) {
  final oc = ray.origin - s.center;
  final a = ray.dir.dot(ray.dir);
  final b = 2.0 * oc.dot(ray.dir);
  final c = oc.dot(oc) - s.radius * s.radius;
  final disc = b * b - 4.0 * a * c;
  if (disc < 0) return null;
  final sqrtDisc = sqrt(disc);
  var t = (-b - sqrtDisc) / (2.0 * a);
  if (t < 1e-4) {
    t = (-b + sqrtDisc) / (2.0 * a);
    if (t < 1e-4) return null;
  }
  return t;
}

double? intersectGround(Ray ray) {
  if (ray.dir.y.abs() < 1e-8) return null;
  final t = -ray.origin.y / ray.dir.y;
  return t > 1e-4 ? t : null;
}

Vec3 checkerboardColor(Vec3 point) {
  int fx = point.x < 0 ? (point.x - 1).floor() : point.x.floor();
  int fz = point.z < 0 ? (point.z - 1).floor() : point.z.floor();
  if ((fx + fz) & 1 == 0) {
    return Vec3(0.8, 0.8, 0.8);
  } else {
    return Vec3(0.3, 0.3, 0.3);
  }
}

Hit? intersectScene(Ray ray) {
  double closest = double.infinity;
  Hit? hit;

  for (final s in spheres) {
    final t = intersectSphere(ray, s);
    if (t != null && t < closest) {
      closest = t;
      final p = ray.origin + ray.dir * t;
      final n = (p - s.center).norm;
      hit = Hit(t, p, n, s.color, s.refl, s.specExp);
    }
  }

  final tg = intersectGround(ray);
  if (tg != null && tg < closest) {
    closest = tg;
    final p = ray.origin + ray.dir * tg;
    final n = Vec3(0, 1, 0);
    final col = checkerboardColor(p);
    hit = Hit(tg, p, n, col, 0.3, 10);
  }

  return hit;
}

bool inShadow(Vec3 point, Vec3 lightDir, double lightDist) {
  final shadowRay = Ray(point + lightDir * 1e-4, lightDir);
  for (final s in spheres) {
    final t = intersectSphere(shadowRay, s);
    if (t != null && t < lightDist) return true;
  }
  final tg = intersectGround(shadowRay);
  if (tg != null && tg < lightDist) return true;
  return false;
}

Vec3 sky(Vec3 dir) {
  final t = 0.5 * (dir.y + 1.0);
  return Vec3(1, 1, 1) * (1.0 - t) + Vec3(0.5, 0.7, 1.0) * t;
}

Vec3 trace(Ray ray, int depth) {
  if (depth > maxDepth) return Vec3(0, 0, 0);

  final hit = intersectScene(ray);
  if (hit == null) return sky(ray.dir);

  final p = hit.point;
  final n = hit.normal;
  final col = hit.color;

  // Ambient
  var local = col * ambient;

  // For each light
  for (final light in lights) {
    final toLight = light.pos - p;
    final lightDist = toLight.length;
    final lightDir = toLight.norm;
    final nDotL = n.dot(lightDir);

    if (nDotL > 0) {
      if (!inShadow(p, lightDir, lightDist)) {
        // Diffuse
        local = local + col * (nDotL * light.intensity);

        // Specular (Phong)
        final reflLight = (lightDir * -1.0).reflect(n);
        final specAngle = max(0.0, (ray.dir * -1.0).dot(reflLight));
        final spec = pow(specAngle, hit.specExp) * light.intensity;
        local = local + Vec3(1, 1, 1) * spec;
      }
    }
  }

  // Reflection
  if (hit.refl > 0 && depth < maxDepth) {
    final reflDir = ray.dir.reflect(n);
    final reflRay = Ray(p + reflDir * 1e-4, reflDir);
    final reflColor = trace(reflRay, depth + 1);
    local = local * (1.0 - hit.refl) + reflColor * hit.refl;
  }

  return local;
}

void main(List<String> args) {
  final width = int.parse(args[0]);
  final height = int.parse(args[1]);

  final camPos = Vec3(0, 1.5, -5);
  final lookAt = Vec3(0, 0.5, 0);
  final up = Vec3(0, 1, 0);
  final fov = 60.0 * pi / 180.0;

  final forward = (lookAt - camPos).norm;
  final right = forward.cross(up).norm;
  final camUp = right.cross(forward).norm;

  final aspect = width / height;
  final halfH = tan(fov / 2.0);
  final halfW = aspect * halfH;

  // PPM header
  final header = 'P6\n$width $height\n255\n';
  stdout.add(Uint8List.fromList(header.codeUnits));

  final rowBytes = Uint8List(width * 3);

  for (int j = 0; j < height; j++) {
    for (int i = 0; i < width; i++) {
      final u = (2.0 * ((i + 0.5) / width) - 1.0) * halfW;
      final v = (1.0 - 2.0 * ((j + 0.5) / height)) * halfH;

      final dir = (forward + right * u + camUp * v).norm;
      final ray = Ray(camPos, dir);

      var color = trace(ray, 0).clamp01();

      // Gamma correction
      final r = pow(color.x, 1.0 / 2.2);
      final g = pow(color.y, 1.0 / 2.2);
      final b = pow(color.z, 1.0 / 2.2);

      final idx = i * 3;
      rowBytes[idx] = (r * 255 + 0.5).toInt();
      rowBytes[idx + 1] = (g * 255 + 0.5).toInt();
      rowBytes[idx + 2] = (b * 255 + 0.5).toInt();
    }
    stdout.add(Uint8List.fromList(rowBytes));
  }
}
