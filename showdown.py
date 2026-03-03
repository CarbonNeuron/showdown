#!/usr/bin/env python3
"""Showdown - Programming Language Benchmark Framework"""

import argparse
import sys
from pathlib import Path

BASE_DIR = Path(__file__).parent.resolve()

GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"


def cmd_init(args):
    name = args.name
    comp_dir = BASE_DIR / "competitions" / name
    if comp_dir.exists():
        print(f"{RED}Competition '{name}' already exists at {comp_dir}{RESET}")
        sys.exit(1)

    comp_dir.mkdir(parents=True)
    (comp_dir / "languages").mkdir()

    template = (BASE_DIR / "templates" / "SPEC.md").read_text()
    spec_text = template.replace("{name}", name)
    (comp_dir / "SPEC.md").write_text(spec_text)

    print(f"{GREEN}Created competition '{name}' at {comp_dir}{RESET}")
    print(f"  Edit {comp_dir / 'SPEC.md'} to define the task.")


def cmd_generate(args):
    from lib.spec import parse_spec
    from lib.languages import resolve_languages, LANGUAGES
    from lib.agents import build_agent_prompt, solution_exists

    name = args.name
    spec_path = BASE_DIR / "competitions" / name / "SPEC.md"
    if not spec_path.exists():
        print(f"{RED}No SPEC.md found at {spec_path}{RESET}")
        sys.exit(1)

    spec = parse_spec(spec_path)

    if args.lang:
        target_langs = args.lang
    else:
        target_langs = resolve_languages(spec.languages)

    if not args.force:
        missing = [l for l in target_langs if not solution_exists(name, l)]
        if not missing:
            print(f"{GREEN}All solutions already exist. Use --force to regenerate.{RESET}")
            return
        target_langs = missing

    print(f"{BOLD}Generating {len(target_langs)} solutions for '{name}'...{RESET}\n")

    for lang in target_langs:
        lang_name = LANGUAGES.get(lang, {}).get("name", lang)
        prompt = build_agent_prompt(name, lang, spec)
        print(f"  {CYAN}Dispatching subagent for {lang_name}...{RESET}")
        print(f"  {DIM}Prompt length: {len(prompt)} chars{RESET}")

    print(f"\n{GREEN}Done. {len(target_langs)} agents dispatched.{RESET}")


def cmd_build(args):
    from lib.spec import parse_spec
    from lib.languages import resolve_languages, LANGUAGES
    from lib.docker import build_image

    name = args.name
    spec_path = BASE_DIR / "competitions" / name / "SPEC.md"
    if not spec_path.exists():
        print(f"{RED}No SPEC.md found at {spec_path}{RESET}")
        sys.exit(1)

    spec = parse_spec(spec_path)

    if args.lang:
        target_langs = args.lang
    else:
        target_langs = resolve_languages(spec.languages)

    langs_dir = BASE_DIR / "competitions" / name / "languages"
    available = [l for l in target_langs if (langs_dir / l / "Dockerfile").exists()]

    if not available:
        print(f"{YELLOW}No solutions found. Run 'showdown generate {name}' first.{RESET}")
        return

    print(f"{BOLD}Building {len(available)} Docker images for '{name}'...{RESET}")

    for i, lang in enumerate(available, 1):
        lang_name = LANGUAGES.get(lang, {}).get("name", lang)
        print(f"  [{i}/{len(available)}] {lang_name}...", end=" ", flush=True)

        ok, elapsed, err = build_image(name, lang)
        if ok:
            print(f"{GREEN}OK ({elapsed:.1f}s){RESET}")
        else:
            print(f"{RED}FAIL: {err[:100]}{RESET}")


