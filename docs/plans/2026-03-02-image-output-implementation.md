# Image Output Support + Raytracer Competition — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add image output support to the benchmark framework and create the raytracer competition.

**Architecture:** Existing text-based pipeline gets an `output_type` branch at each stage. When `output_type` is `"image"`, Docker captures binary stdout, benchmark saves PPM/PNG files, validation uses PPM format checks + SSIM, and reports embed PNG thumbnails. First passing solution becomes the SSIM reference.

**Tech Stack:** Python 3.12+, Pillow (PPM↔PNG), scikit-image (SSIM), Docker.

---

### Task 1: Add requirements.txt

**Files:**
- Create: `requirements.txt`

**Step 1: Create requirements.txt**

```
pillow>=10.0
scikit-image>=0.22
```

**Step 2: Install dependencies**

Run: `pip install -r requirements.txt`
Expected: Successfully installed pillow and scikit-image

**Step 3: Verify imports work**

Run: `python -c "from PIL import Image; from skimage.metrics import structural_similarity; print('OK')"`
Expected: `OK`

**Step 4: Commit**

```bash
git add requirements.txt
git commit -m "feat: add requirements.txt with pillow and scikit-image"
```

---

### Task 2: Add binary output mode to docker.py

**Files:**
- Modify: `lib/docker.py:40-68` (the `run_container` function)

**Step 1: Write failing test**

Create: `tests/test_docker.py`

```python
"""Tests for docker binary output mode."""
import subprocess
from unittest.mock import patch, MagicMock
from lib.docker import run_container


def test_run_container_text_mode_returns_str():
    """Default text mode returns string stdout."""
    mock_proc = MagicMock()
    mock_proc.stdout = "hello\n"
    mock_proc.returncode = 0

    with patch("lib.docker.subprocess.run", return_value=mock_proc) as mock_run:
        stdout, elapsed, rc = run_container("comp", "lang", ["arg"])
        assert isinstance(stdout, str)
        # Verify text=True is passed
        call_kwargs = mock_run.call_args[1]
        assert call_kwargs["text"] is True


def test_run_container_binary_mode_returns_bytes():
    """Binary mode returns bytes stdout."""
    mock_proc = MagicMock()
    mock_proc.stdout = b"\x89PNG binary data"
    mock_proc.returncode = 0

    with patch("lib.docker.subprocess.run", return_value=mock_proc) as mock_run:
        stdout, elapsed, rc = run_container("comp", "lang", ["arg"], binary=True)
        assert isinstance(stdout, bytes)
        # Verify text=False is passed
        call_kwargs = mock_run.call_args[1]
        assert call_kwargs.get("text", False) is False
```

**Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_docker.py -v`
Expected: FAIL — `run_container` has no `binary` parameter

**Step 3: Implement binary mode**

In `lib/docker.py`, modify `run_container` (lines 40-68). Add `binary: bool = False` parameter. When `binary=True`, run with `text=False` and don't pass `input` as string:

```python
def run_container(
    competition: str,
    lang: str,
    args: list[str],
    timeout: int = 300,
    memory: str = "512m",
    cpus: str = "1",
    stdin_data: str | None = None,
    binary: bool = False,
) -> tuple[str | bytes, float, int]:
    tag = image_name(competition, lang)
    cmd = [
        "docker", "run", "--rm",
        "--network=none",
        f"--memory={memory}",
        f"--cpus={cpus}",
        tag,
    ] + args

    start = time.perf_counter()
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=not binary,
        timeout=timeout,
        input=stdin_data,
    )
    elapsed = time.perf_counter() - start

    return proc.stdout, elapsed, proc.returncode
```

**Step 4: Run tests to verify they pass**

Run: `python -m pytest tests/test_docker.py -v`
Expected: 2 passed

**Step 5: Commit**

```bash
git add lib/docker.py tests/test_docker.py
git commit -m "feat: add binary output mode to run_container"
```

---

### Task 3: Add image validation functions to benchmark.py

**Files:**
- Modify: `lib/benchmark.py` (add new functions after `validate_output`)
- Create: `tests/test_image_validation.py`

**Step 1: Write failing tests**

Create: `tests/test_image_validation.py`

```python
"""Tests for PPM validation and SSIM computation."""
from lib.benchmark import validate_ppm, compute_ssim, save_output_image
from pathlib import Path
import struct


