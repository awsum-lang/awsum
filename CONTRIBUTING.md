# Contributing to Awsum

Thanks for your interest in contributing.

## Building and testing

The repository holds layer 0: an interpreter in C, and a compiler in Awsum layer0 that emits LLVM IR. [README.md](README.md#building) says how to build it and check it. Before opening a pull request, run the tests of the layer:

```sh
cd layer0
just test
```

## Developer Certificate of Origin

By contributing to Awsum you certify the [Developer Certificate of Origin](https://developercertificate.org/) (DCO) for your contribution: you wrote the patch yourself, or otherwise have the right to submit it under the project's Apache-2.0 license.

After cloning, run once:

```sh
just setup-dev
```

It installs the `prepare-commit-msg` hook from [scripts/git-hooks/](scripts/git-hooks/), which adds a `Signed-off-by` trailer with the name and email of your git config to every commit in this clone.

## Signed commits

`main` requires signed commits: every commit of a pull request needs a verified signature, GPG or SSH, as [GitHub's documentation](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification) describes.

## Pull requests

- Open them against `main`.
- A bug fix lands with a test case that fails before the fix and passes after it.
