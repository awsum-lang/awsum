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