def make_ppm(width, height, pixel_value=128):
    """Create a valid PPM P6 binary."""
    header = f"P6\n{width} {height}\n255\n".encode()
    data = bytes([pixel_value] * (width * height * 3))
    return header + data


def test_validate_ppm_valid():
    data = make_ppm(4, 3)
    valid, msg = validate_ppm(data, 4, 3)
    assert valid, msg


def test_validate_ppm_wrong_magic():
    data = b"P5\n4 3\n255\n" + b"\x00" * 36
    valid, msg = validate_ppm(data, 4, 3)
    assert not valid
    assert "P6" in msg


def test_validate_ppm_wrong_dimensions():
    data = make_ppm(8, 6)
    valid, msg = validate_ppm(data, 4, 3)
    assert not valid
    assert "dimension" in msg.lower()


def test_validate_ppm_truncated_data():
    header = b"P6\n4 3\n255\n"
    data = header + b"\x00" * 10  # need 36 bytes
    valid, msg = validate_ppm(data, 4, 3)
    assert not valid
    assert "data" in msg.lower() or "size" in msg.lower()


def test_compute_ssim_identical():
    data = make_ppm(64, 64, 128)
    score = compute_ssim(data, data, 64, 64)
    assert score > 0.99


def test_compute_ssim_different():
    data_a = make_ppm(64, 64, 0)
    data_b = make_ppm(64, 64, 255)
    score = compute_ssim(data_a, data_b, 64, 64)
    assert score < 0.5


def test_save_output_image(tmp_path):
    data = make_ppm(4, 3)
    save_output_image(str(tmp_path), "testlang", data)
    assert (tmp_path / "output" / "testlang.ppm").exists()
    assert (tmp_path / "output" / "testlang.png").exists()
```

**Step 2: Run tests to verify they fail**

Run: `python -m pytest tests/test_image_validation.py -v`
Expected: FAIL — `validate_ppm`, `compute_ssim`, `save_output_image` don't exist

**Step 3: Implement the three functions**

Add to `lib/benchmark.py` after the existing `validate_output` function (after line 51):

```python
def validate_ppm(data: bytes, width: int, height: int) -> tuple[bool, str]:
    """Validate PPM P6 binary format."""
    if not data.startswith(b"P6"):
        return False, "Not a PPM P6 file (missing P6 magic)"

    try:
        header_end = data.index(b"\n", data.index(b"\n", data.index(b"\n") + 1) + 1) + 1
        header = data[:header_end].decode("ascii")
        lines = header.strip().split("\n")
        # Skip comments
        lines = [l for l in lines if not l.startswith("#")]
        dims = lines[1].split()
        w, h = int(dims[0]), int(dims[1])
    except (ValueError, IndexError):
        return False, "Failed to parse PPM header"

    if w != width or h != height:
        return False, f"Dimension mismatch: expected {width}x{height}, got {w}x{h}"

    expected_data_len = width * height * 3
    actual_data_len = len(data) - header_end
    if actual_data_len < expected_data_len:
        return False, f"Pixel data too short: expected {expected_data_len} bytes, got {actual_data_len}"

    return True, ""


def compute_ssim(ppm_a: bytes, ppm_b: bytes, width: int, height: int) -> float:
    """Compute SSIM between two PPM P6 images."""
    import numpy as np
    from PIL import Image
    from skimage.metrics import structural_similarity
    import io

    img_a = Image.open(io.BytesIO(ppm_a)).convert("L")
    img_b = Image.open(io.BytesIO(ppm_b)).convert("L")

    arr_a = np.array(img_a)
    arr_b = np.array(img_b)

    return structural_similarity(arr_a, arr_b)


def save_output_image(comp_dir: str, lang: str, ppm_data: bytes) -> Path:
    """Save PPM data as .ppm and convert to .png. Returns the output directory."""
    from PIL import Image
    import io

    output_dir = Path(comp_dir) / "output"
    output_dir.mkdir(exist_ok=True)

    ppm_path = output_dir / f"{lang}.ppm"
    ppm_path.write_bytes(ppm_data)

    img = Image.open(io.BytesIO(ppm_data))
    png_path = output_dir / f"{lang}.png"
    img.save(png_path)

    return output_dir
