# Competition: Ray Tracer

## Task
Render a fixed 3D scene using ray tracing, outputting the result as a PPM P6 binary image to stdout.

**Scene definition:**

Camera at (0, 1.5, -5) looking at (0, 0.5, 0) with 60 degree vertical FOV. Up vector (0, 1, 0).

Ground plane at y=0, checkerboard pattern alternating (0.8, 0.8, 0.8) and (0.3, 0.3, 0.3) with square size 1.0, reflectivity 0.3.

Five spheres:
| Center         | Radius | Color           | Reflectivity | Specular |
|----------------|--------|-----------------|-------------|----------|
| (-2, 1, 0)     | 1.0    | (0.9, 0.2, 0.2) | 0.3         | 50       |
| (0, 0.75, 0)   | 0.75   | (0.2, 0.9, 0.2) | 0.2         | 30       |
| (2, 1, 0)      | 1.0    | (0.2, 0.2, 0.9) | 0.4         | 80       |
| (-0.75, 0.4, -1.5) | 0.4 | (0.9, 0.9, 0.2) | 0.5      | 100      |
| (1.5, 0.5, -1)  | 0.5   | (0.9, 0.2, 0.9) | 0.6         | 60       |

Two point lights:
| Position       | Intensity |
|----------------|-----------|
| (-3, 5, -3)   | 0.7       |
| (3, 3, -1)    | 0.4       |

Ambient light intensity: 0.1.

**Required rendering features:**
- Phong shading (ambient + diffuse + specular)
- Hard shadows via ray casting to each light source
- Recursive reflections with max depth 5
- Gamma correction (gamma = 2.2) applied before output

**Constraints:**
- Single-threaded execution only, no GPU or SIMD acceleration
- Standard library math only (no external rendering or math libraries)
- Runtime rendering required (no pre-computed or embedded image data)
- 64-bit floating-point precision

## Interface
- **Input:** Two command-line arguments: `WIDTH HEIGHT` (integers)
- **Output:** PPM P6 binary image to stdout (binary mode)
- **Exit code:** 0 on success, non-zero on error

## Validation
- Valid PPM P6 binary with correct dimensions
- SSIM >= 0.85 against reference render

## Scoring
- **runtime**: Wall-clock rendering time (primary sort)
- **build_time**: Wall-clock compilation/build time
- **binary_size**: Size of compiled artifact or Docker image

## Parameters
- **output_type**: image
- **default_width**: 1920
- **default_height**: 1080
- **ssim_threshold**: 0.85
- **timeout_build**: 300
- **timeout_run**: 600
- **warmup_runs**: 1
- **bench_runs**: 3

## Languages
c, rust, go, javascript, python

## Docker
- **base_image**: ubuntu:24.04
- **max_image_size**: 2GB
