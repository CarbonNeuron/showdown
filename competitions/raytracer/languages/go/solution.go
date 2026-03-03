package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
)

// ---------- Vector ----------

type Vec3 struct {
	X, Y, Z float64
}

func (a Vec3) Add(b Vec3) Vec3    { return Vec3{a.X + b.X, a.Y + b.Y, a.Z + b.Z} }
func (a Vec3) Sub(b Vec3) Vec3    { return Vec3{a.X - b.X, a.Y - b.Y, a.Z - b.Z} }
func (a Vec3) Mul(s float64) Vec3 { return Vec3{a.X * s, a.Y * s, a.Z * s} }
func (a Vec3) MulVec(b Vec3) Vec3 { return Vec3{a.X * b.X, a.Y * b.Y, a.Z * b.Z} }
func (a Vec3) Dot(b Vec3) float64 { return a.X*b.X + a.Y*b.Y + a.Z*b.Z }
func (a Vec3) Cross(b Vec3) Vec3 {
	return Vec3{a.Y*b.Z - a.Z*b.Y, a.Z*b.X - a.X*b.Z, a.X*b.Y - a.Y*b.X}
}
func (a Vec3) Len() float64        { return math.Sqrt(a.Dot(a)) }
func (a Vec3) Norm() Vec3          { l := a.Len(); return Vec3{a.X / l, a.Y / l, a.Z / l} }
func (a Vec3) Neg() Vec3           { return Vec3{-a.X, -a.Y, -a.Z} }
func (a Vec3) AddScaled(b Vec3, t float64) Vec3 {
	return Vec3{a.X + b.X*t, a.Y + b.Y*t, a.Z + b.Z*t}
}

// ---------- Ray ----------

type Ray struct {
	Origin, Dir Vec3
}

func (r Ray) At(t float64) Vec3 { return r.Origin.AddScaled(r.Dir, t) }

// ---------- Material ----------

type Material struct {
	Color        Vec3
	Reflectivity float64
	Specular     float64
}

// ---------- Sphere ----------

type Sphere struct {
	Center   Vec3
	Radius   float64
	Material Material
}

func (s *Sphere) Intersect(r Ray) (float64, bool) {
	oc := r.Origin.Sub(s.Center)
	a := r.Dir.Dot(r.Dir)
	b := oc.Dot(r.Dir)
	c := oc.Dot(oc) - s.Radius*s.Radius
	disc := b*b - a*c
	if disc < 0 {
		return 0, false
	}
	sqrtDisc := math.Sqrt(disc)
	t := (-b - sqrtDisc) / a
	if t > 1e-6 {
		return t, true
	}
	t = (-b + sqrtDisc) / a
	if t > 1e-6 {
		return t, true
	}
	return 0, false
}

func (s *Sphere) NormalAt(p Vec3) Vec3 {
	return p.Sub(s.Center).Mul(1.0 / s.Radius)
}

// ---------- Plane (ground, y=0) ----------

type Plane struct {
	Y            float64
	Reflectivity float64
	Specular     float64
}

func (p *Plane) Intersect(r Ray) (float64, bool) {
	if math.Abs(r.Dir.Y) < 1e-12 {
		return 0, false
	}
	t := (p.Y - r.Origin.Y) / r.Dir.Y
	if t > 1e-6 {
		return t, true
	}
	return 0, false
}

func (p *Plane) ColorAt(point Vec3) Vec3 {
	fx := math.Floor(point.X)
	fz := math.Floor(point.Z)
	ix := int(fx)
	iz := int(fz)
	// handle negative coordinates properly
	if point.X < 0 {
		ix -= 1
	}
	if point.Z < 0 {
		iz -= 1
	}
	if (ix+iz)%2 == 0 {
		return Vec3{0.8, 0.8, 0.8}
	}
	return Vec3{0.3, 0.3, 0.3}
}

// ---------- Light ----------

type Light struct {
	Position  Vec3
	Intensity float64
}

// ---------- Scene ----------

var spheres = []Sphere{
	{Vec3{-2, 1, 0}, 1.0, Material{Vec3{0.9, 0.2, 0.2}, 0.3, 50}},
	{Vec3{0, 0.75, 0}, 0.75, Material{Vec3{0.2, 0.9, 0.2}, 0.2, 30}},
	{Vec3{2, 1, 0}, 1.0, Material{Vec3{0.2, 0.2, 0.9}, 0.4, 80}},
	{Vec3{-0.75, 0.4, -1.5}, 0.4, Material{Vec3{0.9, 0.9, 0.2}, 0.5, 100}},
	{Vec3{1.5, 0.5, -1}, 0.5, Material{Vec3{0.9, 0.2, 0.9}, 0.6, 60}},
}

var ground = Plane{0, 0.3, 0}

var lights = []Light{
	{Vec3{-3, 5, -3}, 0.7},
	{Vec3{3, 3, -1}, 0.4},
}

const ambient = 0.1
const maxDepth = 5
const gamma = 2.2

// ---------- Hit record ----------

type HitType int

const (
	HitNone HitType = iota
	HitSphere
	HitPlane
)

type Hit struct {
	T        float64
	Point    Vec3
	Normal   Vec3
	Color    Vec3
	Reflect  float64
	Specular float64
	Type     HitType
}

