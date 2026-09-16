# Agent guide

Docker images for development environments. They're built for Coder workspaces but work with plain Docker too. `README.md` covers building, running and settings.

## Layout

- `images/base/Dockerfile`: the `workbench:base` image.
- `images/base/rootfs/`: files copied into the image as-is, including the startup scripts in `usr/local/bin/`.
- `docker-bake.hcl`: build definitions for `docker buildx bake`.
- `tests/base.sh`: smoke tests for the built image.
- `coder/docker/main.tf`: a Coder template for the images.

## Principles

- **Tools, not personal settings.** Anyone should be able to use the image. Personal configuration comes from the dotfiles repo in `WORKBENCH_DOTFILES_REPO`.
- **Keep it lean.** Don't add packages or tools unless the maintainer asks for them.
- **`$HOME` is a persistent volume.** Files the image puts in `/home/dev` only reach a volume on its first mount. Put defaults in `/etc/skel`; `workbench-init` copies in any that are missing on every start.
- **Anything that updates itself lives in `$HOME`.** Coder recreates the container on every start, so anything outside `$HOME` resets to the image. That's why `workbench-init` installs Claude Code, pi and asdf plugins at start.
- **Startup never breaks the container.** The entrypoint and `workbench-init` run on every start. Keep them idempotent, don't use `set -e`, and put slow or network work in the background, logged to `~/.cache/workbench/setup.log`.
- **amd64 and arm64.** Use `TARGETARCH` for architecture-specific downloads, and update a download's version together with its checksums for both architectures.

## Coder template

- The container sets `command`, not `entrypoint`, so the image's entrypoint runs before Coder's agent.
- Settings the image reads at start go in the container's `env`. The agent's `env` only reaches agent sessions and scripts.
- `coder_script` bodies run under the user's shell, which is zsh. Keep them POSIX `sh` and avoid names zsh reserves, such as `status`.
- After editing, run `terraform fmt` and `terraform validate`. Neither checks the shell inside scripts, so test that separately.

## Testing

Each machine builds its own architecture:

```sh
docker buildx bake
tests/base.sh             # quick checks, no network needed
tests/base.sh --network   # also Docker-in-Docker and the first-start installs
```

Add a check to `tests/base.sh` for new behavior.

CI (`.github/workflows/ci.yml`) runs shellcheck on the scripts, `terraform fmt -check` and `terraform validate` on the template, and `tests/base.sh --network` on native amd64 and arm64 runners. Only builds that pass are published, and only from `main`.

## Style

- Shell scripts use 2-space indentation and start with a comment saying what the script does.
- Comments explain why, not what.

## Commits

- Write an imperative subject line. Add a short body when the reason isn't obvious from the diff.
- End the message with a `Co-Authored-By` trailer naming the agent and model, such as `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Commits are SSH-signed. If signing fails, stop and report it instead of committing with `--no-gpg-sign`.
- Don't push; the maintainer pushes.
