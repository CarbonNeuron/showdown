using System;
using System.IO;
using System.Runtime.CompilerServices;

// Single-threaded raytracer for PPM P6 output.
// Scene: 5 spheres on a checkerboard ground plane, 2 point lights, Phong shading,
// hard shadows, recursive reflections (max depth 5), gamma 2.2.

struct Vec3
{
    public double X, Y, Z;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public Vec3(double x, double y, double z)
    {
        X = x; Y = y; Z = z;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Vec3 operator +(Vec3 a, Vec3 b) =>
        new Vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Vec3 operator -(Vec3 a, Vec3 b) =>
        new Vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Vec3 operator *(Vec3 a, double s) =>
        new Vec3(a.X * s, a.Y * s, a.Z * s);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Vec3 operator *(double s, Vec3 a) =>
        new Vec3(a.X * s, a.Y * s, a.Z * s);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Vec3 operator -(Vec3 a) =>
        new Vec3(-a.X, -a.Y, -a.Z);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public double Dot(Vec3 b) => X * b.X + Y * b.Y + Z * b.Z;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public Vec3 Cross(Vec3 b) =>
        new Vec3(Y * b.Z - Z * b.Y, Z * b.X - X * b.Z, X * b.Y - Y * b.X);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public double Length() => Math.Sqrt(X * X + Y * Y + Z * Z);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public Vec3 Normalize()
    {
        double len = Length();
        double inv = 1.0 / len;
        return new Vec3(X * inv, Y * inv, Z * inv);
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public Vec3 Reflect(Vec3 normal)
    {
        double d = 2.0 * this.Dot(normal);
        return new Vec3(X - normal.X * d, Y - normal.Y * d, Z - normal.Z * d);
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Clamp01(double x)
    {
        if (x < 0.0) return 0.0;
        if (x > 1.0) return 1.0;
        return x;
    }
}

struct Ray
{
    public Vec3 Origin;
    public Vec3 Dir;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public Ray(Vec3 origin, Vec3 dir)
    {
        Origin = origin;
        Dir = dir;
    }
}

struct Sphere
{
    public Vec3 Center;
    public double Radius;
    public Vec3 Color;
    public double Reflectivity;
    public double Specular;

    public Sphere(Vec3 center, double radius, Vec3 color, double reflectivity, double specular)
    {
        Center = center;
        Radius = radius;
        Color = color;
        Reflectivity = reflectivity;
        Specular = specular;
    }
}

struct PointLight
{
    public Vec3 Position;
    public double Intensity;

    public PointLight(Vec3 position, double intensity)
    {
        Position = position;
        Intensity = intensity;
    }
}

struct HitInfo
{
    public bool Hit;
    public double T;
    public Vec3 Point;
    public Vec3 Normal;
    public Vec3 Color;
    public double Reflectivity;
    public double Specular;
}

static class Raytracer
{
    const double Epsilon = 1e-6;
    const double Inf = 1e20;
    const int MaxDepth = 5;
    const double Ambient = 0.1;
    const double GroundY = 0.0;
    const double GroundReflect = 0.3;
    const double GroundSpecular = 10.0;
    const double CheckSize = 1.0;

    static Sphere[] spheres;
    static PointLight[] lights;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    static double IntersectSphere(ref Ray r, ref Sphere s)
    {
        Vec3 oc = r.Origin - s.Center;
        double b = oc.Dot(r.Dir);
        double c = oc.Dot(oc) - s.Radius * s.Radius;
        double disc = b * b - c;
        if (disc < 0.0) return Inf;
        double sq = Math.Sqrt(disc);
        double t1 = -b - sq;
        if (t1 > Epsilon) return t1;
        double t2 = -b + sq;
        if (t2 > Epsilon) return t2;
        return Inf;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    static double IntersectGround(ref Ray r)
    {
        if (Math.Abs(r.Dir.Y) < Epsilon) return Inf;
        double t = (GroundY - r.Origin.Y) / r.Dir.Y;
        return t > Epsilon ? t : Inf;
    }

    static HitInfo SceneIntersect(ref Ray r)
    {
        HitInfo best = default;
        best.Hit = false;
        best.T = Inf;

        // Spheres
        for (int i = 0; i < spheres.Length; i++)
        {
            double t = IntersectSphere(ref r, ref spheres[i]);
            if (t < best.T)
            {
                best.Hit = true;
                best.T = t;
                best.Point = r.Origin + r.Dir * t;
                best.Normal = (best.Point - spheres[i].Center).Normalize();
                best.Color = spheres[i].Color;
                best.Reflectivity = spheres[i].Reflectivity;
                best.Specular = spheres[i].Specular;
            }
        }

        // Ground plane
        double tg = IntersectGround(ref r);
        if (tg < best.T)
        {
            best.Hit = true;
            best.T = tg;
            best.Point = r.Origin + r.Dir * tg;
            best.Normal = new Vec3(0.0, 1.0, 0.0);

            // Checkerboard - match reference: shift negative coords by -1
            double px = best.Point.X / CheckSize;
            double pz = best.Point.Z / CheckSize;
            double fx = px < 0.0 ? Math.Floor(px - 1.0) : Math.Floor(px);
            double fz = pz < 0.0 ? Math.Floor(pz - 1.0) : Math.Floor(pz);
            int check = ((int)fx + (int)fz) & 1;
            if (check != 0)
                best.Color = new Vec3(0.3, 0.3, 0.3);
            else
                best.Color = new Vec3(0.8, 0.8, 0.8);

            best.Reflectivity = GroundReflect;
            best.Specular = GroundSpecular;
        }

        return best;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    static bool InShadow(Vec3 point, Vec3 lightDir, double lightDist)
    {
        Ray shadowRay = new Ray(point, lightDir);

        // Check spheres
        for (int i = 0; i < spheres.Length; i++)
        {
            double t = IntersectSphere(ref shadowRay, ref spheres[i]);
            if (t < lightDist) return true;
        }

        // Check ground plane
        double tg = IntersectGround(ref shadowRay);
        if (tg < lightDist) return true;

        return false;
    }

    static Vec3 Shade(ref HitInfo h, ref Ray r, int depth)
    {
        Vec3 result = h.Color * Ambient;

        Vec3 offsetPoint = h.Point + h.Normal * Epsilon;

        for (int i = 0; i < lights.Length; i++)
        {
            Vec3 toLight = lights[i].Position - h.Point;
            double dist = toLight.Length();
            Vec3 lightDir = toLight * (1.0 / dist);

            if (InShadow(offsetPoint, lightDir, dist))
                continue;

            // Diffuse
            double nDotL = h.Normal.Dot(lightDir);
            if (nDotL > 0.0)
            {
                result = result + h.Color * (nDotL * lights[i].Intensity);

                // Specular (Phong) - WHITE specular highlight
                Vec3 reflDir = (-lightDir).Reflect(h.Normal);
                Vec3 viewDir = -r.Dir;
                double specDot = viewDir.Dot(reflDir);
                if (specDot > 0.0)
                {
                    double spec = Math.Pow(specDot, h.Specular) * lights[i].Intensity;
                    result = result + new Vec3(spec, spec, spec);
                }
            }
        }

        // Reflections
        if (depth < MaxDepth && h.Reflectivity > 0.0)
        {
            Vec3 reflDir = r.Dir.Reflect(h.Normal);
            Ray reflRay = new Ray(offsetPoint, reflDir);
            Vec3 reflColor = Trace(ref reflRay, depth + 1);
            result = result * (1.0 - h.Reflectivity) + reflColor * h.Reflectivity;
        }

        return result;
    }

    static Vec3 Trace(ref Ray r, int depth)
    {
        HitInfo h = SceneIntersect(ref r);
        if (!h.Hit)
        {
            // Sky gradient
            double t = 0.5 * (r.Dir.Normalize().Y + 1.0);
            return new Vec3(1.0, 1.0, 1.0) * (1.0 - t) + new Vec3(0.5, 0.7, 1.0) * t;
        }
        return Shade(ref h, ref r, depth);
    }

    static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.Error.WriteLine("Usage: solution WIDTH HEIGHT");
            return 1;
        }

        int width = int.Parse(args[0]);
        int height = int.Parse(args[1]);
        if (width <= 0 || height <= 0)
        {
            Console.Error.WriteLine("Invalid dimensions");
            return 1;
        }

        // Scene setup
        spheres = new Sphere[]
        {
            new Sphere(new Vec3(-2.0, 1.0, 0.0),   1.0,  new Vec3(0.9, 0.2, 0.2), 0.3, 50.0),
            new Sphere(new Vec3(0.0, 0.75, 0.0),    0.75, new Vec3(0.2, 0.9, 0.2), 0.2, 30.0),
            new Sphere(new Vec3(2.0, 1.0, 0.0),     1.0,  new Vec3(0.2, 0.2, 0.9), 0.4, 80.0),
            new Sphere(new Vec3(-0.75, 0.4, -1.5),  0.4,  new Vec3(0.9, 0.9, 0.2), 0.5, 100.0),
            new Sphere(new Vec3(1.5, 0.5, -1.0),    0.5,  new Vec3(0.9, 0.2, 0.9), 0.6, 60.0),
        };

        lights = new PointLight[]
        {
            new PointLight(new Vec3(-3.0, 5.0, -3.0), 0.7),
            new PointLight(new Vec3(3.0, 3.0, -1.0),  0.4),
        };

        // Camera setup
        Vec3 camPos = new Vec3(0.0, 1.5, -5.0);
        Vec3 lookAt = new Vec3(0.0, 0.5, 0.0);
        Vec3 up = new Vec3(0.0, 1.0, 0.0);
        double fovDeg = 60.0;

        Vec3 forward = (lookAt - camPos).Normalize();
        Vec3 right = forward.Cross(up).Normalize();
        Vec3 camUp = right.Cross(forward).Normalize();

        double aspect = (double)width / (double)height;
        double fovRad = fovDeg * Math.PI / 180.0;
        double halfHeight = Math.Tan(fovRad / 2.0);
        double halfWidth = aspect * halfHeight;

        double invGamma = 1.0 / 2.2;

        // Allocate pixel buffer
        int bufSize = width * height * 3;
        byte[] pixels = new byte[bufSize];

        // Render
        int idx = 0;
        for (int j = 0; j < height; j++)
        {
            double v = (1.0 - 2.0 * ((j + 0.5) / height)) * halfHeight;
            for (int i = 0; i < width; i++)
            {
                double u = (2.0 * ((i + 0.5) / width) - 1.0) * halfWidth;
                Vec3 direction = (forward + right * u + camUp * v).Normalize();
                Ray ray = new Ray(camPos, direction);

                Vec3 color = Trace(ref ray, 0);

                // Gamma correction
                double cr = Math.Pow(Vec3.Clamp01(color.X), invGamma);
                double cg = Math.Pow(Vec3.Clamp01(color.Y), invGamma);
                double cb = Math.Pow(Vec3.Clamp01(color.Z), invGamma);

                pixels[idx++] = (byte)(cr * 255.0 + 0.5);
                pixels[idx++] = (byte)(cg * 255.0 + 0.5);
                pixels[idx++] = (byte)(cb * 255.0 + 0.5);
            }
        }

        // Write PPM P6 to stdout in binary mode
        using (Stream stdout = Console.OpenStandardOutput())
        using (BufferedStream bstdout = new BufferedStream(stdout, 1 << 16))
        {
            // Write header as ASCII bytes
            byte[] header = System.Text.Encoding.ASCII.GetBytes(
                "P6\n" + width + " " + height + "\n255\n");
            bstdout.Write(header, 0, header.Length);

            // Write pixel data
            bstdout.Write(pixels, 0, pixels.Length);
            bstdout.Flush();
        }

        return 0;
    }
}
