"use strict";

const WIDTH = parseInt(process.argv[2], 10);
const HEIGHT = parseInt(process.argv[3], 10);

// Vector operations (inline for performance)
function vAdd(a, b) { return [a[0]+b[0], a[1]+b[1], a[2]+b[2]]; }
function vSub(a, b) { return [a[0]-b[0], a[1]-b[1], a[2]-b[2]]; }
function vMul(a, s) { return [a[0]*s, a[1]*s, a[2]*s]; }
function vDot(a, b) { return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]; }
function vLen(a) { return Math.sqrt(a[0]*a[0] + a[1]*a[1] + a[2]*a[2]); }
function vNorm(a) { const l = 1 / vLen(a); return [a[0]*l, a[1]*l, a[2]*l]; }
function vMulV(a, b) { return [a[0]*b[0], a[1]*b[1], a[2]*b[2]]; }
function vReflect(v, n) {
  const d2 = 2 * vDot(v, n);
  return [v[0] - d2*n[0], v[1] - d2*n[1], v[2] - d2*n[2]];
}

// Scene setup
const spheres = [
  { cx: -2, cy: 1, cz: 0, r: 1.0, r2: 1.0, color: [0.9, 0.2, 0.2], refl: 0.3, spec: 50 },
  { cx: 0, cy: 0.75, cz: 0, r: 0.75, r2: 0.5625, color: [0.2, 0.9, 0.2], refl: 0.2, spec: 30 },
  { cx: 2, cy: 1, cz: 0, r: 1.0, r2: 1.0, color: [0.2, 0.2, 0.9], refl: 0.4, spec: 80 },
  { cx: -0.75, cy: 0.4, cz: -1.5, r: 0.4, r2: 0.16, color: [0.9, 0.9, 0.2], refl: 0.5, spec: 100 },
  { cx: 1.5, cy: 0.5, cz: -1, r: 0.5, r2: 0.25, color: [0.9, 0.2, 0.9], refl: 0.6, spec: 60 },
];

const lights = [
  { pos: [-3, 5, -3], intensity: 0.7 },
  { pos: [3, 3, -1], intensity: 0.4 },
];

const AMBIENT = 0.1;
const MAX_DEPTH = 5;
const EPSILON = 1e-6;
const GAMMA_INV = 1.0 / 2.2;

// Camera
const camPos = [0, 1.5, -5];
const camLookAt = [0, 0.5, 0];
const camUp = [0, 1, 0];

const camForward = vNorm(vSub(camLookAt, camPos));
const camRight = vNorm([
  camForward[1]*camUp[2] - camForward[2]*camUp[1],
  camForward[2]*camUp[0] - camForward[0]*camUp[2],
  camForward[0]*camUp[1] - camForward[1]*camUp[0],
]);
const camUpReal = [
  camRight[1]*camForward[2] - camRight[2]*camForward[1],
  camRight[2]*camForward[0] - camRight[0]*camForward[2],
  camRight[0]*camForward[1] - camRight[1]*camForward[0],
];

const aspect = WIDTH / HEIGHT;
const fovScale = Math.tan((60 * Math.PI / 180) * 0.5);

// Intersection: returns t or -1
function intersectSphere(ox, oy, oz, dx, dy, dz, s) {
  const ex = ox - s.cx;
  const ey = oy - s.cy;
  const ez = oz - s.cz;
  const b = ex*dx + ey*dy + ez*dz;
  const c = ex*ex + ey*ey + ez*ez - s.r2;
  const disc = b*b - c;
  if (disc < 0) return -1;
  const sqrtDisc = Math.sqrt(disc);
  let t = -b - sqrtDisc;
  if (t > EPSILON) return t;
  t = -b + sqrtDisc;
  if (t > EPSILON) return t;
  return -1;
}

// Plane intersection: y=0
function intersectPlane(oy, dy) {
  if (dy >= -EPSILON && dy <= EPSILON) return -1;
  const t = -oy / dy;
  return t > EPSILON ? t : -1;
}

