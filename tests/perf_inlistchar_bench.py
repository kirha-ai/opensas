#!/usr/bin/env python3
"""Measure a long character IN list: python3 tests/perf_inlistchar_bench.py."""

import argparse
import pathlib
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default="zig-out/bin/opensas")
    parser.add_argument("--rows", type=int, default=1_000_000)
    parser.add_argument("--keys", type=int, default=1_000)
    args = parser.parse_args()
    if args.rows < 1 or args.keys < 1:
        parser.error("rows and keys must be positive")

    literals = ", ".join(f"'K{i:04d}'" for i in range(args.keys))
    source = (
        "data _null_;\n"
        "  length u $ 8;\n"
        f"  do i = 1 to {args.rows};\n"
        f"    u = 'K{args.keys - 1:04d}';\n"
        f"    if u in ({literals}) then n + 1;\n"
        "  end;\n"
        "  put n=;\n"
        "run;\n"
    )
    binary = pathlib.Path(args.binary).resolve()
    with tempfile.TemporaryDirectory(prefix="inlistchar-") as directory:
        program = pathlib.Path(directory) / "bench.sas"
        program.write_text(source, encoding="ascii")
        start = time.perf_counter()
        result = subprocess.run([binary, program], capture_output=True, text=True)
        elapsed = time.perf_counter() - start
    expected = f"n={args.rows}\n"
    if result.returncode or result.stdout != expected:
        raise SystemExit(
            f"benchmark failed: rc={result.returncode}, stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )
    print(f"character IN: rows={args.rows} keys={args.keys} elapsed={elapsed:.3f}s")


if __name__ == "__main__":
    main()
