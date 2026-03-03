# Competition: {name}

## Task
Describe what the program should do.

## Interface
- **Input:** How the program receives input (args, stdin, files)
- **Output:** What the program should produce on stdout
- **Exit code:** 0 on success, non-zero on error

## Validation
- List of rules to verify output correctness

## Scoring
- **runtime**: Wall-clock execution time (primary sort)
- **build_time**: Wall-clock compilation/build time
- **binary_size**: Size of compiled artifact or source

## Parameters
- **default_n**: 1000000
- **timeout_build**: 120
- **timeout_run**: 300
- **warmup_runs**: 1
- **bench_runs**: 3

## Languages
all

## Docker
- **base_image**: ubuntu:24.04
- **max_image_size**: 2GB
