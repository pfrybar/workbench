# Workbench

Workbench is a general-purpose Ubuntu 26.04 development image for amd64 and
arm64. It includes Git, zsh, tmux, terminal Emacs, common command-line tools,
build tools, Docker, and Mise for installing additional tools and dotfiles.

The default user is `dev` (UID 1000) with zsh and passwordless sudo. The
default command keeps the container running so you can attach with
`docker exec`. To open a shell directly and persist your home:

```sh
docker run -it --rm -v workbench-home:/home/dev ghcr.io/pfrybar/workbench:base zsh -l
```

To apply a Mise configuration, use `mise bootstrap` inside the container.
Docker clients can use a daemon you explicitly configure. For Docker in
Docker, start `dockerd` with a runtime or container configuration that
supports it.

## Build and test

```sh
docker buildx bake
tests/base.sh
tests/base.sh --network
```

The network tests also exercise Docker in Docker and install a tool with Mise.

## Published images

GitHub Actions tests native builds on amd64 and arm64. Pushes to `main`
publish a multi-architecture image to GitHub Container Registry.

| Tag | Points at |
| --- | --- |
| `ghcr.io/pfrybar/workbench:base` | Latest build of `main` |
| `ghcr.io/pfrybar/workbench:base-sha-<commit>` | Build for a specific commit |