// Find closest intersection
// Returns: [t, sphereIndex] where sphereIndex = -1 means ground plane
function findClosest(ox, oy, oz, dx, dy, dz) {
  let bestT = Infinity;
  let bestIdx = -2; // -2 = nothing

  for (let i = 0; i < 5; i++) {
    const t = intersectSphere(ox, oy, oz, dx, dy, dz, spheres[i]);
    if (t > 0 && t < bestT) {
      bestT = t;
      bestIdx = i;
    }
  }

  const tp = intersectPlane(oy, dy);
  if (tp > 0 && tp < bestT) {
    bestT = tp;
    bestIdx = -1; // ground plane
  }

  return bestIdx >= -1 ? bestT : -1;
}

function findClosestIdx(ox, oy, oz, dx, dy, dz) {
  let bestT = Infinity;
  let bestIdx = -2;

  for (let i = 0; i < 5; i++) {
    const t = intersectSphere(ox, oy, oz, dx, dy, dz, spheres[i]);
    if (t > 0 && t < bestT) {
      bestT = t;
      bestIdx = i;
    }
  }

  const tp = intersectPlane(oy, dy);
  if (tp > 0 && tp < bestT) {
    bestT = tp;
    bestIdx = -1;
  }

  return [bestT, bestIdx];
}

// Trace ray, returns [r, g, b]
function trace(ox, oy, oz, dx, dy, dz, depth) {
  if (depth > MAX_DEPTH) return [0, 0, 0];

  const [t, idx] = findClosestIdx(ox, oy, oz, dx, dy, dz);

  if (idx === -2) {
    // Background: simple gradient
    const blend = 0.5 * (dy + 1.0);
    return [1.0 - 0.5 * blend, 1.0 - 0.3 * blend, 1.0];
  }

  // Hit point
  const hx = ox + dx * t;
  const hy = oy + dy * t;
  const hz = oz + dz * t;

  let nx, ny, nz;
  let cr, cg, cb;
  let reflectivity, specPow;

  if (idx === -1) {
    // Ground plane
    nx = 0; ny = 1; nz = 0;
    reflectivity = 0.3;
    specPow = 10;

    // Checkerboard
    let fx = hx < 0 ? Math.floor(hx - 1) : Math.floor(hx);
    let fz = hz < 0 ? Math.floor(hz - 1) : Math.floor(hz);
    if (((fx + fz) & 1) === 0) {
      cr = 0.8; cg = 0.8; cb = 0.8;
    } else {
      cr = 0.3; cg = 0.3; cb = 0.3;
    }
  } else {
    // Sphere
    const s = spheres[idx];
    const invR = 1.0 / s.r;
    nx = (hx - s.cx) * invR;
    ny = (hy - s.cy) * invR;
    nz = (hz - s.cz) * invR;
    cr = s.color[0];
    cg = s.color[1];
    cb = s.color[2];
    reflectivity = s.refl;
    specPow = s.spec;
  }

  // Ensure normal faces the ray
  const dotND = nx*dx + ny*dy + nz*dz;
  if (dotND > 0) {
    nx = -nx; ny = -ny; nz = -nz;
  }

  // Lighting
  let diffR = AMBIENT * cr;
  let diffG = AMBIENT * cg;
  let diffB = AMBIENT * cb;
  let specR = 0, specG = 0, specB = 0;

  for (let li = 0; li < 2; li++) {
    const light = lights[li];
    const lx = light.pos[0] - hx;
    const ly = light.pos[1] - hy;
    const lz = light.pos[2] - hz;
    const lDist = Math.sqrt(lx*lx + ly*ly + lz*lz);
    const invLD = 1.0 / lDist;
    const ldx = lx * invLD;
    const ldy = ly * invLD;
    const ldz = lz * invLD;

    // Shadow check
    const sox = hx + nx * EPSILON;
    const soy = hy + ny * EPSILON;
    const soz = hz + nz * EPSILON;

    let inShadow = false;
    for (let si = 0; si < 5; si++) {
      const st = intersectSphere(sox, soy, soz, ldx, ldy, ldz, spheres[si]);
      if (st > 0 && st < lDist) { inShadow = true; break; }
    }
    if (!inShadow) {
      // Check ground plane shadow
      const pt = intersectPlane(soy, ldy);
      if (pt > 0 && pt < lDist) inShadow = true;
    }

    if (inShadow) continue;

    const intensity = light.intensity;

    // Diffuse
    const NdotL = nx*ldx + ny*ldy + nz*ldz;
    if (NdotL > 0) {
      const d = NdotL * intensity;
      diffR += cr * d;
      diffG += cg * d;
      diffB += cb * d;
    }

    // Specular (Phong)
    // Reflect light direction about normal
    const rDot2 = 2 * (ldx*nx + ldy*ny + ldz*nz);
    const rlx = ldx - rDot2*nx; // This is actually wrong direction, let me fix
    // For Phong: R = 2*(N.L)*N - L
    const refX = rDot2*nx - ldx;
    const refY = rDot2*ny - ldy;
    const refZ = rDot2*nz - ldz;

    // View direction (from hit point to camera / ray origin direction)
    const vx = -dx;
    const vy = -dy;
    const vz = -dz;

    const RdotV = refX*vx + refY*vy + refZ*vz;
    if (RdotV > 0) {
      const sp = Math.pow(RdotV, specPow) * intensity;
      specR += sp;
      specG += sp;
      specB += sp;
    }
  }

  let outR = diffR + specR;
  let outG = diffG + specG;
  let outB = diffB + specB;

  // Reflections
  if (reflectivity > 0 && depth < MAX_DEPTH) {
    // Reflect ray direction about normal
    const rDot2 = 2 * (dx*nx + dy*ny + dz*nz);
    const rdx = dx - rDot2*nx;
    const rdy = dy - rDot2*ny;
    const rdz = dz - rDot2*nz;

    const rox = hx + nx * EPSILON;
    const roy = hy + ny * EPSILON;
    const roz = hz + nz * EPSILON;

    const refl = trace(rox, roy, roz, rdx, rdy, rdz, depth + 1);
    outR = outR * (1 - reflectivity) + refl[0] * reflectivity;
    outG = outG * (1 - reflectivity) + refl[1] * reflectivity;
    outB = outB * (1 - reflectivity) + refl[2] * reflectivity;
  }

  return [outR, outG, outB];
}

