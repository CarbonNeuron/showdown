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
