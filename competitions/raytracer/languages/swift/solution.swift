import Foundation

struct Vec3 {
    var x: Double
    var y: Double
    var z: Double

    static func +(a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x+b.x, y: a.y+b.y, z: a.z+b.z) }
    static func -(a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x-b.x, y: a.y-b.y, z: a.z-b.z) }
    static func *(a: Vec3, s: Double) -> Vec3 { Vec3(x: a.x*s, y: a.y*s, z: a.z*s) }
    static func *(s: Double, a: Vec3) -> Vec3 { a * s }
    static func *(a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x*b.x, y: a.y*b.y, z: a.z*b.z) }

    func dot(_ b: Vec3) -> Double { x*b.x + y*b.y + z*b.z }
    func length() -> Double { sqrt(dot(self)) }
    func norm() -> Vec3 {
        let l = length()
        return l > 0 ? self * (1.0/l) : self
    }
    func reflect(_ n: Vec3) -> Vec3 {
        self - n * (2.0 * self.dot(n))
    }
    func clamped() -> Vec3 {
        Vec3(x: min(max(x,0),1), y: min(max(y,0),1), z: min(max(z,0),1))
    }
}

func cross(_ a: Vec3, _ b: Vec3) -> Vec3 {
    Vec3(x: a.y*b.z - a.z*b.y, y: a.z*b.x - a.x*b.z, z: a.x*b.y - a.y*b.x)
}

struct Ray {
    var origin: Vec3
    var dir: Vec3
}

struct Sphere {
    var center: Vec3
    var radius: Double
    var color: Vec3
    var reflectivity: Double
    var specular: Double
}

struct Light {
    var pos: Vec3
    var intensity: Double
}

struct Hit {
    var t: Double
    var point: Vec3
    var normal: Vec3
    var color: Vec3
    var reflectivity: Double
    var specular: Double
}

let spheres: [Sphere] = [
    Sphere(center: Vec3(x:-2, y:1, z:0), radius:1.0, color:Vec3(x:0.9,y:0.2,z:0.2), reflectivity:0.3, specular:50),
    Sphere(center: Vec3(x:0, y:0.75, z:0), radius:0.75, color:Vec3(x:0.2,y:0.9,z:0.2), reflectivity:0.2, specular:30),
    Sphere(center: Vec3(x:2, y:1, z:0), radius:1.0, color:Vec3(x:0.2,y:0.2,z:0.9), reflectivity:0.4, specular:80),
    Sphere(center: Vec3(x:-0.75, y:0.4, z:-1.5), radius:0.4, color:Vec3(x:0.9,y:0.9,z:0.2), reflectivity:0.5, specular:100),
    Sphere(center: Vec3(x:1.5, y:0.5, z:-1), radius:0.5, color:Vec3(x:0.9,y:0.2,z:0.9), reflectivity:0.6, specular:60),
]

let lights: [Light] = [
    Light(pos: Vec3(x:-3, y:5, z:-3), intensity: 0.7),
    Light(pos: Vec3(x:3, y:3, z:-1), intensity: 0.4),
]

let ambient = 0.1

func intersectSphere(_ ray: Ray, _ s: Sphere) -> Double? {
    let oc = ray.origin - s.center
    let a = ray.dir.dot(ray.dir)
    let b = 2.0 * oc.dot(ray.dir)
    let c = oc.dot(oc) - s.radius * s.radius
    let disc = b*b - 4*a*c
    if disc < 0 { return nil }
    let sq = sqrt(disc)
    let t1 = (-b - sq) / (2*a)
    if t1 > 1e-4 { return t1 }
    let t2 = (-b + sq) / (2*a)
    if t2 > 1e-4 { return t2 }
    return nil
}

func intersectGround(_ ray: Ray) -> Double? {
    if abs(ray.dir.y) < 1e-8 { return nil }
    let t = -ray.origin.y / ray.dir.y
    return t > 1e-4 ? t : nil
}

func checkerboard(_ p: Vec3) -> Vec3 {
    let fx = p.x < 0 ? floor(p.x) - 1 : floor(p.x)
    let fz = p.z < 0 ? floor(p.z) - 1 : floor(p.z)
    let check = (Int(fx) + Int(fz)) & 1
    return check == 0 ? Vec3(x:0.8, y:0.8, z:0.8) : Vec3(x:0.3, y:0.3, z:0.3)
}

