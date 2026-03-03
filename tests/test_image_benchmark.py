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
def test_image_benchmark_captures_binary(mock_run, mock_save, mock_size, tmp_path):
    ppm = make_ppm(4, 3)
    mock_run.return_value = (ppm, 1.5, 0)
    mock_save.return_value = None

    spec = make_image_spec()

    # Redirect the competitions directory to tmp_path so reference file
    # does not pollute the real project tree
    fake_base = tmp_path / "project"
    fake_base.mkdir()
    with patch("lib.benchmark.Path") as mock_path_cls:
        # Let real Path work except for __file__ parent resolution
        from pathlib import Path as RealPath

        def path_side_effect(*args, **kwargs):
            return RealPath(*args, **kwargs)

        mock_path_cls.side_effect = path_side_effect
        mock_path_cls.__truediv__ = RealPath.__truediv__

        # Patch __file__ resolution: Path(__file__).parent.parent => fake_base
        file_path_mock = MagicMock()
        file_path_mock.parent.parent = fake_base
        mock_path_cls.return_value = file_path_mock

        # Since we're mocking Path class, let's take a simpler approach:
        # just let it write to the real filesystem using tmp_path
        # Reset the mock to use real Path
        mock_path_cls.reset_mock()

    # Simpler approach: patch at the module level where comp_dir is computed
    import lib.benchmark as bm
    original_file = bm.__file__

    # Create a fake module location so comp_dir resolves under tmp_path
    fake_lib = tmp_path / "lib"
    fake_lib.mkdir()
    bm.__file__ = str(fake_lib / "benchmark.py")

    try:
        result = run_benchmark("comp", "lang", spec)
    finally:
        bm.__file__ = original_file

    assert result.output_valid
    assert result.run_time_median_s == 1.5
    # Verify binary=True was passed to run_container
    call_kwargs = mock_run.call_args_list[0][1]
    assert call_kwargs.get("binary") is True
    # Verify WIDTH HEIGHT args (not N)
    call_args = mock_run.call_args_list[0][0]
    assert call_args[2] == ["4", "3"]

    # Verify reference file was written under tmp_path
    ref_path = tmp_path / "competitions" / "comp" / "output" / "_reference.ppm"
    assert ref_path.exists()
