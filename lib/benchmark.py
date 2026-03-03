"""Benchmark engine: timing, validation, and scoring."""

import re
import statistics
from dataclasses import dataclass, field
from pathlib import Path

from .spec import CompetitionSpec
from .docker import run_container, get_image_size


@dataclass
class BenchResult:
    language: str
    build_time_s: float = 0.0
    run_time_median_s: float = 0.0
    run_times_s: list = field(default_factory=list)
    image_size_bytes: int = 0
    output_valid: bool = False
    error: str = ""


def validate_output(output: str, spec: CompetitionSpec, n: int) -> tuple[bool, str]:
    rules = spec.validation.lower()
    lines = output.strip().split("\n") if output.strip() else []

    if "exactly n lines" in rules or "n lines" in rules:
        if len(lines) != n:
            return False, f"Expected {n} lines, got {len(lines)}"

    if "valid integer" in rules or "integer" in rules:
        for i, line in enumerate(lines):
            try:
                int(line.strip())
            except ValueError:
                return False, f"Line {i+1}: '{line.strip()}' is not an integer"

    range_match = re.search(r"in \[(\d+),\s*(\d+)\]", spec.validation)
    if range_match:
        lo, hi = int(range_match.group(1)), int(range_match.group(2))
        for i, line in enumerate(lines):
            val = int(line.strip())
            if val < lo or val > hi:
                return False, f"Line {i+1}: {val} not in [{lo}, {hi}]"

    if "sorted" in rules:
        vals = [int(line.strip()) for line in lines]
        for i in range(len(vals) - 1):
            if vals[i] > vals[i + 1]:
                return False, f"Not sorted: line {i+1} ({vals[i]}) > line {i+2} ({vals[i+1]})"

    return True, ""


def validate_ppm(data: bytes, width: int, height: int) -> tuple[bool, str]:
    """Validate PPM P6 binary format."""
    if not data.startswith(b"P6"):
        return False, "Not a PPM P6 file (missing P6 magic)"

    try:
        header_end = data.index(b"\n", data.index(b"\n", data.index(b"\n") + 1) + 1) + 1
        header = data[:header_end].decode("ascii")
        lines = header.strip().split("\n")
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


def run_benchmark(
    competition: str,
    lang: str,
    spec: CompetitionSpec,
    n: int | None = None,
) -> BenchResult:
    result = BenchResult(language=lang)

    if n is None:
        n = spec.parameters.get("default_n", 1000000)

    warmup_runs = spec.parameters.get("warmup_runs", 1)
    bench_runs = spec.parameters.get("bench_runs", 3)
    timeout = spec.parameters.get("timeout_run", 300)

    # Warmup
    for _ in range(warmup_runs):
        try:
            stdout, elapsed, rc = run_container(
                competition, lang, [str(n)], timeout=timeout
            )
            if rc != 0:
                result.error = f"Warmup failed (exit {rc})"
                return result
        except Exception as e:
            result.error = f"Warmup error: {e}"
            return result

    # Benchmark runs
    for i in range(bench_runs):
        try:
            stdout, elapsed, rc = run_container(
                competition, lang, [str(n)], timeout=timeout
            )
            if rc != 0:
                result.error = f"Run {i+1} failed (exit {rc})"
                return result

            result.run_times_s.append(elapsed)

            if i == 0:
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

    return result
