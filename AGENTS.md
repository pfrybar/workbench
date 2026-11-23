# AGENTS.md

A generic Docker image for development environments. The README is for people
using the image.

## Layout

- `images/base/Dockerfile`: the image.
- `tests/base.sh`: smoke tests for the built image.
- `.github/workflows/ci.yml`: lints, builds and tests on amd64 and arm64, and
  publishes to GHCR from `main` only.

## Build and test

```sh
docker buildx bake          # builds workbench:base for this machine's architecture
tests/base.sh               # quick checks, no network needed
tests/base.sh --network     # also Docker-in-Docker and a tool installed by mise
shellcheck tests/base.sh
```

Add a check to `tests/base.sh` for new behavior.

## Rules

- The image is generic: base tools and mise. Users install their tools and
  dotfiles with mise.
- The image starts no services.
- Don't add packages unless the maintainer asks.
- Build for amd64 and arm64.
- Shell scripts use 2-space indentation and start with a comment saying what
  they do. Comments explain why, not what.

## Commits and pull requests

- Commit on a branch, never `main`. Write an imperative subject line; add a
  short body when the reason isn't obvious from the diff.
- End the message with a `Co-Authored-By` trailer naming the agent and model,
  such as `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Commits are SSH-signed. If signing fails, stop and report it; don't use
  `--no-gpg-sign`.
- You can't push to `origin`. Push to your account's fork and open a pull
  request; the maintainer reviews and merges it:

  ```sh
  gh repo fork --remote --remote-name fork   # once per clone
  gh repo set-default pfrybar/workbench      # once per clone
  git push -u fork HEAD
  gh pr create --fill
  ```
