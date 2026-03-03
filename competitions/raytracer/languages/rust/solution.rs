use std::env;
use std::io::{self, BufWriter, Write};

#[derive(Clone, Copy)]
struct Vec3 {
    x: f64,
    y: f64,
    z: f64,
}

impl Vec3 {
    #[inline(always)]
    fn new(x: f64, y: f64, z: f64) -> Self {
        Self { x, y, z }
    }

    #[inline(always)]
    fn add(self, other: Self) -> Self {
        Self::new(self.x + other.x, self.y + other.y, self.z + other.z)
    }

    #[inline(always)]
    fn sub(self, other: Self) -> Self {
        Self::new(self.x - other.x, self.y - other.y, self.z - other.z)
    }

    #[inline(always)]
    fn mul(self, s: f64) -> Self {
        Self::new(self.x * s, self.y * s, self.z * s)
    }

    #[inline(always)]
    fn dot(self, other: Self) -> f64 {
        self.x * other.x + self.y * other.y + self.z * other.z
    }

    #[inline(always)]
    fn cross(self, other: Self) -> Self {
        Self::new(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        )
    }

    #[inline(always)]
    fn length(self) -> f64 {
        self.dot(self).sqrt()
    }

    #[inline(always)]
    fn normalize(self) -> Self {
        let len = self.length();
        if len > 0.0 {
            self.mul(1.0 / len)
        } else {
            self
        }
    }

    #[inline(always)]
    fn reflect(self, normal: Self) -> Self {
        self.sub(normal.mul(2.0 * self.dot(normal)))
    }

    #[inline(always)]
    fn clamp(self) -> Self {
        Self::new(
            self.x.max(0.0).min(1.0),
            self.y.max(0.0).min(1.0),
            self.z.max(0.0).min(1.0),
        )
    }

    #[inline(always)]
    fn gamma_correct(self, gamma: f64) -> Self {
        let inv = 1.0 / gamma;
        Self::new(self.x.powf(inv), self.y.powf(inv), self.z.powf(inv))
    }
}

struct Ray {
    origin: Vec3,
    direction: Vec3,
}

struct Sphere {
    center: Vec3,
    radius: f64,
    color: Vec3,
    reflectivity: f64,
    specular: f64,
}

struct PointLight {
    position: Vec3,
    intensity: f64,
}

struct HitRecord {
    point: Vec3,
    normal: Vec3,
    color: Vec3,
    reflectivity: f64,
    specular: f64,
}

const EPSILON: f64 = 1e-6;
const MAX_DEPTH: i32 = 5;
const GAMMA: f64 = 2.2;
const AMBIENT: f64 = 0.1;

#[inline(always)]
fn intersect_sphere(ray: &Ray, sphere: &Sphere) -> Option<f64> {
    let oc = ray.origin.sub(sphere.center);
    let a = ray.direction.dot(ray.direction);
    let b = 2.0 * oc.dot(ray.direction);
    let c = oc.dot(oc) - sphere.radius * sphere.radius;
    let discriminant = b * b - 4.0 * a * c;
    if discriminant < 0.0 {
        return None;
    }
    let sqrt_disc = discriminant.sqrt();
    let t1 = (-b - sqrt_disc) / (2.0 * a);
    if t1 > EPSILON {
        return Some(t1);
    }
    let t2 = (-b + sqrt_disc) / (2.0 * a);
    if t2 > EPSILON {
        return Some(t2);
    }
    None
}

#[inline(always)]
fn intersect_plane(ray: &Ray) -> Option<f64> {
    // Ground plane at y = 0, normal (0, 1, 0)
    if ray.direction.y.abs() < EPSILON {
        return None;
    }
    let t = -ray.origin.y / ray.direction.y;
    if t > EPSILON {
        Some(t)
    } else {
        None
    }
}

#[inline(always)]
fn checkerboard_color(point: Vec3) -> Vec3 {
    let fx = if point.x < 0.0 {
        (point.x - 1.0).floor()
    } else {
        point.x.floor()
    };
    let fz = if point.z < 0.0 {
        (point.z - 1.0).floor()
    } else {
        point.z.floor()
    };
    let check = ((fx as i64) + (fz as i64)) & 1;
    if check == 0 {
        Vec3::new(0.8, 0.8, 0.8)
    } else {
        Vec3::new(0.3, 0.3, 0.3)
    }
}

fn find_closest_hit(ray: &Ray, spheres: &[Sphere]) -> Option<HitRecord> {
    let mut closest_t = f64::MAX;
    let mut hit: Option<HitRecord> = None;

    // Check spheres
    for sphere in spheres {
        if let Some(t) = intersect_sphere(ray, sphere) {
            if t < closest_t {
                closest_t = t;
                let point = ray.origin.add(ray.direction.mul(t));
                let normal = point.sub(sphere.center).normalize();
                hit = Some(HitRecord {
                    point,
                    normal,
                    color: sphere.color,
                    reflectivity: sphere.reflectivity,
                    specular: sphere.specular,
                });
            }
        }
    }

    // Check ground plane
    if let Some(t) = intersect_plane(ray) {
        if t < closest_t {
            let point = ray.origin.add(ray.direction.mul(t));
            let normal = Vec3::new(0.0, 1.0, 0.0);
            let color = checkerboard_color(point);
            hit = Some(HitRecord {
                point,
                normal,
                color,
                reflectivity: 0.3,
                specular: 10.0,
            });
        }
    }

    hit
}

