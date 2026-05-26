#!/usr/bin/env bash
# Verify that two independent `stack build` runs of HEAD produce a byte-identical
# `awsum` binary on macOS. Use for iterative reproducibility debugging — run,
# read the diffoscope output, add a fix to package.yaml or to the codesign step
# below, re-run.
#
# Two builds run from independent `git worktree` clones of the current HEAD, so
# both filesystem path and wall-clock time differ between them. `STACK_ROOT` is
# left at the user default (~/.stack) so dependency builds are reused — only
# the local `awsum` package is rebuilt from scratch in each worktree.
#
# Prereqs:
#   - stack (any recent version)
#   - codesign (preinstalled with macOS Command Line Tools)
#   - diffoscope (brew install diffoscope) — only needed if builds differ
#
# Usage from awsum/ on a clean working tree (no uncommitted changes):
#   scripts/verify-reproducible-build-macos.sh

set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
  echo "This script targets macOS only. Got: $(uname)" >&2
  exit 2
fi

if ! git diff --quiet HEAD --; then
  echo "Working tree has uncommitted changes. Commit or stash first — reproducibility is per-SHA." >&2
  exit 2
fi

SHA="$(git rev-parse HEAD)"
EPOCH="$(git log -1 --pretty=%ct "$SHA")"
echo "Verifying reproducibility at $SHA (epoch $EPOCH)"

WORKDIR="$(mktemp -d -t awsum-repro)"
DIR_A="$WORKDIR/a"
DIR_B="$WORKDIR/b"

cleanup() {
  # Always unregister the worktrees so subsequent runs (and `git worktree list`)
  # stay clean. The user can re-create them if they want to inspect.
  git worktree remove --force "$DIR_A" 2>/dev/null || true
  git worktree remove --force "$DIR_B" 2>/dev/null || true
  git worktree prune
}
trap cleanup EXIT

git worktree add --detach "$DIR_A" "$SHA" > /dev/null
git worktree add --detach "$DIR_B" "$SHA" > /dev/null

build_and_sign() {
  local dir=$1
  ( cd "$dir"
    SOURCE_DATE_EPOCH="$EPOCH" \
    MACOSX_DEPLOYMENT_TARGET=14.0 \
      stack build --pedantic --copy-bins --local-bin-path target

    # ld64's "deterministic" -random_uuid actually varies between builds for
    # our link line; zero the LC_UUID bytes so the binary content is stable
    # before codesign.
    python3 scripts/zero-macho-uuid.py target/awsum

    # Re-sign with ad-hoc identity and no Apple TSA timestamp. --force overwrites
    # the linker's auto-applied ad-hoc signature (which uses wall-clock).
    codesign --sign - --options runtime --timestamp=none --force target/awsum
  )
}

echo ""
echo "=== Build A ($DIR_A) ==="
build_and_sign "$DIR_A"

echo ""
echo "=== Build B ($DIR_B) ==="
build_and_sign "$DIR_B"

SHA_A="$(shasum -a 256 "$DIR_A/target/awsum" | cut -d' ' -f1)"
SHA_B="$(shasum -a 256 "$DIR_B/target/awsum" | cut -d' ' -f1)"

echo ""
echo "=== Hashes ==="
echo "A: $SHA_A  ($DIR_A/target/awsum)"
echo "B: $SHA_B  ($DIR_B/target/awsum)"

if [ "$SHA_A" = "$SHA_B" ]; then
  echo ""
  echo "OK: byte-identical."
  exit 0
fi

echo ""
echo "DIFFER. Running diffoscope (install with 'brew install diffoscope' if missing)."
echo ""

if ! command -v diffoscope > /dev/null; then
  echo "diffoscope not in PATH. Run: brew install diffoscope" >&2
  echo "Binaries kept for manual inspection:"
  echo "  $DIR_A/target/awsum"
  echo "  $DIR_B/target/awsum"
  # Keep the worktrees so the user can run diffoscope themselves.
  trap - EXIT
  exit 1
fi

# Copy the binaries out of the worktrees before we tear those down, so the user
# can re-run diffoscope or otool against them.
KEEP_DIR="$WORKDIR/diff"
mkdir -p "$KEEP_DIR"
cp "$DIR_A/target/awsum" "$KEEP_DIR/awsum-a"
cp "$DIR_B/target/awsum" "$KEEP_DIR/awsum-b"

diffoscope --max-report-size=500000 "$KEEP_DIR/awsum-a" "$KEEP_DIR/awsum-b" || true

echo ""
echo "Binaries preserved at:"
echo "  $KEEP_DIR/awsum-a"
echo "  $KEEP_DIR/awsum-b"
echo ""
echo "Useful follow-up commands:"
echo "  diffoscope $KEEP_DIR/awsum-a $KEEP_DIR/awsum-b      # full report"
echo "  otool -lv  $KEEP_DIR/awsum-a | less                  # all Mach-O load commands"
echo "  codesign --display --verbose=4 $KEEP_DIR/awsum-a    # signature details"
exit 1
