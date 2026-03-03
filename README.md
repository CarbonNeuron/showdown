# Showdown

Programming language benchmark competitions. Docker-isolated. Subagent-generated.

## Quick Start

```bash
# Create a new competition
python showdown.py init my-competition

# Edit the spec
vim competitions/my-competition/SPEC.md

# Run everything (generate solutions + build + benchmark + report)
python showdown.py all my-competition

# Or run individual stages
python showdown.py generate my-competition          # Write solutions via AI subagents
python showdown.py build my-competition              # Build Docker images
python showdown.py run my-competition                # Benchmark in containers
python showdown.py report my-competition             # Generate RESULTS.md
```

## Competitions

Each competition lives in `competitions/<name>/` with:
- `SPEC.md` -- defines the task, I/O contract, validation, and scoring
- `languages/<lang>/` -- per-language solution + Dockerfile
- `results.json` -- machine-readable benchmark data
- `RESULTS.md` -- human-readable results report

## Adding a Language

```bash
# Generate one language for an existing competition
python showdown.py generate sorting --lang rust

# Re-benchmark just that language
python showdown.py build sorting --lang rust
python showdown.py run sorting --lang rust
python showdown.py report sorting
```

## How It Works

1. **SPEC.md** defines the task in markdown (human + AI readable)
2. **Subagents** write per-language implementations + Dockerfiles in parallel
3. **Docker** isolates each language with its own dependencies
4. **Benchmark** runs containers with `--network=none --memory=512m --cpus=1`
5. **Report** generates ranked results with timing, build size, and image size
