#!/usr/bin/env python3
"""
Mark a release in CHANGELOG.md after publishing the game from Studio.

    python tools/release.py                    # asks for the type, previews, then confirms
    python tools/release.py --type Content --yes
    python tools/release.py --date 2026-10-20  # published on an earlier day

What it does, in order:
  1. Takes the "## Unreleased" section of CHANGELOG.md.
  2. Renames it to a dated release ("## 2026-10-20 - Content - release-2026-10-20") and leaves a
     fresh, empty Unreleased section above it.
  3. Commits CHANGELOG.md (that file only) and tags the commit release-YYYY-MM-DD.
  4. Pushes the commit and the tag (skip with --no-push).

That is all. gnomecode.com reads this repo's CHANGELOG.md from GitHub every hour (the game's
Repository field on the dashboard), and each dated section becomes an entry in the game's update
log, linked to the code changes since the previous release. Nothing to send, and no key needed.

The file stays the master copy: to correct a past release, edit its section here and push; the
dashboard follows within the hour.

Standard library only, so it runs anywhere Python 3.8+ does.
"""

import argparse
import datetime as dt
import os
import re
import subprocess
import sys

TYPES = ["Content", "Bugfix", "Config", "Misc"]
TAG_PREFIX = "release-"
UNRELEASED_RE = re.compile(r"^## Unreleased[ \t]*$", re.M)
HEADING_RE = re.compile(r"^#{1,2} ", re.M)


def die(msg):
    print("release: " + msg, file=sys.stderr)
    sys.exit(1)


def git(*args, check=True):
    r = subprocess.run(["git", *args], capture_output=True, text=True, encoding="utf-8")
    if check and r.returncode != 0:
        die("git " + " ".join(args) + " failed:\n" + r.stderr.strip())
    return r.stdout.strip()


def confirm(question, assume_yes):
    if assume_yes:
        return True
    return input(question + " [y/N] ").strip().lower() in ("y", "yes")


def main():
    ap = argparse.ArgumentParser(description="Mark a release in CHANGELOG.md after publishing from Studio.")
    ap.add_argument("--type", choices=TYPES, help="the release's type on the website")
    ap.add_argument("--date", help="release date, YYYY-MM-DD (default: today)")
    ap.add_argument("--no-push", action="store_true", help="do not push the commit and tag")
    ap.add_argument("--yes", "-y", action="store_true", help="do not ask for confirmation")
    args = ap.parse_args()

    os.chdir(git("rev-parse", "--show-toplevel"))
    if not os.path.exists("CHANGELOG.md"):
        die("no CHANGELOG.md at the repo root")
    with open("CHANGELOG.md", "rb") as f:
        raw = f.read().decode("utf-8")
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")

    m = UNRELEASED_RE.search(text)
    if not m:
        die("CHANGELOG.md has no '## Unreleased' section")
    nxt = HEADING_RE.search(text, m.end())
    end = nxt.start() if nxt else len(text)
    body = text[m.end():end]
    info = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    info = "\n".join(line.rstrip() for line in info.strip("\n").splitlines()).strip("\n")
    if not info:
        die("the Unreleased section is empty: nothing to release")

    dirty = [l for l in git("status", "--porcelain").splitlines() if not l.endswith("CHANGELOG.md")]
    if dirty:
        print("Uncommitted changes (they will NOT be in the release commit or tag):")
        print("\n".join("  " + l for l in dirty[:15]) + ("\n  ..." if len(dirty) > 15 else ""))
        # Never waved through by --yes: an unattended release of a dirty tree is exactly the case
        # where the tag ends up not matching what was published.
        if args.yes or not confirm("Release anyway?", False):
            die("stopped. Commit or stash them first, then run this again.")

    date = args.date or dt.date.today().isoformat()
    try:
        dt.date.fromisoformat(date)
    except ValueError:
        die("--date must be YYYY-MM-DD")
    rtype = args.type
    if not rtype:
        if args.yes:
            die("--type is required with --yes")
        choice = input(f"Type ({'/'.join(TYPES)}): ").strip().capitalize()
        if choice not in TYPES:
            die(f"type must be one of {', '.join(TYPES)}")
        rtype = choice
    existing = set(git("tag", "-l", TAG_PREFIX + "*").splitlines())
    tag, n = TAG_PREFIX + date, 2
    while tag in existing:
        tag, n = f"{TAG_PREFIX}{date}-{n}", n + 1

    print(f"\n## {date} - {rtype} - {tag}\n")
    print(info + "\n")
    if not confirm("Release this?", args.yes):
        die("stopped. Nothing was changed.")

    # Comments in the Unreleased section are instructions to whoever adds to it, so they stay there
    # for the next release rather than moving into this one.
    notes = "\n".join(re.findall(r"<!--.*?-->", body, flags=re.S))
    new = (text[:m.end()] + "\n\n" + (notes + "\n\n" if notes else "")
           + f"## {date} - {rtype} - {tag}\n\n" + info + "\n\n" + text[end:].lstrip("\n"))
    with open("CHANGELOG.md", "wb") as f:
        f.write((new.replace("\n", "\r\n") if crlf else new).encode("utf-8"))
    git("commit", "-m", f"Release {date}", "--", "CHANGELOG.md")
    git("tag", "-a", tag, "-m", f"{rtype} release {date}")
    print(f"Committed and tagged {tag} ({git('rev-parse', '--short', 'HEAD')}).")

    if args.no_push:
        print(f"Not pushed. The website picks it up once you run: git push origin HEAD {tag}")
        return
    pushed = subprocess.run(["git", "push", "origin", "HEAD", tag], capture_output=True, text=True)
    if pushed.returncode != 0:
        die("push failed, so the website will not see this release until you push:\n  "
            + pushed.stderr.strip().replace("\n", "\n  ") + f"\n  git push origin HEAD {tag}")
    print("Pushed. gnomecode.com picks it up within the hour (or press Sync now on the game's DEV tab).")


if __name__ == "__main__":
    main()
