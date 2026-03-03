"""Docker build and run operations for showdown."""

import subprocess
import time
from pathlib import Path


BASE_DIR = Path(__file__).parent.parent.resolve()


def image_name(competition: str, lang: str) -> str:
    return f"showdown-{competition}-{lang}"


def build_image(competition: str, lang: str) -> tuple[bool, float, str]:
    lang_dir = BASE_DIR / "competitions" / competition / "languages" / lang
    dockerfile = lang_dir / "Dockerfile"

    if not dockerfile.exists():
        return False, 0.0, f"No Dockerfile at {dockerfile}"

    tag = image_name(competition, lang)
    cmd = [
        "docker", "build",
        "-t", tag,
        "-f", str(dockerfile),
        str(lang_dir),
    ]

    start = time.perf_counter()
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    elapsed = time.perf_counter() - start

    if proc.returncode != 0:
        return False, elapsed, proc.stderr[-500:]

    return True, elapsed, ""


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


def get_image_size(competition: str, lang: str) -> int:
    tag = image_name(competition, lang)
    proc = subprocess.run(
        ["docker", "image", "inspect", tag, "--format", "{{.Size}}"],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return 0
    try:
        return int(proc.stdout.strip())
    except ValueError:
        return 0
