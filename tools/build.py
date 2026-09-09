#!/usr/bin/env python3
"""Compile the project headlessly with Igor, and report GML errors.

Lifted from the Wordsearch project, which is where the discovery that this
works at all was made. The installed runtime ships `Igor.exe`, it matches the
IDE version in the `.yyp`, and a cached build takes a couple of seconds. So a
change can be *compiled* rather than eyeballed, and the whole class of mistakes
a static checker only approximates -- a typo'd variable, a script that does not
parse -- is caught by the real compiler instead.

`check_project.py` is still worth running, because the two see different
things: Igor compiles GML but says nothing about a room instance missing from
`instanceCreationOrder`, and it will happily build a project whose `.yy` files
GameMaker's *IDE* would refuse to open. Run both.

Usage:
    python tools/build.py            # compile, report errors, exit non-zero on failure
    python tools/build.py --run      # compile and launch the game
    python tools/build.py --clean    # discard the cache first (slower)

The build artefacts go to a scratch folder outside the project so they never
end up in the repo or in front of GameMaker's asset scanner.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RUNTIME = r"C:\ProgramData\GameMakerStudio2\Cache\runtimes\runtime-2024.14.2.256"
USER = os.path.join(os.environ.get("APPDATA", ""), "GameMakerStudio2",
                    "bussylmao_5100662")
IGOR = os.path.join(RUNTIME, "bin", "igor", "windows", "x64", "Igor.exe")

BUILD = os.path.join(tempfile.gettempdir(), "bullethell_build")

# Windows' CreateProcess show-window request. **This is where "the harness does
# not take over the screen" actually lives**, and both tools go through it.
#
# `option_windows_start_fullscreen` used to be on, so every harness run changed
# the display mode and raised a borderless window over everything else before a
# line of GML could object -- see `obj_boot`'s Create for that half. Turning it
# off stops the game seizing the *display*; it does not stop the window
# appearing and taking the foreground, and a run launched from a terminal the
# user is looking at inherits the right to do exactly that.
#
# So the process is started minimised and un-activated. GameMaker keeps
# rendering into it -- measured: a `-shot` run launched this way saves the same
# 1864x1048 screenshot with the same content, because `screen_save` reads the
# game's own surface and never the desktop -- so nothing is given up.
#
# **`window_set_visible(false)` is the version of this that does not work.**
# From inside GML it stops the game stepping at all, so `room_test` never runs
# and `tools/test.py` reports its timeout. Minimising from outside is a
# different thing and the runner is happy with it.
SW_SHOWMINNOACTIVE = 7


def _background_startupinfo():
    """STARTUPINFO that opens the game minimised, without stealing focus."""
    if os.name != "nt":
        return None
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    si.wShowWindow = SW_SHOWMINNOACTIVE
    return si


def run_game(cmd, timeout, show=False):
    """Run the built game and hand back the finished process.

    ``show`` opens it normally, for the rare run somebody actually wants to
    watch -- `shot.py --fullscreen` is the one that asks, because a minimised
    full screen is a contradiction.
    """
    return subprocess.run(cmd, capture_output=True, text=True,
                          errors="replace", timeout=timeout,
                          cwd=os.path.dirname(cmd[0]),
                          startupinfo=None if show else _background_startupinfo())



def project_name():
    for fn in os.listdir(ROOT):
        if fn.endswith(".yyp"):
            return fn[:-4]
    raise SystemExit("no .yyp found in %s" % ROOT)


# Igor prints compiler diagnostics in a handful of shapes. These are the ones
# that mean the build is broken, as opposed to the ones that are just noise.
ERROR_PATTERNS = (
    re.compile(r"^Error ?:", re.I),
    re.compile(r"\bError\b.*\bat line\b", re.I),
    re.compile(r"^.*\.gml\(\d+"),           # foo.gml(12,3): ...
    re.compile(r"Compile failed", re.I),
    re.compile(r"^\s*at gml_", re.I),
    re.compile(r"Unhandled exception", re.I),
)

# ...and the lines that match the above but are harmless.
IGNORE = (
    re.compile(r"^Igor complete", re.I),
    re.compile(r"DoIcon|DoVersion|PlatformOptions"),
)


def looks_like_error(line):
    if any(p.search(line) for p in IGNORE):
        return False
    return any(p.search(line) for p in ERROR_PATTERNS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", action="store_true", help="launch the game after building")
    ap.add_argument("--clean", action="store_true", help="discard the build cache first")
    ap.add_argument("-v", "--verbose", action="store_true", help="show all Igor output")
    args = ap.parse_args()

    if not os.path.exists(IGOR):
        raise SystemExit("Igor not found at %s" % IGOR)

    name = project_name()
    cache = os.path.join(BUILD, "cache")
    temp = os.path.join(BUILD, "temp")
    out = os.path.join(BUILD, "out")

    if args.clean:
        shutil.rmtree(BUILD, ignore_errors=True)
    for d in (cache, temp, out):
        os.makedirs(d, exist_ok=True)

    cmd = [
        IGOR,
        "--project=%s" % os.path.join(ROOT, name + ".yyp"),
        "--rp=%s" % RUNTIME,
        "--uf=%s" % USER,
        "--config=Default",
        "--runtime=VM",
        "--cache=%s" % cache,
        "--temp=%s" % temp,
        "--of=%s" % os.path.join(out, name + ".zip"),
        "--tf=%s.zip" % name,
        "--",
        "Windows",
        "Run" if args.run else "PackageZip",
    ]

    # **Run from the build folder, not the project.** `--tf` names the target
    # archive and Igor writes it relative to the working directory, so running
    # from ROOT drops a multi-megabyte zip in the project root -- in front of
    # GameMaker's asset scanner, and into git as an untracked file. Nothing
    # here needs the project as its cwd; `--project` is absolute.
    proc = subprocess.run(cmd, capture_output=True, text=True,
                          errors="replace", cwd=BUILD)
    output = (proc.stdout or "") + (proc.stderr or "")
    lines = output.splitlines()

    errors = [ln for ln in lines if looks_like_error(ln)]

    if args.verbose:
        print(output)

    if errors or proc.returncode != 0:
        print("BUILD FAILED (exit %d)" % proc.returncode)
        if errors:
            print()
            # Dedupe while preserving order -- Igor repeats each diagnostic.
            seen = set()
            for ln in errors:
                key = ln.strip()
                if key in seen:
                    continue
                seen.add(key)
                print("  " + key)
        elif not args.verbose:
            print()
            print("\n".join(lines[-25:]))
        return 1

    print("Build OK  (%s)" % name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
