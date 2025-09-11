#!/bin/bash

# This script helps to avoid Cyrillic characters in the codebase:

# Input: list of directories, specified in the code

# Outcome A:
# - non-zero exit code (fail)
# - print the list of files containing Cyrillic characters and the first matching line

# Outcome B:
# - zero exit code (success) if there are no files containing Cyrillic characters

# Fail on errors and undefined variables
set -eu

# Array of matched files (mutable)
cyrillic_file_paths=()

function report_match {
  local file="$1"
  local pattern="${2}"
  # Get first matching line with line number
  local match_line
  match_line=$(grep -n -m1 -E "$pattern" "$file" || true)
  echo "  → First match in '$file':"
  if [[ -n "$match_line" ]]; then
    echo "    $match_line"
  else
    echo "    (in filename)"
  fi
}

function check_file {
  local filename="$@"

  # Note: for some reason this explicit pattern doesn't produce false positives, but the character range does.
  local cyrillic_pattern="[АаБбВвГгДдЕеЁёЖжЗзИиЙйКкЛлМмНнОоПпРрСсТтУуФфХхЦцЧчШшЩщЪъЫыЬьЭэЮюЯя]"

  # Check if name matches or content matches the pattern
  if [[ "$filename" =~ $cyrillic_pattern ]] || grep -q "$cyrillic_pattern" "$filename"; then
    cyrillic_file_paths+=("$filename")
    report_match "$filename" "$cyrillic_pattern"
  fi
}

function list_files_to_check {
  # Configure git for this repo
  # to not transform unicode names into "\320\264\320\266\320\270\320\263\321\203\321\200\320\264\320\260.txt"
  git config core.quotePath false

  # List all files under source control (don't look at gitignored ones)
  # And exclude some specific patterns (directories and extensions)
  git ls-files |
    # Note: script itself contains regex with cyrillic characters
    grep -v 'detect-cyrillic.sh$'
}

function run_check {
  local file_paths=()

  # Note: we use read instead of readarray (from bash v4) for compatibility with Macs
  # Note: append null byte = stop reading
  IFS=$'\n' read -r -d '' -a file_paths < <(list_files_to_check && printf '\0')

  for file_path in "${file_paths[@]}"; do
    check_file "$file_path"
  done

  if ((${#cyrillic_file_paths[@]} == 0)); then
    echo -e "\n"
    echo "✅ No cyrillic files found"
    return 0
  else
    echo -e "\n"
    echo "🚨 Cyrillic files found:"
    echo -e "\n"
    printf "%s\n" "${cyrillic_file_paths[@]}"
    return 1
  fi
}

run_check