fn is_in_shadow(point: Vec3, light_pos: Vec3, spheres: &[Sphere]) -> bool {
    let to_light = light_pos.sub(point);
    let dist = to_light.length();
    let dir = to_light.normalize();
    let shadow_ray = Ray {
        origin: point.add(dir.mul(EPSILON)),
        direction: dir,
    };

    // Check spheres
    for sphere in spheres {
        if let Some(t) = intersect_sphere(&shadow_ray, sphere) {
            if t < dist {
                return true;
            }
        }
    }

    // Check ground plane
    if let Some(t) = intersect_plane(&shadow_ray) {
        if t < dist {
            return true;
        }
    }

    false
}

fn trace(ray: &Ray, spheres: &[Sphere], lights: &[PointLight], depth: i32) -> Vec3 {
    if depth >= MAX_DEPTH {
        return Vec3::new(0.0, 0.0, 0.0);
    }

    let hit = find_closest_hit(ray, spheres);
    match hit {
        None => {
            // Sky gradient
            let t = 0.5 * (ray.direction.normalize().y + 1.0);
            Vec3::new(1.0, 1.0, 1.0)
                .mul(1.0 - t)
                .add(Vec3::new(0.5, 0.7, 1.0).mul(t))
        }
        Some(h) => {
            // Ambient
            let mut color = h.color.mul(AMBIENT);

            let view_dir = ray.direction.mul(-1.0).normalize();

            // For each light
            for light in lights {
                if is_in_shadow(h.point, light.position, spheres) {
                    continue;
                }

                let light_dir = light.position.sub(h.point).normalize();
                let n_dot_l = h.normal.dot(light_dir).max(0.0);

                // Diffuse
                let diffuse = h.color.mul(n_dot_l * light.intensity);
                color = color.add(diffuse);

                // Specular (Phong)
                if n_dot_l > 0.0 {
                    let reflect_dir = light_dir.mul(-1.0).reflect(h.normal);
                    let spec_angle = view_dir.dot(reflect_dir).max(0.0);
                    let spec = spec_angle.powf(h.specular) * light.intensity;
                    color = color.add(Vec3::new(spec, spec, spec));
                }
            }

            // Reflection
            if h.reflectivity > 0.0 && depth < MAX_DEPTH {
                let reflect_dir = ray.direction.normalize().reflect(h.normal);
                let reflect_ray = Ray {
                    origin: h.point.add(reflect_dir.mul(EPSILON)),
                    direction: reflect_dir,
                };
                let reflected_color = trace(&reflect_ray, spheres, lights, depth + 1);
                color = color
                    .mul(1.0 - h.reflectivity)
                    .add(reflected_color.mul(h.reflectivity));
            }

            color
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: {} WIDTH HEIGHT", args[0]);
        std::process::exit(1);
    }
    let width: usize = args[1].parse().expect("Invalid width");
    let height: usize = args[2].parse().expect("Invalid height");

    // Camera setup
    let cam_pos = Vec3::new(0.0, 1.5, -5.0);
    let look_at = Vec3::new(0.0, 0.5, 0.0);
    let up = Vec3::new(0.0, 1.0, 0.0);
    let fov: f64 = 60.0;

    let forward = look_at.sub(cam_pos).normalize();
    let right = forward.cross(up).normalize();
    let cam_up = right.cross(forward).normalize();

    let aspect = width as f64 / height as f64;
    let half_height = (fov.to_radians() / 2.0).tan();
    let half_width = aspect * half_height;

    // Spheres
    let spheres = vec![
        Sphere {
            center: Vec3::new(-2.0, 1.0, 0.0),
            radius: 1.0,
            color: Vec3::new(0.9, 0.2, 0.2),
            reflectivity: 0.3,
            specular: 50.0,
        },
        Sphere {
            center: Vec3::new(0.0, 0.75, 0.0),
            radius: 0.75,
            color: Vec3::new(0.2, 0.9, 0.2),
            reflectivity: 0.2,
            specular: 30.0,
        },
        Sphere {
            center: Vec3::new(2.0, 1.0, 0.0),
            radius: 1.0,
            color: Vec3::new(0.2, 0.2, 0.9),
            reflectivity: 0.4,
            specular: 80.0,
        },
        Sphere {
            center: Vec3::new(-0.75, 0.4, -1.5),
            radius: 0.4,
            color: Vec3::new(0.9, 0.9, 0.2),
            reflectivity: 0.5,
            specular: 100.0,
        },
        Sphere {
            center: Vec3::new(1.5, 0.5, -1.0),
            radius: 0.5,
            color: Vec3::new(0.9, 0.2, 0.9),
            reflectivity: 0.6,
            specular: 60.0,
        },
    ];

    // Lights
    let lights = vec![
        PointLight {
            position: Vec3::new(-3.0, 5.0, -3.0),
            intensity: 0.7,
        },
        PointLight {
            position: Vec3::new(3.0, 3.0, -1.0),
            intensity: 0.4,
        },
    ];

    // Render
    let mut pixels = Vec::with_capacity(width * height * 3);

    for j in 0..height {
        for i in 0..width {
            let u = (2.0 * ((i as f64 + 0.5) / width as f64) - 1.0) * half_width;
            let v = (1.0 - 2.0 * ((j as f64 + 0.5) / height as f64)) * half_height;

            let direction = forward.add(right.mul(u)).add(cam_up.mul(v)).normalize();
            let ray = Ray {
                origin: cam_pos,
                direction,
            };

            let color = trace(&ray, &spheres, &lights, 0);
            let color = color.clamp().gamma_correct(GAMMA);

            pixels.push((color.x * 255.0 + 0.5) as u8);
            pixels.push((color.y * 255.0 + 0.5) as u8);
            pixels.push((color.z * 255.0 + 0.5) as u8);
        }
    }

    // Output PPM P6
    let stdout = io::stdout();
    let mut writer = BufWriter::new(stdout.lock());
    write!(writer, "P6\n{} {}\n255\n", width, height).unwrap();
    writer.write_all(&pixels).unwrap();
    writer.flush().unwrap();
}