def cmd_run(args):
    from lib.spec import parse_spec
    from lib.languages import resolve_languages, LANGUAGES
    from lib.benchmark import run_benchmark
    from lib.report import save_results_json, format_time

    name = args.name
    spec_path = BASE_DIR / "competitions" / name / "SPEC.md"
    if not spec_path.exists():
        print(f"{RED}No SPEC.md found at {spec_path}{RESET}")
        sys.exit(1)

    spec = parse_spec(spec_path)
    n = args.n or spec.parameters.get("default_n", 1000000)

    if args.lang:
        target_langs = args.lang
    else:
        target_langs = resolve_languages(spec.languages)

    langs_dir = BASE_DIR / "competitions" / name / "languages"
    available = [l for l in target_langs if (langs_dir / l / "Dockerfile").exists()]

    if not available:
        print(f"{YELLOW}No solutions found. Run 'showdown generate {name}' first.{RESET}")
        return

    print(f"{BOLD}Benchmarking {len(available)} languages for '{name}' (N={n:,})...{RESET}\n")

    results = []
    for i, lang in enumerate(available, 1):
        lang_name = LANGUAGES.get(lang, {}).get("name", lang)
        print(f"  [{i}/{len(available)}] {lang_name}...", end=" ", flush=True)

        r = run_benchmark(name, lang, spec, n)
        results.append(r)

        if r.error:
            print(f"{RED}FAIL: {r.error}{RESET}")
        else:
            print(f"{GREEN}{format_time(r.run_time_median_s)}{RESET}")

    path = save_results_json(name, spec, results, n)
    print(f"\n{DIM}Results saved to {path}{RESET}")


def cmd_report(args):
    from lib.spec import parse_spec
    from lib.report import generate_report

    name = args.name
    spec_path = BASE_DIR / "competitions" / name / "SPEC.md"
    if not spec_path.exists():
        print(f"{RED}No SPEC.md found at {spec_path}{RESET}")
        sys.exit(1)

    spec = parse_spec(spec_path)

    path = generate_report(name, spec)
    print(f"{GREEN}Report generated at {path}{RESET}")


def cmd_all(args):
    from lib.spec import parse_spec
    from lib.languages import resolve_languages, LANGUAGES

    name = args.name
    spec_path = BASE_DIR / "competitions" / name / "SPEC.md"
    if not spec_path.exists():
        print(f"{RED}No SPEC.md found at {spec_path}{RESET}")
        sys.exit(1)

    # Generate missing solutions
    cmd_generate(args)

    # Build
    cmd_build(args)

    # Run
    cmd_run(args)

    # Report
    cmd_report(args)


def cmd_list(args):
    comps_dir = BASE_DIR / "competitions"
    if not comps_dir.exists():
        print("No competitions found.")
        return

    found = False
    for d in sorted(comps_dir.iterdir()):
        if d.is_dir() and (d / "SPEC.md").exists():
            found = True
            has_results = (d / "results.json").exists()
            lang_count = sum(1 for l in (d / "languages").iterdir() if l.is_dir()) if (d / "languages").exists() else 0
            status = f"{GREEN}benchmarked{RESET}" if has_results else f"{YELLOW}spec only{RESET}"
            print(f"  {BOLD}{d.name}{RESET}  [{status}]  {lang_count} languages")

    if not found:
        print("No competitions found.")


def main():
    parser = argparse.ArgumentParser(
        prog="showdown",
        description="Programming Language Benchmark Framework",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    sub_init = subparsers.add_parser("init", help="Create a new competition")
    sub_init.add_argument("name")

    sub_generate = subparsers.add_parser("generate", help="Generate solutions via subagents")
    sub_generate.add_argument("name")
    sub_generate.add_argument("--lang", nargs="*")
    sub_generate.add_argument("--force", action="store_true")

    sub_build = subparsers.add_parser("build", help="Build Docker images")
    sub_build.add_argument("name")
    sub_build.add_argument("--lang", nargs="*")

    sub_run = subparsers.add_parser("run", help="Run benchmarks")
    sub_run.add_argument("name")
    sub_run.add_argument("--lang", nargs="*")
    sub_run.add_argument("--n", type=int)

    sub_report = subparsers.add_parser("report", help="Generate results report")
    sub_report.add_argument("name")

    sub_all = subparsers.add_parser("all", help="Full pipeline")
    sub_all.add_argument("name")
    sub_all.add_argument("--lang", nargs="*")
    sub_all.add_argument("--force", action="store_true")
    sub_all.add_argument("--n", type=int)

    sub_list = subparsers.add_parser("list", help="List competitions")

    args = parser.parse_args()

    commands = {
        "init": cmd_init,
        "generate": cmd_generate,
        "build": cmd_build,
        "run": cmd_run,
        "report": cmd_report,
        "all": cmd_all,
        "list": cmd_list,
    }

    commands[args.command](args)


if __name__ == "__main__":
    main()
