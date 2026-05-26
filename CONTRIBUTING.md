# Contributing to Awsum

Thanks for your interest in contributing.

## Development setup

See [README.md](README.md) for installation and [CLAUDE.md](CLAUDE.md) for the project layout. Quick reference:

```bash
just build      # Build with pedantic warnings
just test       # Run all tests
just fix        # Format, lint, build, test (run before pushing)
```

## Developer Certificate of Origin

By contributing to Awsum you certify the [Developer Certificate of Origin](https://developercertificate.org/) (DCO) for your contribution — a short statement that you wrote the patch yourself, or otherwise have the right to submit it under the project's [Apache-2.0 license](LICENSE). The full text is at the link above.

After cloning, run once:

```bash
just setup-dev
```

This installs the `prepare-commit-msg` hook from [scripts/git-hooks/](scripts/git-hooks/) (via per-clone `core.hooksPath`), which adds a `Signed-off-by` trailer to every commit you make in this clone:

```
Signed-off-by: Your Name <you@example.com>
```

The trailer uses the name and email from your `[user]` section in `~/.gitconfig` (the same one used for signed commits below). No manual flags, no global gitconfig changes. The setup is per-clone — repeat in each clone of the repo.

## Signed commits

Separately from the DCO trailer above, the `main` branch requires signed commits — every commit you push to a PR needs a verified signature (GPG or SSH), otherwise the merge button stays grey.

Minimal `~/.gitconfig` for SSH signing:

```ini
[user]
	email = ...
	name = ...
	signingkey = ~/.ssh/id_ed25519.pub
[commit]
	gpgsign = true
[gpg]
	format = ssh
```

For GPG signing instead, set `gpg.format = openpgp` (or omit — that's the default) and point `signingkey` at your GPG key ID. The option name `gpgsign` is git's historical name for "sign this thing" and applies regardless of format.

The same key file must be added to GitHub Settings → SSH and GPG keys as a **Signing Key** (a separate category from Authentication Key, even if you reuse the same file). Verify locally:

```bash
git commit -S -m "test" --allow-empty
git log --show-signature -1
```

If you already made unsigned commits on a feature branch, retroactively sign with:

```bash
git rebase --exec 'git commit --amend --no-edit -S' <range>
```

then force-push your branch.

## Pull requests

- Open against `main`. CI (`check-and-build.yml`) must be green before merge.
- Any new functionality lands together with the tests that exercise it — see [docs/testing.md](docs/testing.md#workflow-when-finishing-a-feature) for the workflow.
- For user-visible changes, add a bullet under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md), grouped by Keep-a-Changelog section (`Added` / `Changed` / `Fixed` / `Removed`). Infrastructure-only changes (CI, dev tooling, internal refactors) still get an entry so the next release notes are complete.
- Run `just fix` before pushing — it runs the same checks CI does (format, lint, build, test), faster locally.
