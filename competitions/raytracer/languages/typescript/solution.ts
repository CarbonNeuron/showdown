const W = parseInt(Deno.args[0]);
const H = parseInt(Deno.args[1]);

type V3 = [number, number, number];

function add(a: V3, b: V3): V3 { return [a[0]+b[0], a[1]+b[1], a[2]+b[2]]; }
function sub(a: V3, b: V3): V3 { return [a[0]-b[0], a[1]-b[1], a[2]-b[2]]; }
function mul(a: V3, s: number): V3 { return [a[0]*s, a[1]*s, a[2]*s]; }
function dot(a: V3, b: V3): number { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }
function cross(a: V3, b: V3): V3 { return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]; }
function len(a: V3): number { return Math.sqrt(dot(a, a)); }
function norm(a: V3): V3 { const l = len(a); return [a[0]/l, a[1]/l, a[2]/l]; }
function vmul(a: V3, b: V3): V3 { return [a[0]*b[0], a[1]*b[1], a[2]*b[2]]; }

interface Sphere {
  center: V3;
  radius: number;
  color: V3;
  refl: number;
  spec: number;
}

interface Light {
  pos: V3;
  intensity: number;
}

const spheres: Sphere[] = [
  { center: [-2, 1, 0], radius: 1, color: [0.9, 0.2, 0.2], refl: 0.3, spec: 50 },
  { center: [0, 0.75, 0], radius: 0.75, color: [0.2, 0.9, 0.2], refl: 0.2, spec: 30 },
  { center: [2, 1, 0], radius: 1, color: [0.2, 0.2, 0.9], refl: 0.4, spec: 80 },
  { center: [-0.75, 0.4, -1.5], radius: 0.4, color: [0.9, 0.9, 0.2], refl: 0.5, spec: 100 },
  { center: [1.5, 0.5, -1], radius: 0.5, color: [0.9, 0.2, 0.9], refl: 0.6, spec: 60 },
];

const lights: Light[] = [
  { pos: [-3, 5, -3], intensity: 0.7 },
  { pos: [3, 3, -1], intensity: 0.4 },
];

const camPos: V3 = [0, 1.5, -5];
const lookAt: V3 = [0, 0.5, 0];
const up: V3 = [0, 1, 0];
const fov = 60;
const ambient = 0.1;
const maxDepth = 5;

const forward = norm(sub(lookAt, camPos));
const right = norm(cross(forward, up));
const camUp = cross(right, forward);

const fovRad = fov * Math.PI / 180;
const halfH = Math.tan(fovRad / 2);
const aspect = W / H;
const halfW = aspect * halfH;

function intersectSphere(o: V3, d: V3, s: Sphere): number {
  const oc = sub(o, s.center);
  const b = dot(oc, d);
  const c = dot(oc, oc) - s.radius * s.radius;
  const disc = b * b - c;
  if (disc < 0) return -1;
  const sq = Math.sqrt(disc);
  let t = -b - sq;
  if (t < 1e-4) {
    t = -b + sq;
    if (t < 1e-4) return -1;
  }
  return t;
}

function intersectGround(o: V3, d: V3): number {
  if (Math.abs(d[1]) < 1e-8) return -1;
  const t = -o[1] / d[1];
  return t > 1e-4 ? t : -1;
}

interface Hit {
  t: number;
  point: V3;
  normal: V3;
  color: V3;
  refl: number;
  spec: number;
}

function findHit(o: V3, d: V3): Hit | null {
  let closest: Hit | null = null;
  let minT = 1e20;

  for (const s of spheres) {
    const t = intersectSphere(o, d, s);
    if (t > 0 && t < minT) {
      minT = t;
      const point = add(o, mul(d, t));
      const normal = norm(sub(point, s.center));
      closest = { t, point, normal, color: s.color, refl: s.refl, spec: s.spec };
    }
  }

  const tg = intersectGround(o, d);
  if (tg > 0 && tg < minT) {
    const point = add(o, mul(d, tg));
    const fx = point[0] < 0 ? Math.floor(point[0]) - 1 : Math.floor(point[0]);
    const fz = Math.floor(point[2]);
    const check = ((fx | 0) + (fz | 0)) & 1;
    const color: V3 = check ? [0.3, 0.3, 0.3] : [0.8, 0.8, 0.8];
    closest = { t: tg, point, normal: [0, 1, 0], color, refl: 0.3, spec: 10 };
  }

  return closest;
}

function reflect(d: V3, n: V3): V3 {
  const dn = dot(d, n);
  return sub(d, mul(n, 2 * dn));
}

function inShadow(point: V3, lightDir: V3, lightDist: number): boolean {
  const o = add(point, mul(lightDir, 1e-4));
  for (const s of spheres) {
    const t = intersectSphere(o, lightDir, s);
    if (t > 0 && t < lightDist) return true;
  }
  const tg = intersectGround(o, lightDir);
  if (tg > 0 && tg < lightDist) return true;
  return false;
}

function sky(d: V3): V3 {
  const t = 0.5 * (d[1] + 1);
  return add(mul([1, 1, 1], 1 - t), mul([0.5, 0.7, 1.0], t));
}

function trace(o: V3, d: V3, depth: number): V3 {
  if (depth > maxDepth) return sky(d);

  const hit = findHit(o, d);
  if (!hit) return sky(d);

  const { point, normal, color, refl, spec } = hit;

  // Ambient
  let local: V3 = mul(color, ambient);

  // Lights
  for (const light of lights) {
    const toLight = sub(light.pos, point);
    const lightDist = len(toLight);
    const lightDir = norm(toLight);
    const nDotL = dot(normal, lightDir);

    if (nDotL > 0 && !inShadow(point, lightDir, lightDist)) {
      // Diffuse
      const diffuse = mul(color, nDotL * light.intensity);
      local = add(local, diffuse);

      // Specular
      const reflDir = reflect(mul(lightDir, -1), normal);
      const rDotV = Math.max(0, dot(mul(d, -1), reflDir));
      const specular = Math.pow(rDotV, spec) * light.intensity;
      local = add(local, [specular, specular, specular]);
    }
  }

  // Reflection
  if (refl > 0 && depth < maxDepth) {
    const reflDir = reflect(d, normal);
    const reflOrigin = add(point, mul(reflDir, 1e-4));
    const reflColor = trace(reflOrigin, reflDir, depth + 1);
    local = add(mul(local, 1 - refl), mul(reflColor, refl));
  }

  return local;
}

function clamp(x: number): number { return x < 0 ? 0 : x > 1 ? 1 : x; }

// PPM header
const header = `P6\n${W} ${H}\n255\n`;
const headerBytes = new TextEncoder().encode(header);
const pixelBytes = new Uint8Array(W * H * 3);

let idx = 0;
for (let j = 0; j < H; j++) {
  for (let i = 0; i < W; i++) {
    const u = (2 * ((i + 0.5) / W) - 1) * halfW;
    const v = (1 - 2 * ((j + 0.5) / H)) * halfH;
    const dir = norm(add(add(forward, mul(right, u)), mul(camUp, v)));
    const c = trace(camPos, dir, 0);
    pixelBytes[idx++] = Math.round(Math.pow(clamp(c[0]), 1 / 2.2) * 255);
    pixelBytes[idx++] = Math.round(Math.pow(clamp(c[1]), 1 / 2.2) * 255);
    pixelBytes[idx++] = Math.round(Math.pow(clamp(c[2]), 1 / 2.2) * 255);
  }
}

Deno.stdout.writeSync(headerBytes);
Deno.stdout.writeSync(pixelBytes);