```

**Step 4: Run tests to verify they pass**

Run: `python -m pytest tests/test_image_validation.py -v`
Expected: 7 passed

**Step 5: Commit**

```bash
git add lib/benchmark.py tests/test_image_validation.py
git commit -m "feat: add PPM validation, SSIM computation, and image saving"
```

---

### Task 4: Add image benchmark path to run_benchmark

**Files:**
- Modify: `lib/benchmark.py:54-108` (the `run_benchmark` function)
- Create: `tests/test_image_benchmark.py`

**Step 1: Write failing test**

Create: `tests/test_image_benchmark.py`

```python
"""Tests for image-mode benchmarking."""
from unittest.mock import patch, MagicMock
from lib.benchmark import run_benchmark
from lib.spec import CompetitionSpec


def make_ppm(width, height, pixel_value=128):
    header = f"P6\n{width} {height}\n255\n".encode()
    data = bytes([pixel_value] * (width * height * 3))
    return header + data


def make_image_spec():
    return CompetitionSpec(
        name="test-image",
        task="Render an image",
        interface="WIDTH HEIGHT args, PPM P6 to stdout",
        validation="Valid PPM P6 image",
        parameters={
            "output_type": "image",
            "default_width": 4,
            "default_height": 3,
            "timeout_run": 60,
            "warmup_runs": 0,
            "bench_runs": 1,
            "ssim_threshold": 0.85,
        },
    )


@patch("lib.benchmark.get_image_size", return_value=1000)
@patch("lib.benchmark.save_output_image")
@patch("lib.benchmark.run_container")
def test_image_benchmark_captures_binary(mock_run, mock_save, mock_size):
    ppm = make_ppm(4, 3)
    mock_run.return_value = (ppm, 1.5, 0)
    mock_save.return_value = None

    spec = make_image_spec()
    result = run_benchmark("comp", "lang", spec)

    assert result.output_valid
    assert result.run_time_median_s == 1.5
    # Verify binary=True was passed to run_container
    call_kwargs = mock_run.call_args_list[0][1]
    assert call_kwargs.get("binary") is True
    # Verify WIDTH HEIGHT args (not N)
    call_args = mock_run.call_args_list[0][0]
    assert call_args[2] == ["4", "3"]
```

**Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_image_benchmark.py -v`
Expected: FAIL — `run_benchmark` doesn't handle `output_type`

**Step 3: Modify run_benchmark to branch on output_type**

Replace `run_benchmark` in `lib/benchmark.py` (lines 54-108) with:

```python
def run_benchmark(
    competition: str,
    lang: str,
    spec: CompetitionSpec,
    n: int | None = None,
) -> BenchResult:
    result = BenchResult(language=lang)

    output_type = spec.parameters.get("output_type", "text")
    is_image = output_type == "image"

    if is_image:
        width = spec.parameters.get("default_width", 1920)
        height = spec.parameters.get("default_height", 1080)
        container_args = [str(width), str(height)]
        ssim_threshold = spec.parameters.get("ssim_threshold", 0.85)
    else:
        if n is None:
            n = spec.parameters.get("default_n", 1000000)
        container_args = [str(n)]

    warmup_runs = spec.parameters.get("warmup_runs", 1)
    bench_runs = spec.parameters.get("bench_runs", 3)
    timeout = spec.parameters.get("timeout_run", 300)

    # Warmup
    for _ in range(warmup_runs):
        try:
            stdout, elapsed, rc = run_container(
                competition, lang, container_args, timeout=timeout, binary=is_image
            )
            if rc != 0:
                result.error = f"Warmup failed (exit {rc})"
                return result
        except Exception as e:
            result.error = f"Warmup error: {e}"
            return result

    # Benchmark runs
    first_output = None
    for i in range(bench_runs):
        try:
            stdout, elapsed, rc = run_container(
                competition, lang, container_args, timeout=timeout, binary=is_image
            )
            if rc != 0:
                result.error = f"Run {i+1} failed (exit {rc})"
                return result

            result.run_times_s.append(elapsed)

            if i == 0:
                first_output = stdout
                if is_image:
                    valid, msg = validate_ppm(stdout, width, height)
                else:
                    valid, msg = validate_output(stdout, spec, n)
                result.output_valid = valid
                if not valid:
                    result.error = f"Validation: {msg}"
                    return result

        except Exception as e:
            result.error = f"Run {i+1} error: {e}"
            return result

    result.run_time_median_s = statistics.median(result.run_times_s)
    result.image_size_bytes = get_image_size(competition, lang)

    # Image-specific: save output and SSIM check
    if is_image and first_output:
        comp_dir = str(Path(__file__).parent.parent / "competitions" / competition)
        save_output_image(comp_dir, lang, first_output)

        ref_path = Path(comp_dir) / "output" / "_reference.ppm"
        if ref_path.exists():
            ref_data = ref_path.read_bytes()
            ssim_score = compute_ssim(ref_data, first_output, width, height)
            if ssim_score < ssim_threshold:
                result.output_valid = False
                result.error = f"SSIM {ssim_score:.3f} < {ssim_threshold}"
        else:
            # First passing solution becomes the reference
            ref_path.write_bytes(first_output)

    return result
```

