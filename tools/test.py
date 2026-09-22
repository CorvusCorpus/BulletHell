#!/usr/bin/env python3
"""Build the game, run its self-tests, and report.

Launches the built executable with `-selftest`, which runs the suites in
`scripts/selftest` and quits before drawing a frame, then reads the results
(`SELFTEST PASS/FAIL/DONE` lines) back off stdout.

Usage:
    python tools/test.py
    python tools/test.py -v     # print every assertion, not just failures
"""
import argparse
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build

ROOT = build.ROOT
EXE = os.path.join(build.BUILD, "out", build.project_name() + ".exe")

TIMEOUT = 180


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    if _compile() != 0:
        return 1

    if not os.path.exists(EXE):
        print("no executable at %s" % EXE)
        return 1

    try:
        # Minimised and without focus (see `build.run_game`).
        proc = build.run_game([EXE, "-selftest"], TIMEOUT)
    except subprocess.TimeoutExpired:
        print("FAILED: the self-test did not finish within %ds" % TIMEOUT)
        print("A run-time throw is a MODAL BOX, which from here is a hang and "
              "not a failure. Suspect an undefined macro, an unregistered "
              "script, or a call with the wrong argument count.")
        return 1

    output = (proc.stdout or "") + (proc.stderr or "")

    passes = []
    fails = []
    done = None
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("SELFTEST PASS "):
            passes.append(line[len("SELFTEST PASS "):])
        elif line.startswith("SELFTEST FAIL "):
            fails.append(line[len("SELFTEST FAIL "):])
        elif line.startswith("SELFTEST DONE "):
            done = line[len("SELFTEST DONE "):]

    if done is None:
        print("FAILED: the self-test produced no result line.")
        print("Last 30 lines of output:")
        print("\n".join(output.splitlines()[-30:]))
        return 1

    if args.verbose:
        for p in passes:
            print("  pass  %s" % p)

    for f in fails:
        print("  FAIL  %s" % f)

    print()
    print("%d passed, %d failed" % (len(passes), len(fails)))
    return 1 if fails else 0


def _compile():
    """Run build.py's main with no arguments of our own."""
    argv = sys.argv
    sys.argv = ["build.py"]
    try:
        return build.main()
    finally:
        sys.argv = argv


if __name__ == "__main__":
    sys.exit(main())
