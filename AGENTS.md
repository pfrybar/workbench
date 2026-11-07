# AGENTS.md

A generic Docker image for development environments (`workbench:base`), and a
Coder template that runs it. `README.md` is for people using the image.

## Layout

- `images/base/Dockerfile`: the image.
- `tests/base.sh`: smoke tests for the built image.
- `coder/docker/main.tf`: the Coder template. Coder shows
  `coder/docker/README.md` next to it, so keep that README in step with
  `main.tf` and use full URLs in it.
- `.github/workflows/ci.yml`: lints, builds and tests on amd64 and arm64, and
  publishes to GHCR from `main` only.

## Build and test

```sh
docker buildx bake          # builds workbench:base for this machine's architecture
tests/base.sh               # quick checks, no network needed
tests/base.sh --network     # also Docker-in-Docker and a tool installed by mise
shellcheck tests/base.sh
```

Check the template after changing it (terraform runs in Docker, so it needn't
be installed):

```sh
docker run --rm -v "$PWD/coder/docker:/w:ro" -w /w hashicorp/terraform fmt -check
docker run --rm -v "$PWD/coder/docker:/w:ro" --entrypoint sh hashicorp/terraform -c \
  'cp -r /w /tmp/w && cd /tmp/w && terraform init -backend=false -input=false >/dev/null && terraform validate'
```

Add a check to `tests/base.sh` for new behavior.

## Rules

- The image is generic: base tools, mise and Paseo. Nothing personal; users
  install their own tools and dotfiles with mise.
- The image starts nothing. The Coder template starts dockerd and Paseo.
- Don't add packages unless the maintainer asks.
- Build for amd64 and arm64; use `TARGETARCH` for downloads that differ.
- The Node in `/opt/workbench/node` only runs Paseo. Keep it off `PATH`.
- In the template, set the container's `command`, not `entrypoint`, and create
  registry and image resources only while a workspace starts
  (`count = data.coder_workspace.me.start_count`).
- `coder_script` bodies run under the user's shell (zsh): keep them POSIX `sh`
  and avoid names zsh reserves, such as `status`.
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
