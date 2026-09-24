# workbench

Docker images for development environments. They're built for [Coder](https://coder.com) workspaces but work with plain Docker too.

The images contain tools, not personal settings. Shell, editor and git configuration come from your own dotfiles, so one image can serve anyone.

## Images

**`workbench:base`** is Ubuntu 26.04 with:

- Docker (the daemon starts with the container) and git
- zsh with [prezto](https://github.com/sorin-ionescu/prezto), tmux, Emacs (terminal), atuin and diff-so-fancy
- [asdf](https://asdf-vm.com) for language runtimes, plus the libraries needed to build Python
- ripgrep, tree, curl, wget, jq, ping, dig, netcat, ssh, rsync, htop, vim and man
- Claude Code, Codex and pi, installed into your home on first start so they can update themselves

The user is `dev` (UID 1000), with passwordless sudo and zsh as its shell.

## Build and test

Each machine builds its own architecture (amd64 or arm64):

```sh
docker buildx bake
tests/base.sh             # quick checks, no network needed
tests/base.sh --network   # also Docker-in-Docker and the first-start installs
```

## Published images

GitHub Actions (`.github/workflows/ci.yml`) lints the scripts and the Coder template, then builds the image on an amd64 runner and an arm64 runner and runs `tests/base.sh --network` on each. Pull requests stop there. Pushes to `main` also publish both builds to GitHub's container registry as one multi-architecture image:

| Tag | Points at |
|---|---|
| `ghcr.io/pfrybar/workbench:base` | the newest build of `main` |
| `ghcr.io/pfrybar/workbench:base-sha-<commit>` | the build of one commit, to pin or roll back to |

GHCR makes a new package private. Make it public in the package's settings, or log the Docker host in to `ghcr.io`, before pulling it.

## Run with Docker

Mount a volume at `/home/dev` so your home survives the container. With [sysbox](https://github.com/nestybox/sysbox) on the host:

```sh
docker run -it --rm --runtime=sysbox-runc -v workbench-home:/home/dev workbench:base
```

Without sysbox (Docker Desktop, OrbStack), Docker inside the container needs `--privileged` and a volume for its data:

```sh
docker run -it --rm --privileged -v workbench-home:/home/dev -v workbench-docker:/var/lib/docker workbench:base
```

Or share the host's Docker instead by adding `-v /var/run/docker.sock:/var/run/docker.sock`. To apply your dotfiles, add `-e WORKBENCH_DOTFILES_REPO=https://github.com/you/dotfiles`.

## Use with Coder

`coder/docker/main.tf` is a Docker template for these images. It runs workspaces under sysbox, passes your dotfiles repo to the image, and shows the image's startup log in the dashboard ("Workbench setup"), holding logins until it's finished. It uses `ghcr.io/pfrybar/workbench:base`, and a workspace start pulls a new build whenever that tag has moved. The package must be public for this, unless you add `registry_auth` for `ghcr.io` to the template's Docker provider. [`coder/docker/README.md`](coder/docker/README.md) covers its prerequisites, variables and how it works. Pass your dotfiles repo when pushing the template:

```sh
coder templates push workbench -d coder/docker --variable dotfiles_uri=https://github.com/you/dotfiles
```

## Dotfiles

The image ships prezto and links `~/.zprezto` to it, since dotfiles normally expect prezto there. Swap the link for your own clone if you'd rather manage it yourself; otherwise the image's copy updates when you rebuild.

Set `WORKBENCH_DOTFILES_REPO` and the image applies your dotfiles on every start, before your first shell. It clones the repo to `~/.dotfiles`, or updates it with `git pull --ff-only` unless you have local changes, then runs its `install.sh` from inside the clone.

If the repo also has an executable `post-install.sh`, it runs afterwards in the background. That's the place for slower steps, like installing Emacs packages. It runs on every start, so make it safe to repeat.

The clone can't prompt for credentials, so a private repo needs them available inside the container when it starts.

## What happens on start

1. The entrypoint starts dockerd, unless a Docker socket is already mounted in or the container isn't allowed to run it.
2. If `WORKBENCH_DOTFILES_REPO` is set, your dotfiles are cloned or updated, and their `install.sh` runs.
3. Files from `/etc/skel` that aren't in `$HOME` yet are copied in, since a volume only gets them on its first mount.
4. In the background: your dotfiles' `post-install.sh`, then Claude Code, Codex and pi if missing, then asdf plugins. Everything is logged to `~/.cache/workbench/setup.log`, and `~/.cache/workbench/setup-status` says `ok` or `failed` when it's done.
5. Your command runs. With no command, you get a login shell if a terminal is attached; otherwise the container stays up for `docker exec`.

## Where things live

| What | Where | How it updates |
|---|---|---|
| Tools, prezto | the image | rebuild the image |
| asdf plugins and runtimes | `~/.asdf` | `asdf install …` |
| Claude Code | `~/.local/bin/claude` | updates itself, or `claude update` |
| Codex | `~/.local/bin/codex`, `~/.codex/packages` | `codex update` |
| pi | `~/.local/share/pi` | `pi update` |

`pi` is a small launcher that runs pi on the image's own Node.js, so the `node` asdf picks for a project can't break it.

## Settings

| Variable | Default | Effect |
|---|---|---|
| `WORKBENCH_DOTFILES_REPO` | none | Dotfiles repo to clone and install on every start |
| `WORKBENCH_START_DOCKERD` | `1` | `0` skips starting dockerd |
| `WORKBENCH_INSTALL_AGENTS` | `1` | `0` skips installing Claude Code, Codex and pi |
| `WORKBENCH_ASDF_PLUGINS` | `python golang nodejs java` | asdf plugins to add; empty for none |

Pinned versions (asdf, the Node.js for pi, prezto, diff-so-fancy) are build arguments at the top of `images/base/Dockerfile`.
