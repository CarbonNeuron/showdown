# Image Output Support + Raytracer Competition

## Problem

The framework only handles text stdout. A raytracer competition produces binary PPM images. We need to support binary output capture, image validation (SSIM), saving rendered images, and visual output in reports.

## Decisions

- **Output type dispatch**: `output_type` field in SPEC.md Parameters (`text` default, `image` for raytracer). Each module branches on this.
- **SSIM reference**: First passing solution becomes the reference. No golden image to maintain.
- **SSIM threshold**: 0.85 — tolerates floating-point variance, catches rendering bugs.
- **Visual output**: PPM saved per language, converted to PNG via Pillow, embedded in RESULTS.md.
- **Dependencies**: Add Pillow and scikit-image (first external Python deps).

## SPEC.md Format Changes

New fields in `## Parameters`:
- `**output_type**: image` (default: `text`)
- `**default_width**: 1920`, `**default_height**: 1080` (replace `default_n` as CLI args)
- `**ssim_threshold**: 0.85`
- `**timeout_run**: 600`, `**timeout_build**: 300`

## Framework Changes

### docker.py — Binary output capture

`run_container()` gets `output_type` parameter. When `"image"`, runs with `text=False` so stdout returns bytes. Return type becomes `str | bytes`.

### benchmark.py — Image validation pipeline

New functions:
- `validate_ppm(data, width, height)` — checks P6 magic, dimensions, data length = w*h*3
- `compute_ssim(img_a, img_b, width, height)` — Pillow + scikit-image on grayscale
- `save_output_image(competition, lang, data, width, height)` — saves .ppm + .png

`run_benchmark()` for image competitions:
1. Warmup runs (discard output)
2. Bench runs (capture binary stdout, record timing)
3. Save first run's output as `output/<lang>.ppm` + `output/<lang>.png`
4. Validate PPM format
5. If reference exists (`output/_reference.ppm`), compute SSIM. Otherwise this becomes the reference.
6. SSIM < threshold → invalid with score in error message

### report.py — Image thumbnails

Adds "## Rendered Output" section with `![lang](output/lang.png)` for passing solutions.

### spec.py — Parse new fields

`output_type` from parameters, defaults to `"text"`. `ssim_threshold` as float. `default_width`/`default_height` as ints.

### showdown.py — CLI arg routing

`cmd_run()` checks `output_type`. For `"image"`, passes width/height from spec instead of n.

### agents.py — Prompt adjustments

ENTRYPOINT instructions change to `WIDTH HEIGHT` args. Prompt includes full scene description and rendering requirements.

## Raytracer SPEC.md

Competition: `raytracer`. Scene: 5 colored spheres on checkerboard ground, 2 point lights, Phong shading, hard shadows, recursive reflections (depth 5), gamma correction 2.2. Output: PPM P6 binary, 1920x1080. Single-threaded, stdlib math only, no GPU/SIMD.

## Dependencies

Add `requirements.txt`: pillow, scikit-image.
