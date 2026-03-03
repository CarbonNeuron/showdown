# Random Numbers - Results

## Task

Generate N random integers between 1 and 100, printing one per line to stdout.

## Methodology

- **N:** 1,000,000
- **Runs:** 3 (median)
- **Warmup:** 1
- **Containers:** Docker with `--network=none --memory=512m --cpus=1`

## Runtime Performance Rankings

| Rank | Language | Runtime | vs Fastest | Image Size |
|-----:|----------|--------:|-----------:|-----------:|
| 1 | **Rust** | 2.344 s | 1.0x | 27.84 MB |
| 2 | **Go** | 2.361 s | 1.0x | 28.12 MB |
| 3 | **C** | 2.399 s | 1.0x | 26.93 MB |
| 4 | JavaScript | 2.518 s | 1.1x | 75.76 MB |
| 5 | Python | 2.946 s | 1.3x | 41.19 MB |

## How to Run

```bash
python showdown.py all random-numbers
```
