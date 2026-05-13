_default:
  @ just --list --unsorted

lint-check:
  hlint .

lint-fix:
  #!/bin/sh
  set -eu
  # Note: on `find`: it produces a list of all .hs files instead of passing the current directory to hlint. It is required for `--refactor` to work:
  # `hlint: Refactor flag can only be used with an individual file`
  find . -name '*.hs' | xargs -L1 hlint --refactor --refactor-options="--inplace"

# Run tests (excludes property tests — use `just test-property` for those)
test:
  stack test --pedantic --ta '--skip "Property tests"'
  @echo "\n\n✅ Test completed!\n\n"

test-watch:
  stack test --pedantic --file-watch --ta '--skip "Property tests"'

# Run only property-based tests (slow: spawns 5 backends per generated input)
test-property:
  stack test --pedantic --ta '--match "Property tests"'
  @echo "\n\n✅ Property tests completed!\n\n"

# Run the tree-sitter fast tests:
#   * `corpus`  — parse every .aww under test/sources/successful/,
#                 test/sources/property/ and test/sources/formatting/
#                 via ../tree-sitter-awsum and assert no ERROR /
#                 MISSING nodes. formatting/ is included because
#                 malformed-but-recoverable input is exactly where
#                 the scanner has historically regressed (the
#                 22-GiB-runaway bug surfaced on
#                 formatting/improperly-formatted-source/).
#   * `queries` — run every .scm under ../tree-sitter-awsum/queries/
#                 against every .aww in the corpus and assert no
#                 query-validation errors.
# Fast, deterministic — the natural baseline for grammar work.
#
# Regenerates parser.c from grammar.js first so scanner.c / grammar.js edits
# are picked up.
# Skipped silently inside the spec if `tree-sitter` is not on PATH
# or ../tree-sitter-awsum is missing (override the latter with
# TREE_SITTER_AWSUM_DIR).
test-tree-sitter:
  #!/bin/sh
  set -eu
  if [ -d "../tree-sitter-awsum" ] && command -v tree-sitter >/dev/null 2>&1; then
    (cd ../tree-sitter-awsum && tree-sitter generate)
  fi
  stack test --pedantic --flag awsum:tree-sitter-tests awsum:test:tree-sitter-tests --ta '--match "tree-sitter-awsum/" --skip "tree-sitter-awsum/property"'
  echo "\n\n✅ tree-sitter corpus + queries completed!\n\n"

# Run the tree-sitter property test (~100 generated programs against
# the same grammar). Use after `just test-tree-sitter` is green.
test-tree-sitter-property:
  #!/bin/sh
  set -eu
  if [ -d "../tree-sitter-awsum" ] && command -v tree-sitter >/dev/null 2>&1; then
    (cd ../tree-sitter-awsum && tree-sitter generate)
  fi
  stack test --pedantic --flag awsum:tree-sitter-tests awsum:test:tree-sitter-tests --ta '--match "tree-sitter-awsum/property"'
  echo "\n\n✅ tree-sitter property completed!\n\n"

# Clean build artefacts (may help with weird compilation issues)
clean:
  stack clean
  @echo "\n\n✅ Clean completed!\n\n"

# Build
build:
  stack build --pedantic

# Non-pedantic build, useful when you want a sucessful build to get HLS to work
build-sloppy:
  stack build

# Build in file-watch mode (rebuild on changes)
build-watch:
  stack build --pedantic --file-watch

# Build tests, don't run them
build-tests:
  stack build --pedantic --test --no-run-tests

# Build tests, don't run them (rebuild on changes)
build-tests-watch:
  stack build --pedantic --test --no-run-tests --file-watch

# Aggregate linearity statistics across every program under test/sources/successful/.
# Phase A.2 of the memory-safety roadmap: see how big a fraction of binders is linear (count==1)
# vs unused (==0) vs multi (>1), broken down by binder kind (Param / CasePattern / RowCaseBinder).
stat-linearity:
  stack run awsum-stats --

# Run a single benchmark program through every backend with timing + peak RSS
# (per-backend timeout via gtimeout — default 60s; override with `just benchmark NAME 90`).
# Sources live under test/sources/benchmark/<NAME>/code/Main.aww.
# macOS-only at the moment (BSD `/usr/bin/time -l`, `gtimeout` from coreutils).
benchmark TEST timeout="60":
  stack run awsum-bench -- {{TEST}} --timeout {{timeout}}

show-binary-sizes:
  #!/bin/sh
  set -eu
  du -h $(stack path --dist-dir)/build/awsum/awsum

# Format all source files and apply fixes
format-fix:
  @ ormolu --mode inplace $(find awsum src test -name '*.hs')
  @echo "\n\n✅ Formatting completed!\n\n"

# Confirm potentially dangerous actions with a specific confirmation input (e.g. version, environment name)
[private]
manual-confirmation-input message required_confirmation:
  #!/bin/sh
  set -eu

  message="{{ message }}"
  required_confirmation="{{ required_confirmation }}"

  echo "$message"
  echo "Type '$required_confirmation' to confirm:"
  read response

  if [ "$response" != "$required_confirmation" ]; then
    echo "Confirmation failed. Exiting..."
    exit 1
  fi

# Tag and push the version currently in package.yaml. Run after the prep PR is merged into main.
release:
  #!/bin/sh
  set -eu
  git checkout main
  git pull
  version=$(grep '^version:' package.yaml | awk '{print $2}')
  just manual-confirmation-input "About to tag and push v$version" "$version"
  git tag -a "v$version" -m "Release $version"
  git push origin "v$version"

# Run precommit for backend and webapp, fix issues where possible
fix:
  #!/bin/sh
  set -eu
  echo "Detecting cyrillic..."
  bash scripts/detect-cyrillic.sh
  echo "Format..."
  just format-fix
  echo "Lint..."
  just lint-fix
  echo "Clean..."
  just clean
  echo "Build..."
  just build-tests
  # echo "Weeder..."
  # just weeder # disabled because this tool is not configured well enough to be used in precommit yet.
  echo "Test..."
  just test
  just test-property