Also add `from pathlib import Path` to the imports at the top of `lib/benchmark.py`.

**Step 4: Run tests to verify they pass**

Run: `python -m pytest tests/test_image_benchmark.py tests/test_image_validation.py -v`
Expected: All passed

**Step 5: Verify existing text-mode behavior still works**

Run: `python -m pytest tests/ -v`
Expected: All tests pass (no regression)

**Step 6: Commit**

```bash
git add lib/benchmark.py tests/test_image_benchmark.py
git commit -m "feat: add image output path in run_benchmark with SSIM validation"
```

---

### Task 5: Update CLI to handle image competitions

**Files:**
- Modify: `showdown.py:111-154` (`cmd_run` function)
- Modify: `lib/report.py:33-66` (`save_results_json` function)

**Step 1: Update cmd_run to show resolution for image competitions**

In `showdown.py`, modify `cmd_run` (lines 111-154). After parsing the spec (line 123), branch on output_type:

```python
def cmd_run(args):
    from lib.spec import parse_spec
    from lib.languages import resolve_languages, LANGUAGES
    from lib.benchmark import run_benchmark
    from lib.report import save_results_json, format_time

    name = args.name
    spec_path = BASE_DIR / "competitions" / name / "SPEC.md"
    if not spec_path.exists():
        print(f"{RED}No SPEC.md found at {spec_path}{RESET}")
        sys.exit(1)

    spec = parse_spec(spec_path)
    output_type = spec.parameters.get("output_type", "text")

    if output_type == "image":
        width = spec.parameters.get("default_width", 1920)
        height = spec.parameters.get("default_height", 1080)
        n = width  # pass width as n for results.json compatibility
    else:
        n = args.n or spec.parameters.get("default_n", 1000000)

    if args.lang:
        target_langs = args.lang
    else:
        target_langs = resolve_languages(spec.languages)

    langs_dir = BASE_DIR / "competitions" / name / "languages"
    available = [l for l in target_langs if (langs_dir / l / "Dockerfile").exists()]

    if not available:
        print(f"{YELLOW}No solutions found. Run 'showdown generate {name}' first.{RESET}")
        return

    if output_type == "image":
        print(f"{BOLD}Benchmarking {len(available)} languages for '{name}' ({width}x{height})...{RESET}\n")
    else:
        print(f"{BOLD}Benchmarking {len(available)} languages for '{name}' (N={n:,})...{RESET}\n")

    results = []
    for i, lang in enumerate(available, 1):
        lang_name = LANGUAGES.get(lang, {}).get("name", lang)
        print(f"  [{i}/{len(available)}] {lang_name}...", end=" ", flush=True)

        r = run_benchmark(name, lang, spec, n)
        results.append(r)

        if r.error:
            print(f"{RED}FAIL: {r.error}{RESET}")
        else:
            print(f"{GREEN}{format_time(r.run_time_median_s)}{RESET}")

    path = save_results_json(name, spec, results, n)
    print(f"\n{DIM}Results saved to {path}{RESET}")
```

**Step 2: Verify no syntax errors**

Run: `python -c "import showdown"`
Expected: No errors

**Step 3: Commit**

```bash
git add showdown.py
git commit -m "feat: update cmd_run to handle image competitions"
```

---

### Task 6: Add image thumbnails to report generation

**Files:**
- Modify: `lib/report.py:76-142` (`generate_report` function)

**Step 1: Write failing test**

Create: `tests/test_report_images.py`

