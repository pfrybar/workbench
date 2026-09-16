# workbench

Docker images for development environments. They're built for [Coder](https://coder.com) workspaces but work with plain Docker too.

The images contain tools, not personal settings. Shell, editor and git configuration come from your own dotfiles, so one image can serve anyone.

## Images

**`workbench:base`** is Ubuntu 26.04 with:

- Docker (the daemon starts with the container) and git
- zsh with [prezto](https://github.com/sorin-ionescu/prezto), tmux, Emacs (terminal), atuin and diff-so-fancy
- [asdf](https://asdf-vm.com) for language runtimes, plus the libraries needed to build Python
- ripgrep, tree, curl, wget, jq, ping, dig, netcat, ssh, rsync, htop, vim and man
- Claude Code and pi, installed into your home on first start so they can update themselves

The user is `dev` (UID 1000), with passwordless sudo and zsh as its shell.

## Build and test

Each machine builds its own architecture (amd64 or arm64):

```sh
docker buildx bake
tests/base.sh             # quick checks, no network needed
tests/base.sh --network   # also Docker-in-Docker and the first-start installs
```

## Run with Docker

Mount a volume at `/home/dev` so your home survives the container. With [sysbox](https://github.com/nestybox/sysbox) on the host:

```sh
docker run -it --rm --runtime=sysbox-runc -v workbench-home:/home/dev workbench:base
```

Without sysbox (Docker Desktop, OrbStack), Docker inside the container needs `--privileged` and a volume for its data:

```sh
docker run -it --rm --privileged -v workbench-home:/home/dev -v workbench-docker:/var/lib/docker workbench:base
```

Or share the host's Docker instead by adding `-v /var/run/docker.sock:/var/run/docker.sock`.

## Use with Coder

`coder/docker/main.tf` is a Docker template for these images. It runs workspaces under sysbox and applies your dotfiles with Coder's dotfiles module. The image has to exist on the Coder host's Docker, so build it there. Pass your dotfiles repo when pushing the template:

```sh
coder templates push workbench -d coder/docker --variable dotfiles_uri=git@github.com:you/dotfiles.git
```

## Dotfiles

The image ships prezto and links `~/.zprezto` to it, since dotfiles normally expect prezto there. Swap the link for your own clone if you'd rather manage it yourself; otherwise the image's copy updates when you rebuild.

The Coder template also installs your Emacs packages on first start: once your dotfiles are applied, the dotfiles module's `post_clone_script` runs Emacs's package install.

## What happens on start

1. The entrypoint starts dockerd, unless a Docker socket is already mounted in or the container isn't allowed to run it.
2. Files from `/etc/skel` that aren't in `$HOME` yet are copied in, since a volume only gets them on its first mount.
3. In the background, Claude Code and pi are installed if missing, and asdf plugins are added. The log is `~/.cache/workbench/setup.log`.
4. Your command runs. With no command, you get a login shell if a terminal is attached; otherwise the container stays up for `docker exec`.

## Where things live

| What | Where | How it updates |
|---|---|---|
| Tools, prezto | the image | rebuild the image |
| asdf plugins and runtimes | `~/.asdf` | `asdf install …` |
| Claude Code | `~/.local/bin/claude` | updates itself, or `claude update` |
| pi | `~/.local/share/pi` | `pi update` |

`pi` is a small launcher that runs pi on the image's own Node.js, so the `node` asdf picks for a project can't break it.

## Settings

| Variable | Default | Effect |
|---|---|---|
| `WORKBENCH_START_DOCKERD` | `1` | `0` skips starting dockerd |
| `WORKBENCH_INSTALL_AGENTS` | `1` | `0` skips installing Claude Code and pi |
| `WORKBENCH_ASDF_PLUGINS` | `python golang nodejs java` | asdf plugins to add; empty for none |

Pinned versions (asdf, the Node.js for pi, prezto, diff-so-fancy) are build arguments at the top of `images/base/Dockerfile`.
