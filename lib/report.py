"""Generate RESULTS.md and results.json from benchmark data."""

import json
from datetime import datetime, timezone
from pathlib import Path

from .spec import CompetitionSpec
from .benchmark import BenchResult
from .languages import LANGUAGES


BASE_DIR = Path(__file__).parent.parent.resolve()


def format_time(seconds: float) -> str:
    if seconds < 0.001:
        return f"{seconds * 1_000_000:.0f} us"
    elif seconds < 1.0:
        return f"{seconds * 1000:.1f} ms"
    else:
        return f"{seconds:.3f} s"


def format_size(size_bytes: int) -> str:
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    else:
        return f"{size_bytes / (1024 * 1024):.2f} MB"


def save_results_json(
    competition: str,
    spec: CompetitionSpec,
    results: list[BenchResult],
    n: int,
):
    path = BASE_DIR / "competitions" / competition / "results.json"

    existing = {}
    if path.exists():
        data = json.loads(path.read_text())
        for r in data.get("results", []):
            existing[r["language"]] = r

    for r in results:
        existing[r.language] = {
            "language": r.language,
            "build_time_s": round(r.build_time_s, 6),
            "run_time_median_s": round(r.run_time_median_s, 6),
            "run_times_s": [round(t, 6) for t in r.run_times_s],
            "image_size_bytes": r.image_size_bytes,
            "output_valid": r.output_valid,
            "error": r.error,
        }

    data = {
        "competition": competition,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "parameters": {"n": n, **spec.parameters},
        "results": list(existing.values()),
    }

    path.write_text(json.dumps(data, indent=2) + "\n")
    return path


def load_results_json(competition: str) -> dict:
    path = BASE_DIR / "competitions" / competition / "results.json"
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def generate_report(competition: str, spec: CompetitionSpec) -> Path:
    data = load_results_json(competition)
    if not data:
        raise FileNotFoundError(f"No results.json for {competition}")

    results = data.get("results", [])
    params = data.get("parameters", {})
    n = params.get("n", params.get("default_n", 1000000))

    ok = [r for r in results if r.get("output_valid") and not r.get("error")]
    failed = [r for r in results if not r.get("output_valid") or r.get("error")]
    ok.sort(key=lambda r: r["run_time_median_s"])

    fastest = ok[0]["run_time_median_s"] if ok else 1

    lines = []
    lines.append(f"# {spec.name} - Results\n")
    lines.append(f"## Task\n\n{spec.task}\n")

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

    lines.append("## Runtime Performance Rankings\n")
    lines.append("| Rank | Language | Runtime | vs Fastest | Image Size |")
    lines.append("|-----:|----------|--------:|-----------:|-----------:|")

    for i, r in enumerate(ok, 1):
        ratio = r["run_time_median_s"] / fastest if fastest > 0 else 0
        ratio_str = "1.0x" if i == 1 else f"{ratio:.1f}x"
        lang_name = LANGUAGES.get(r["language"], {}).get("name", r["language"])
        rt = format_time(r["run_time_median_s"])
        img = format_size(r["image_size_bytes"]) if r.get("image_size_bytes") else "n/a"
        bold = "**" if i <= 3 else ""
        lines.append(f"| {i} | {bold}{lang_name}{bold} | {rt} | {ratio_str} | {img} |")

    if failed:
        lines.append(f"\n### Skipped / Failed\n")
        for r in failed:
            lang_name = LANGUAGES.get(r["language"], {}).get("name", r["language"])
            reason = r.get("error", "unknown error")
            lines.append(f"- **{lang_name}**: {reason}")

    lines.append("")

    compiled = [r for r in ok if r.get("build_time_s", 0) > 0]
    if compiled:
        compiled.sort(key=lambda r: r["build_time_s"])
        lines.append("## Build Time Rankings\n")
        lines.append("| Rank | Language | Build Time |")
        lines.append("|-----:|----------|----------:|")
        for i, r in enumerate(compiled, 1):
            lang_name = LANGUAGES.get(r["language"], {}).get("name", r["language"])
            lines.append(f"| {i} | {lang_name} | {format_time(r['build_time_s'])} |")
        lines.append("")

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

    lines.append("## How to Run\n")
    lines.append("```bash")
    lines.append(f"python showdown.py all {competition}")
    lines.append("```\n")

    path = BASE_DIR / "competitions" / competition / "RESULTS.md"
    path.write_text("\n".join(lines))
    return path
