import java.io.BufferedOutputStream;
import java.io.IOException;

public class solution {

    static final int MAX_DEPTH = 5;
    static final double AMBIENT = 0.1;
    static final double EPSILON = 1e-6;

    // ── Vector ──────────────────────────────────────────────────────────
    static double[] vec(double x, double y, double z) { return new double[]{x, y, z}; }
    static double dot(double[] a, double[] b) { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }
    static double[] add(double[] a, double[] b) { return vec(a[0]+b[0],a[1]+b[1],a[2]+b[2]); }
    static double[] sub(double[] a, double[] b) { return vec(a[0]-b[0],a[1]-b[1],a[2]-b[2]); }
    static double[] mul(double[] a, double s) { return vec(a[0]*s,a[1]*s,a[2]*s); }
    static double[] cross(double[] a, double[] b) {
        return vec(a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]);
    }
    static double len(double[] a) { return Math.sqrt(dot(a,a)); }
    static double[] norm(double[] a) { double l=len(a); return vec(a[0]/l,a[1]/l,a[2]/l); }
    static double[] reflect(double[] v, double[] n) { return sub(v, mul(n, 2*dot(v,n))); }

    // ── Sphere ──────────────────────────────────────────────────────────
    static final double[][] sphereCenter = {
        {-2, 1, 0}, {0, 0.75, 0}, {2, 1, 0}, {-0.75, 0.4, -1.5}, {1.5, 0.5, -1}
    };
    static final double[] sphereRadius = {1, 0.75, 1, 0.4, 0.5};
    static final double[][] sphereColor = {
        {0.9,0.2,0.2}, {0.2,0.9,0.2}, {0.2,0.2,0.9}, {0.9,0.9,0.2}, {0.9,0.2,0.9}
    };
    static final double[] sphereRefl = {0.3, 0.2, 0.4, 0.5, 0.6};
    static final double[] sphereSpec = {50, 30, 80, 100, 60};
    static final int NUM_SPHERES = 5;

    // ── Lights ──────────────────────────────────────────────────────────
    static final double[][] lightPos = { {-3,5,-3}, {3,3,-1} };
    static final double[] lightInt = { 0.7, 0.4 };
    static final int NUM_LIGHTS = 2;

    // ── Ground ──────────────────────────────────────────────────────────
    static final double GROUND_Y = 0;
    static final double GROUND_REFL = 0.3;
    static final double GROUND_SPEC = 10;

    // ── Hit record ──────────────────────────────────────────────────────
    // hitType: 0=none, 1=sphere, 2=ground; hitIdx: sphere index
    static int hitType, hitIdx;
    static double hitT;
    static double[] hitPoint, hitNormal, hitColor;
    static double hitRefl, hitSpecExp;

    static boolean intersectScene(double[] ro, double[] rd) {
        hitT = 1e20;
        hitType = 0;

        // Spheres
        for (int i = 0; i < NUM_SPHERES; i++) {
            double[] oc = sub(ro, sphereCenter[i]);
            double b = dot(oc, rd);
            double c = dot(oc, oc) - sphereRadius[i] * sphereRadius[i];
            double disc = b * b - c;
            if (disc > 0) {
                double sqrtDisc = Math.sqrt(disc);
                double t = -b - sqrtDisc;
                if (t < EPSILON) t = -b + sqrtDisc;
                if (t > EPSILON && t < hitT) {
                    hitT = t;
                    hitType = 1;
                    hitIdx = i;
                }
            }
        }

        // Ground plane y=0
        if (Math.abs(rd[1]) > EPSILON) {
            double t = (GROUND_Y - ro[1]) / rd[1];
            if (t > EPSILON && t < hitT) {
                hitT = t;
                hitType = 2;
            }
        }

        if (hitType == 0) return false;

        hitPoint = add(ro, mul(rd, hitT));

        if (hitType == 1) {
            hitNormal = norm(sub(hitPoint, sphereCenter[hitIdx]));
            hitColor = sphereColor[hitIdx];
            hitRefl = sphereRefl[hitIdx];
            hitSpecExp = sphereSpec[hitIdx];
        } else {
            hitNormal = vec(0, 1, 0);
            // Checkerboard
            double fx = hitPoint[0] < 0 ? Math.floor(hitPoint[0]) - 1 : Math.floor(hitPoint[0]);
            double fz = hitPoint[2] < 0 ? Math.floor(hitPoint[2]) - 1 : Math.floor(hitPoint[2]);
            int check = (((int) fx) + ((int) fz)) & 1;
            hitColor = check == 0 ? vec(0.8, 0.8, 0.8) : vec(0.3, 0.3, 0.3);
            hitRefl = GROUND_REFL;
            hitSpecExp = GROUND_SPEC;
        }
        return true;
    }

    static boolean shadowHit(double[] ro, double[] rd, double maxDist) {
        // Spheres
        for (int i = 0; i < NUM_SPHERES; i++) {
            double[] oc = sub(ro, sphereCenter[i]);
            double b = dot(oc, rd);
            double c = dot(oc, oc) - sphereRadius[i] * sphereRadius[i];
            double disc = b * b - c;
            if (disc > 0) {
                double sqrtDisc = Math.sqrt(disc);
                double t = -b - sqrtDisc;
                if (t > EPSILON && t < maxDist) return true;
                t = -b + sqrtDisc;
                if (t > EPSILON && t < maxDist) return true;
            }
        }
        // Ground
        if (Math.abs(rd[1]) > EPSILON) {
            double t = (GROUND_Y - ro[1]) / rd[1];
            if (t > EPSILON && t < maxDist) return true;
        }
        return false;
    }

    static double[] trace(double[] ro, double[] rd, int depth) {
        if (depth > MAX_DEPTH) {
            return sky(rd);
        }

        if (!intersectScene(ro, rd)) {
            return sky(rd);
        }

        // Save hit data (since recursive calls overwrite statics)
        double[] hp = hitPoint.clone();
        double[] hn = hitNormal.clone();
        double[] hc = hitColor.clone();
        double hr = hitRefl;
        double hse = hitSpecExp;

        // Phong lighting
        double[] local = vec(hc[0] * AMBIENT, hc[1] * AMBIENT, hc[2] * AMBIENT);

        for (int l = 0; l < NUM_LIGHTS; l++) {
            double[] toLight = sub(lightPos[l], hp);
            double dist = len(toLight);
            double[] ldir = mul(toLight, 1.0 / dist);

            // Shadow
            if (shadowHit(add(hp, mul(hn, EPSILON)), ldir, dist)) continue;

            double nDotL = dot(hn, ldir);
            if (nDotL > 0) {
                // Diffuse
                double diff = nDotL * lightInt[l];
                local[0] += hc[0] * diff;
                local[1] += hc[1] * diff;
                local[2] += hc[2] * diff;

                // Specular (white)
                double[] reflDir = reflect(mul(ldir, -1), hn);
                double specAngle = Math.max(0, dot(mul(rd, -1), reflDir));
                double spec = Math.pow(specAngle, hse) * lightInt[l];
                local[0] += spec;
                local[1] += spec;
                local[2] += spec;
            }
        }

        // Reflection
        if (hr > 0 && depth < MAX_DEPTH) {
            double[] reflDir = reflect(rd, hn);
            double[] reflColor = trace(add(hp, mul(hn, EPSILON)), reflDir, depth + 1);
            local[0] = local[0] * (1 - hr) + reflColor[0] * hr;
            local[1] = local[1] * (1 - hr) + reflColor[1] * hr;
            local[2] = local[2] * (1 - hr) + reflColor[2] * hr;
        }

        return local;
    }

    static double[] sky(double[] rd) {
        double t = 0.5 * (rd[1] + 1);
        return vec(1 - t + 0.5 * t, 1 - t + 0.7 * t, 1 - t + 1.0 * t);
    }

    static int toByte(double v) {
        v = Math.pow(Math.max(0, Math.min(1, v)), 1.0 / 2.2);
        return (int)(v * 255 + 0.5);
    }

    public static void main(String[] args) throws IOException {
        int width = Integer.parseInt(args[0]);
        int height = Integer.parseInt(args[1]);

        // Camera
        double[] camPos = vec(0, 1.5, -5);
        double[] lookAt = vec(0, 0.5, 0);
        double[] up = vec(0, 1, 0);
        double fov = 60.0;

        double fovRad = fov * Math.PI / 180.0;
        double halfH = Math.tan(fovRad / 2);
        double aspect = (double) width / height;
        double halfW = aspect * halfH;

        double[] forward = norm(sub(lookAt, camPos));
        double[] right = norm(cross(forward, up));
        double[] camUp = cross(right, forward);

        BufferedOutputStream out = new BufferedOutputStream(System.out, 1 << 20);
        byte[] header = ("P6\n" + width + " " + height + "\n255\n").getBytes();
        out.write(header);

        byte[] row = new byte[width * 3];
        for (int j = 0; j < height; j++) {
            for (int i = 0; i < width; i++) {
                double u = (2.0 * ((i + 0.5) / width) - 1.0) * halfW;
                double v = (1.0 - 2.0 * ((j + 0.5) / height)) * halfH;
                double[] dir = norm(add(add(forward, mul(right, u)), mul(camUp, v)));

                double[] color = trace(camPos, dir, 0);

                int idx = i * 3;
                row[idx]     = (byte) toByte(color[0]);
                row[idx + 1] = (byte) toByte(color[1]);
                row[idx + 2] = (byte) toByte(color[2]);
            }
            out.write(row);
        }
        out.flush();
    }
}