// Main render
const header = `P6\n${WIDTH} ${HEIGHT}\n255\n`;
const headerBuf = Buffer.from(header, 'ascii');
const pixelBuf = Buffer.alloc(WIDTH * HEIGHT * 3);

let offset = 0;
for (let y = 0; y < HEIGHT; y++) {
  for (let x = 0; x < WIDTH; x++) {
    // Normalized device coordinates
    const px = (2 * (x + 0.5) / WIDTH - 1) * aspect * fovScale;
    const py = (1 - 2 * (y + 0.5) / HEIGHT) * fovScale;

    // Ray direction in world space
    const rdx = camRight[0]*px + camUpReal[0]*py + camForward[0];
    const rdy = camRight[1]*px + camUpReal[1]*py + camForward[1];
    const rdz = camRight[2]*px + camUpReal[2]*py + camForward[2];
    const invLen = 1.0 / Math.sqrt(rdx*rdx + rdy*rdy + rdz*rdz);
    const dx = rdx * invLen;
    const dy = rdy * invLen;
    const dz = rdz * invLen;

    const color = trace(camPos[0], camPos[1], camPos[2], dx, dy, dz, 0);

    // Gamma correction and clamp
    let r = Math.pow(Math.min(Math.max(color[0], 0), 1), GAMMA_INV);
    let g = Math.pow(Math.min(Math.max(color[1], 0), 1), GAMMA_INV);
    let b = Math.pow(Math.min(Math.max(color[2], 0), 1), GAMMA_INV);

    pixelBuf[offset++] = (r * 255 + 0.5) | 0;
    pixelBuf[offset++] = (g * 255 + 0.5) | 0;
    pixelBuf[offset++] = (b * 255 + 0.5) | 0;
  }
}

process.stdout.write(headerBuf);
process.stdout.write(pixelBuf);
