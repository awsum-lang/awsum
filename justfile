_default:
  @ just --list --unsorted

# TODO: drop-package-cache
# TODO: setup-tooling
# TODO: check-tooling
# TODO: weeder
# TODO: rerun-weeder
# TODO: lint-check
# TODO: lint-fix

# Run tests
test:
  stack test --pedantic
  @echo "\n\n✅ Test completed!\n\n"

test-watch:
  stack test --pedantic --file-watch

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

show-binary-sizes:
  #!/bin/sh
  set -eu
  du -h $(stack path --dist-dir)/build/awsum/awsum

# Format all source files and apply fixes
format-fix:
  @ ormolu --mode inplace $(find awsum src test -name '*.hs')
  @echo "\n\n✅ Formatting completed!\n\n"

# Run precommit for backend and webapp, fix issues where possible
precommit-fix:
  #!/bin/sh
  set -eu
  echo "Detecting cyrillic..."
  bash scripts/detect-cyrillic.sh
  echo "Format..."
  just format-fix
  # echo "Lint..."
  # just lint-fix  # disabled for nightly
  echo "Clean..."
  just clean
  echo "Build..."
  just build-tests
  # echo "Weeder..."
  # just weeder # disabled because this tool is not configured well enough to be used in precommit yet.
  echo "Test..."
  just test
