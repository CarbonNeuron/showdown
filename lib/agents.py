"""Subagent dispatch for generating language solutions."""

from pathlib import Path

from .spec import CompetitionSpec
from .languages import LANGUAGES


BASE_DIR = Path(__file__).parent.parent.resolve()


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


def get_solution_dir(competition: str, lang_key: str) -> Path:
    return BASE_DIR / "competitions" / competition / "languages" / lang_key


def solution_exists(competition: str, lang_key: str) -> bool:
    lang_dir = get_solution_dir(competition, lang_key)
    if not lang_dir.exists():
        return False
    ext = LANGUAGES[lang_key]["ext"]
    has_source = (lang_dir / f"solution.{ext}").exists()
    has_docker = (lang_dir / "Dockerfile").exists()
    return has_source and has_docker
