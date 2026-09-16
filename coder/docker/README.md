---
display_name: Workbench
description: Docker workspaces running the workbench image, with Docker inside and your dotfiles applied on every start
icon: /icon/docker.png
maintainer_github: pfrybar
tags: [docker, container, sysbox]
---

# Workbench on Docker

Provision Docker containers running the [workbench](https://github.com/pfrybar/workbench) image as Coder workspaces. Workspaces run under [sysbox](https://github.com/nestybox/sysbox), so Docker works inside them without privileged containers, and your dotfiles are applied every time a workspace starts.

<!-- prerequisites:start -->

## Prerequisites

### Workspace image

The template uses `ghcr.io/pfrybar/workbench:base` by default, which the workbench repo's CI builds for amd64 and arm64. It includes Docker, git, zsh with prezto, tmux, Emacs, asdf, atuin, ripgrep and common command-line tools, and it installs Claude Code and pi into the home directory on first start. The [workbench README](https://github.com/pfrybar/workbench) has the full list.

The template pulls the image without credentials, so the GHCR package must be public. For a private package, add `registry_auth` for `ghcr.io` to the template's Docker provider.

### Infrastructure

The Coder host needs:

- **Docker**, with the `coder` user in the `docker` group:

  ```sh
  sudo adduser coder docker
  sudo systemctl restart coder
  sudo -u coder docker ps
  ```

- **Sysbox**, registered with Docker as the `sysbox-runc` runtime. See [installing sysbox](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md) and Coder's [Docker in workspaces](https://coder.com/docs/admin/templates/extending-templates/docker-in-workspaces) guide.
- **A Docker network named `coder-workspaces`**, which every workspace container joins:

  ```sh
  docker network create coder-workspaces
  ```

- **Access to `ghcr.io`**, to pull the image.

<!-- prerequisites:end -->

## Variables

Set these when pushing the template, for example:

```sh
coder templates push workbench -d coder/docker \
  --variable dotfiles_uri=https://github.com/you/dotfiles
```

| Variable | Default | Description |
|---|---|---|
| `image` | `ghcr.io/pfrybar/workbench:base` | Workspace image in a registry. Use a `base-sha-<commit>` tag to stay on one build. |
| `dotfiles_uri` | `https://github.com/pfrybar/dotfiles` | Dotfiles repository applied on every start. Empty for none. |
| `docker_socket` | empty | Docker socket URI, if not the default. |
| `cert_path` | empty | Directory holding TLS certificates for the Docker host. |

## Parameters

When creating a workspace, you can set:

- **(Optional) Git repository to clone:** the [git-clone](https://registry.coder.com/modules/coder/git-clone) module clones it into your home directory.

## Architecture

This template provisions the following resources:

- **Docker image**, pulled from the registry when a workspace starts. A start pulls again only if the tag has moved to a new build. Images stay on the host after workspaces stop, so prune old builds now and then.
- **Docker container (ephemeral)**, recreated on every start, running under sysbox on the `coder-workspaces` network.
- **Docker volume (persistent)** at `/home/dev`.
- **Coder agent**, with dashboard metadata for the workspace's CPU, memory and home disk usage, and the host's CPU, memory, load and swap.
- **Apps and scripts:** [code-server](https://registry.coder.com/modules/coder/code-server), git-clone, and a "Workbench setup" script.

Only `/home/dev` persists. That's where your dotfiles clone, asdf runtimes, Claude Code, pi and shell history live. Everything else resets when the workspace restarts, including images and containers you create with Docker inside it.

The template sets no Git environment variables, so Git identity and commit signing come from your dotfiles.

### What happens on start

1. The image's entrypoint starts Docker inside the container.
2. If `dotfiles_uri` is set, the image clones the repo into `~/.dotfiles` (or updates it) and runs its `install.sh`.
3. In the background, the image runs the dotfiles' `post-install.sh`, installs Claude Code and pi if they're missing, and adds asdf plugins.
4. The entrypoint starts Coder's agent. The container sets `command` rather than `entrypoint`, so the image's entrypoint always runs first.
5. The "Workbench setup" script waits for step 3, prints that start's setup log in the dashboard, and holds logins until it's done. It fails if any step failed; the full log is in `~/.cache/workbench/setup.log`.

## Updating

- **The image:** merging to workbench's `main` publishes a new `base` build, and each workspace picks it up on its next start. No template push is needed.
- **The template:** edit `main.tf`, run `terraform fmt` and `terraform validate`, then push it with `coder templates push workbench -d coder/docker`.
