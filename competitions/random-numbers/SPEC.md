# Competition: Random Numbers

## Task
Generate N random integers between 1 and 100, printing one per line to stdout.

## Interface
- **Input:** Single command-line argument `N` (integer)
- **Output:** N lines to stdout, each an integer in [1, 100]
- **Exit code:** 0 on success, non-zero on error

## Validation
- Exactly N lines of output
- Each line is a valid integer
- Each line is in [1, 100]

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