func findHit(_ ray: Ray) -> Hit? {
    var closest: Hit? = nil
    var bestT = Double.infinity

    for s in spheres {
        if let t = intersectSphere(ray, s), t < bestT {
            bestT = t
            let p = ray.origin + ray.dir * t
            let n = (p - s.center).norm()
            closest = Hit(t: t, point: p, normal: n, color: s.color, reflectivity: s.reflectivity, specular: s.specular)
        }
    }

    if let t = intersectGround(ray), t < bestT {
        bestT = t
        let p = ray.origin + ray.dir * t
        let n = Vec3(x:0, y:1, z:0)
        let col = checkerboard(p)
        closest = Hit(t: t, point: p, normal: n, color: col, reflectivity: 0.3, specular: 10)
    }

    return closest
}

func inShadow(_ point: Vec3, _ lightPos: Vec3) -> Bool {
    let toLight = lightPos - point
    let dist = toLight.length()
    let dir = toLight * (1.0/dist)
    let shadowRay = Ray(origin: point + dir * 1e-3, dir: dir)

    for s in spheres {
        if let t = intersectSphere(shadowRay, s), t < dist {
            return true
        }
    }

    if let t = intersectGround(shadowRay), t < dist {
        return true
    }

    return false
}

func sky(_ dir: Vec3) -> Vec3 {
    let t = 0.5 * (dir.norm().y + 1.0)
    return Vec3(x:1,y:1,z:1) * (1.0-t) + Vec3(x:0.5,y:0.7,z:1.0) * t
}

func trace(_ ray: Ray, _ depth: Int) -> Vec3 {
    if depth >= 5 { return sky(ray.dir) }

    guard let hit = findHit(ray) else {
        return sky(ray.dir)
    }

    // Ambient
    var local = hit.color * ambient

    // For each light
    for light in lights {
        if inShadow(hit.point, light.pos) { continue }

        let toLight = (light.pos - hit.point).norm()
        let nDotL = hit.normal.dot(toLight)

        if nDotL > 0 {
            // Diffuse
            local = local + hit.color * (nDotL * light.intensity)

            // Specular (white)
            let viewDir = (ray.origin - hit.point).norm()
            let halfVec = (toLight + viewDir).norm()
            let specAngle = max(hit.normal.dot(halfVec), 0)
            let spec = pow(specAngle, hit.specular) * light.intensity
            local = local + Vec3(x:1,y:1,z:1) * spec
        }
    }

    // Reflection
    if hit.reflectivity > 0 {
        let reflDir = ray.dir.reflect(hit.normal).norm()
        let reflRay = Ray(origin: hit.point + reflDir * 1e-3, dir: reflDir)
        let reflColor = trace(reflRay, depth + 1)
        return local * (1.0 - hit.reflectivity) + reflColor * hit.reflectivity
    }

    return local
}

// Main
let args = CommandLine.arguments
guard args.count >= 3,
      let width = Int(args[1]),
      let height = Int(args[2]) else {
    fatalError("Usage: solution <width> <height>")
}

let camPos = Vec3(x:0, y:1.5, z:-5)
let lookAt = Vec3(x:0, y:0.5, z:0)
let up = Vec3(x:0, y:1, z:0)
let fov = 60.0
let aspectRatio = Double(width) / Double(height)
let fovRad = fov * .pi / 180.0
let halfH = tan(fovRad / 2.0)
let halfW = halfH * aspectRatio

let forward = (lookAt - camPos).norm()
let right = cross(forward, up).norm()
let camUp = cross(right, forward).norm()

// Build PPM header
let header = "P6\n\(width) \(height)\n255\n"
var data = [UInt8](header.utf8)
data.reserveCapacity(data.count + width * height * 3)

for j in 0..<height {
    for i in 0..<width {
        let u = (2.0 * (Double(i) + 0.5) / Double(width) - 1.0) * halfW
        let v = (1.0 - 2.0 * (Double(j) + 0.5) / Double(height)) * halfH

        let dir = (forward + right * u + camUp * v).norm()
        let ray = Ray(origin: camPos, dir: dir)
        let color = trace(ray, 0).clamped()

        let r = pow(color.x, 1.0/2.2)
        let g = pow(color.y, 1.0/2.2)
        let b = pow(color.z, 1.0/2.2)

        data.append(UInt8(r * 255.0 + 0.5))
        data.append(UInt8(g * 255.0 + 0.5))
        data.append(UInt8(b * 255.0 + 0.5))
    }
}

data.withUnsafeBufferPointer { ptr in
    let rawPtr = UnsafeRawBufferPointer(ptr)
    let fileData = Data(rawPtr)
    FileHandle.standardOutput.write(fileData)
}