func traceScene(r Ray) (Hit, bool) {
	var closest Hit
	closest.T = math.MaxFloat64
	found := false

	for i := range spheres {
		if t, ok := spheres[i].Intersect(r); ok && t < closest.T {
			p := r.At(t)
			closest = Hit{
				T:        t,
				Point:    p,
				Normal:   spheres[i].NormalAt(p),
				Color:    spheres[i].Material.Color,
				Reflect:  spheres[i].Material.Reflectivity,
				Specular: spheres[i].Material.Specular,
				Type:     HitSphere,
			}
			found = true
		}
	}

	if t, ok := ground.Intersect(r); ok && t < closest.T {
		p := r.At(t)
		closest = Hit{
			T:        t,
			Point:    p,
			Normal:   Vec3{0, 1, 0},
			Color:    ground.ColorAt(p),
			Reflect:  ground.Reflectivity,
			Specular: ground.Specular,
			Type:     HitPlane,
		}
		found = true
	}

	return closest, found
}

func inShadow(point, lightPos Vec3) bool {
	dir := lightPos.Sub(point)
	dist := dir.Len()
	r := Ray{point.AddScaled(dir.Norm(), 1e-4), dir.Norm()}

	for i := range spheres {
		if t, ok := spheres[i].Intersect(r); ok && t < dist {
			return true
		}
	}

	// check ground plane shadow
	if t, ok := ground.Intersect(r); ok && t < dist {
		return true
	}

	return false
}

func shade(r Ray, hit Hit, depth int) Vec3 {
	// Ambient
	color := hit.Color.Mul(ambient)

	viewDir := r.Dir.Neg().Norm()

	for i := range lights {
		lDir := lights[i].Position.Sub(hit.Point)
		lDist := lDir.Len()
		_ = lDist
		lDir = lDir.Norm()

		// Shadow check
		if inShadow(hit.Point.AddScaled(hit.Normal, 1e-4), lights[i].Position) {
			continue
		}

		// Diffuse
		diff := math.Max(0, hit.Normal.Dot(lDir))
		color = color.Add(hit.Color.Mul(diff * lights[i].Intensity))

		// Specular
		if hit.Specular > 0 {
			reflDir := hit.Normal.Mul(2 * hit.Normal.Dot(lDir)).Sub(lDir).Norm()
			spec := math.Pow(math.Max(0, viewDir.Dot(reflDir)), hit.Specular)
			color = color.Add(Vec3{1, 1, 1}.Mul(spec * lights[i].Intensity))
		}
	}

	// Reflection
	if hit.Reflect > 0 && depth < maxDepth {
		reflDir := r.Dir.Sub(hit.Normal.Mul(2 * r.Dir.Dot(hit.Normal))).Norm()
		reflRay := Ray{hit.Point.AddScaled(hit.Normal, 1e-4), reflDir}
		reflColor := trace(reflRay, depth+1)
		color = color.Mul(1 - hit.Reflect).Add(reflColor.Mul(hit.Reflect))
	}

	return color
}

func trace(r Ray, depth int) Vec3 {
	hit, found := traceScene(r)
	if !found {
		// Sky gradient
		t := 0.5 * (r.Dir.Norm().Y + 1.0)
		return Vec3{1, 1, 1}.Mul(1 - t).Add(Vec3{0.5, 0.7, 1.0}.Mul(t))
	}
	return shade(r, hit, depth)
}

func clamp(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return v
}

func toByte(v float64) byte {
	// Gamma correction then convert
	g := math.Pow(clamp(v), 1.0/gamma)
	return byte(g*255.0 + 0.5)
}

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: solution WIDTH HEIGHT\n")
		os.Exit(1)
	}
	width, err := strconv.Atoi(os.Args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid width: %s\n", os.Args[1])
		os.Exit(1)
	}
	height, err := strconv.Atoi(os.Args[2])
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid height: %s\n", os.Args[2])
		os.Exit(1)
	}

	// Camera setup
	camPos := Vec3{0, 1.5, -5}
	lookAt := Vec3{0, 0.5, 0}
	up := Vec3{0, 1, 0}
	fov := 60.0

	forward := lookAt.Sub(camPos).Norm()
	right := forward.Cross(up).Norm()
	camUp := right.Cross(forward).Norm()

	aspectRatio := float64(width) / float64(height)
	halfH := math.Tan(fov * math.Pi / 360.0) // tan(fov/2)
	halfW := halfH * aspectRatio

	// Allocate pixel buffer
	pixels := make([]byte, width*height*3)

	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			// Map pixel to [-1, 1] range
			u := (2.0*(float64(x)+0.5)/float64(width) - 1.0) * halfW
			v := (1.0 - 2.0*(float64(y)+0.5)/float64(height)) * halfH

			dir := forward.Add(right.Mul(u)).Add(camUp.Mul(v)).Norm()
			r := Ray{camPos, dir}
			color := trace(r, 0)

			idx := (y*width + x) * 3
			pixels[idx] = toByte(color.X)
			pixels[idx+1] = toByte(color.Y)
			pixels[idx+2] = toByte(color.Z)
		}
	}

	// Write PPM P6
	w := bufio.NewWriter(os.Stdout)
	fmt.Fprintf(w, "P6\n%d %d\n255\n", width, height)
	w.Write(pixels)
	w.Flush()
}
