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