```python
"""Tests for image competition report generation."""
import json
from pathlib import Path
from lib.report import generate_report
from lib.spec import CompetitionSpec


def test_report_includes_rendered_output_section(tmp_path, monkeypatch):
    """Image competitions get a Rendered Output section with PNG links."""
    import lib.report
    monkeypatch.setattr(lib.report, "BASE_DIR", tmp_path)

    comp_dir = tmp_path / "competitions" / "test-rt"
    comp_dir.mkdir(parents=True)
    output_dir = comp_dir / "output"
    output_dir.mkdir()

    # Create fake PNG files
    (output_dir / "c.png").write_bytes(b"fakepng")
    (output_dir / "rust.png").write_bytes(b"fakepng")

    # Create results.json
    results_data = {
        "competition": "test-rt",
        "timestamp": "2026-01-01T00:00:00Z",
        "parameters": {"output_type": "image", "default_width": 1920, "default_height": 1080},
        "results": [
            {"language": "c", "build_time_s": 1.0, "run_time_median_s": 5.0,
             "run_times_s": [5.0], "image_size_bytes": 1000, "output_valid": True, "error": ""},
            {"language": "rust", "build_time_s": 2.0, "run_time_median_s": 3.0,
             "run_times_s": [3.0], "image_size_bytes": 2000, "output_valid": True, "error": ""},
        ],
    }
    (comp_dir / "results.json").write_text(json.dumps(results_data))

    spec = CompetitionSpec(
        name="test-rt",
        task="Render a scene",
        interface="WIDTH HEIGHT",
        validation="PPM P6",
        parameters={"output_type": "image", "default_width": 1920, "default_height": 1080},
    )

    path = generate_report("test-rt", spec)
    content = path.read_text()

    assert "## Rendered Output" in content
    assert "![Rust](output/rust.png)" in content
    assert "![C](output/c.png)" in content
```

**Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_report_images.py -v`
Expected: FAIL — no "Rendered Output" section

**Step 3: Modify generate_report**

In `lib/report.py`, modify `generate_report` (lines 76-142). Add output_type awareness to the methodology section and add a rendered output section before "How to Run". Replace the methodology section to handle image competitions, and add the rendered output block:

After the methodology section (around line 100), change the `N` line to be conditional:

```python
    output_type = params.get("output_type", "text")

    lines.append("## Methodology\n")
    if output_type == "image":
        w = params.get("default_width", 1920)
        h = params.get("default_height", 1080)
        lines.append(f"- **Resolution:** {w}x{h}")
    else:
        lines.append(f"- **N:** {n:,}")
    lines.append(f"- **Runs:** {params.get('bench_runs', 3)} (median)")
    lines.append(f"- **Warmup:** {params.get('warmup_runs', 1)}")
    lines.append(f"- **Containers:** Docker with `--network=none --memory=512m --cpus=1`")
    lines.append("")
```

Then, before the "How to Run" section (before line 135), add the rendered output block:

```python
    # Rendered output section for image competitions
    if output_type == "image":
        output_dir = BASE_DIR / "competitions" / competition / "output"
        if output_dir.exists():
            ok_langs = [r["language"] for r in ok]
            pngs = [(l, output_dir / f"{l}.png") for l in ok_langs if (output_dir / f"{l}.png").exists()]
            if pngs:
                lines.append("## Rendered Output\n")
                for lang_key, png_path in pngs:
                    lang_name = LANGUAGES.get(lang_key, {}).get("name", lang_key)
                    lines.append(f"### {lang_name}\n")
                    lines.append(f"![{lang_name}](output/{lang_key}.png)\n")
