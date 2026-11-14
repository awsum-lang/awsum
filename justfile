_default:
  @ just --list --unsorted

# One-time post-clone setup: install the hook that adds the DCO Signed-off-by trailer to every commit in this clone (CONTRIBUTING.md)
setup-dev:
  git config core.hooksPath scripts/git-hooks
  chmod +x scripts/git-hooks/prepare-commit-msg
  @ echo "✅ DCO prepare-commit-msg hook installed for this clone"
