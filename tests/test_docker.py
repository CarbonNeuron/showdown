"""Tests for docker binary output mode."""
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
        call_kwargs = mock_run.call_args[1]
        assert call_kwargs.get("text", False) is False
