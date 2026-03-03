# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Showdown is a programming language benchmark framework. It defines competitions via SPEC.md files, generates per-language solutions using AI subagents, builds Docker images, benchmarks them in isolated containers, and produces ranked reports.

## Commands

```bash
# Full pipeline (generate → build → run → report)
python showdown.py all <competition>

# Individual stages
python showdown.py init <name>              # scaffold new competition
python showdown.py generate <name>          # dispatch AI subagents to write solutions
python showdown.py build <name>             # build Docker images
python showdown.py run <name>               # benchmark in containers
python showdown.py report <name>            # generate RESULTS.md from results.json
python showdown.py list                     # show all competitions with status

# Target specific languages
python showdown.py build <name> --lang rust go
python showdown.py run <name> --lang rust --n 1000  # custom problem size

# Regenerate existing solutions
python showdown.py generate <name> --lang python --force
```

There are no formal tests, linter, or package manager configured. The project is plain Python 3.12+ with no dependencies beyond the standard library and Docker.

## Architecture

**Pipeline:** SPEC → Generate → Build → Run → Report

- `showdown.py` — CLI entry point with argparse subcommands. All `cmd_*` functions live here. Uses `BASE_DIR = Path(__file__).parent.resolve()` as the root for all path resolution.
- `lib/spec.py` — Parses `SPEC.md` markdown into a `CompetitionSpec` dataclass. Sections are identified by `## Heading` markers. Parameters have defaults (N=1M, timeout_build=120s, timeout_run=300s, warmup=1, bench_runs=3).
- `lib/languages.py` — Registry of 32 languages as a `LANGUAGES` dict mapping key → `{ext, name, compiled}`. `resolve_languages("all")` returns all keys.
- `lib/agents.py` — `build_agent_prompt()` assembles a structured prompt from the spec for AI subagents to produce `solution.<ext>` + `Dockerfile`. `solution_exists()` checks for both files.
- `lib/docker.py` — `build_image()` and `run_container()` wrap Docker CLI via subprocess. Containers run with `--network=none --memory=512m --cpus=1`. Image naming: `showdown-{competition}-{lang}`.
- `lib/benchmark.py` — `run_benchmark()` does warmup runs, bench runs, median calculation, output validation, and image size capture. Returns `BenchResult` dataclass. Validation rules: line count, integer check, range check, sorted check.
- `lib/report.py` — Generates `RESULTS.md` (ranked markdown table) and `results.json` (machine-readable). Includes `format_time()` and `format_size()` helpers.

## Competition Structure

```
competitions/<name>/
├── SPEC.md              # task definition (parsed by lib/spec.py)
├── languages/<lang>/    # solution.<ext> + Dockerfile per language
├── results.json         # benchmark output (machine-readable)
└── RESULTS.md           # generated report (human-readable)
```

## Key Conventions

- Solutions must produce two files: `solution.<ext>` and a `Dockerfile` with `ENTRYPOINT` accepting N as its argument.
- Compiled languages use multi-stage Docker builds; interpreted languages use single-stage.
- The `generate` command skips languages that already have solutions unless `--force` is passed.
- Docker images use the naming convention `showdown-{competition}-{lang}`.
- All SPEC.md parsing is section-based (`## Task`, `## Interface`, `## Validation`, `## Scoring`, `## Parameters`, `## Languages`, `## Docker`).
