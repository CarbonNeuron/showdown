"""Parse SPEC.md files into structured CompetitionSpec objects."""

import re
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class CompetitionSpec:
    name: str
    task: str
    interface: str
    validation: str
    scoring: list[str] = field(default_factory=list)
    parameters: dict = field(default_factory=dict)
    languages: str = "all"
    docker: dict = field(default_factory=dict)
    raw_sections: dict = field(default_factory=dict)


DEFAULTS = {
    "default_n": 1000000,
    "timeout_build": 120,
    "timeout_run": 300,
    "warmup_runs": 1,
    "bench_runs": 3,
}

DOCKER_DEFAULTS = {
    "base_image": "ubuntu:24.04",
    "max_image_size": "2GB",
}


def parse_spec(spec_path: Path) -> CompetitionSpec:
    text = spec_path.read_text()

    title_match = re.search(r"^#\s+Competition:\s*(.+)$", text, re.MULTILINE)
    name = title_match.group(1).strip() if title_match else spec_path.parent.name

    sections = {}
    current_header = None
    current_lines = []

    for line in text.split("\n"):
        header_match = re.match(r"^##\s+(.+)$", line)
        if header_match:
            if current_header:
                sections[current_header] = "\n".join(current_lines).strip()
            current_header = header_match.group(1).strip()
            current_lines = []
        elif current_header:
            current_lines.append(line)

    if current_header:
        sections[current_header] = "\n".join(current_lines).strip()

    parameters = dict(DEFAULTS)
    if "Parameters" in sections:
        for match in re.finditer(r"\*\*(\w+)\*\*:\s*(\S+)", sections["Parameters"]):
            key, val = match.group(1), match.group(2)
            try:
                parameters[key] = int(val)
            except ValueError:
                try:
                    parameters[key] = float(val)
                except ValueError:
                    parameters[key] = val

    docker = dict(DOCKER_DEFAULTS)
    if "Docker" in sections:
        for match in re.finditer(r"\*\*(\w+)\*\*:\s*(.+)", sections["Docker"]):
            docker[match.group(1)] = match.group(2).strip()

    scoring = []
    if "Scoring" in sections:
        for match in re.finditer(r"\*\*(\w+)\*\*:", sections["Scoring"]):
            scoring.append(match.group(1))

    return CompetitionSpec(
        name=name,
        task=sections.get("Task", ""),
        interface=sections.get("Interface", ""),
        validation=sections.get("Validation", ""),
        scoring=scoring or ["runtime", "build_time", "binary_size"],
        parameters=parameters,
        languages=sections.get("Languages", "all").strip(),
        docker=docker,
        raw_sections=sections,
    )