```

**Step 4: Run tests to verify they pass**

Run: `python -m pytest tests/test_report_images.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/report.py tests/test_report_images.py
git commit -m "feat: add rendered output section to image competition reports"
```

---

### Task 7: Update agent prompt for image competitions

**Files:**
- Modify: `lib/agents.py:12-55` (`build_agent_prompt` function)

**Step 1: Modify build_agent_prompt to handle image output**

In `lib/agents.py`, the prompt currently says "ENTRYPOINT must accept a single argument N". For image competitions, it should say "ENTRYPOINT must accept two arguments: WIDTH HEIGHT" and omit the N-specific language. Check `spec.parameters.get("output_type", "text")`:

```python
def build_agent_prompt(
    competition: str,
    lang_key: str,
    spec: CompetitionSpec,
) -> str:
    lang = LANGUAGES[lang_key]
    lang_name = lang["name"]
    ext = lang["ext"]

    comp_dir = f"competitions/{competition}/languages/{lang_key}"

    dockerfile_template = (BASE_DIR / "templates" / "Dockerfile.template").read_text()

    output_type = spec.parameters.get("output_type", "text")

    if output_type == "image":
        entrypoint_doc = "The ENTRYPOINT must accept two arguments: WIDTH HEIGHT (the image dimensions)"
    else:
        entrypoint_doc = "The ENTRYPOINT must accept a single argument N (the number passed on the command line)"

    prompt = f'''You are implementing a solution for the "{spec.name}" programming language showdown in **{lang_name}**.

## Task
{spec.task}

## Interface
{spec.interface}

## Validation
{spec.validation}

## Your deliverables

Write these files inside the directory `{comp_dir}/`:

1. `solution.{ext}` -- your {lang_name} implementation. Optimize for runtime performance.
2. `Dockerfile` -- builds and runs the solution inside Docker.

### Dockerfile requirements:
- Use multi-stage builds for compiled languages (build stage + slim runtime stage)
- {entrypoint_doc}
- Use official language Docker images where available (e.g. `rust:1.77-slim`, `python:3.12-slim`, `golang:1.22-bookworm`)
- Optimize for runtime performance (use -O2 or equivalent compiler flags)
- For interpreted languages, just COPY the source and set ENTRYPOINT

### Reference Dockerfile patterns:
{dockerfile_template}

Write the files now. Do NOT explain -- just write the two files using the Write tool.
'''
    return prompt
```

**Step 2: Verify no syntax errors**

Run: `python -c "from lib.agents import build_agent_prompt; print('OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
git add lib/agents.py
git commit -m "feat: update agent prompt for image competition entrypoint"
```

---

### Task 8: Create the raytracer competition SPEC.md

**Files:**
- Create: `competitions/raytracer/SPEC.md`
- Create: `competitions/raytracer/languages/` (empty dir)

**Step 1: Create competition directory**

```bash
mkdir -p competitions/raytracer/languages
```

**Step 2: Write SPEC.md**

Create: `competitions/raytracer/SPEC.md`

```markdown
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
```

**Step 3: Verify the spec parses correctly**

Run: `python -c "from lib.spec import parse_spec; s = parse_spec('competitions/raytracer/SPEC.md'); print(s.name, s.parameters.get('output_type'), s.parameters.get('default_width'))"`
Expected: `Ray Tracer image 1920`

**Step 4: Commit**

```bash
git add competitions/raytracer/
git commit -m "feat: add raytracer competition spec"
```

---

### Task 9: Run all tests and verify no regressions

**Files:** None (verification only)

**Step 1: Run all tests**

Run: `python -m pytest tests/ -v`
Expected: All tests pass

**Step 2: Verify text competition still works end-to-end**

Run: `python showdown.py list`
Expected: Shows both `random-numbers` and `raytracer` competitions

**Step 3: Verify spec parsing**

Run: `python -c "from lib.spec import parse_spec; s = parse_spec('competitions/raytracer/SPEC.md'); print(f'output_type={s.parameters.get(\"output_type\")}, width={s.parameters.get(\"default_width\")}, height={s.parameters.get(\"default_height\")}, ssim={s.parameters.get(\"ssim_threshold\")}, timeout_run={s.parameters.get(\"timeout_run\")}')"`
Expected: `output_type=image, width=1920, height=1080, ssim=0.85, timeout_run=600`

---

### Task 10: Update CLAUDE.md with image output support

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add image output documentation to CLAUDE.md**

Add a section after "Key Conventions" describing image competitions:

```markdown
## Image Competitions

Competitions with `**output_type**: image` in their Parameters section produce binary PPM P6 output instead of text. Key differences:

- Container entrypoint takes `WIDTH HEIGHT` args instead of `N`
- Docker output captured in binary mode
- Validation: PPM format check + SSIM >= threshold against a reference image
- First passing solution's output becomes the reference (`output/_reference.ppm`)
- Output saved as `output/<lang>.ppm` and `output/<lang>.png` (converted via Pillow)
- RESULTS.md includes a "Rendered Output" section with embedded PNG thumbnails
- Dependencies: `pip install -r requirements.txt` (pillow, scikit-image)
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with image competition documentation"
```
