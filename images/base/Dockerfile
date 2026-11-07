# workbench base image: a general-purpose development environment.
# It holds tools only. Personal configuration comes from each user's dotfiles.

FROM ubuntu:26.04

ARG TARGETARCH
ARG USERNAME=dev
ARG USER_UID=1000

ARG NODE_VERSION=24.21.0
ARG PASEO_VERSION=0.15.3
# Signing key of ppa:git-core/ppa, as published by Launchpad.
ARG GIT_PPA_FINGERPRINT=F911AB184317630C59970973E363C90F8F1B6217

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# The Ubuntu image is minimized. Keep man pages for everything installed below,
# and remove the stub that stands in for `man`.
RUN sed -i '\|^path-exclude=/usr/share/man/|d' /etc/dpkg/dpkg.cfg.d/excludes \
 && rm -f /usr/bin/man \
 && dpkg-divert --quiet --local --rename --remove /usr/bin/man

# Extra package repositories: Docker CE, the latest git and the GitHub CLI.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL -o /etc/apt/keyrings/docker.asc https://download.docker.com/linux/ubuntu/gpg \
 && curl -fsSL -o /etc/apt/keyrings/git-core.asc \
      "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x${GIT_PPA_FINGERPRINT}" \
 && curl -fsSL -o /etc/apt/keyrings/githubcli.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
 && . /etc/os-release \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list \
 && echo "deb [signed-by=/etc/apt/keyrings/git-core.asc] https://ppa.launchpadcontent.net/git-core/ppa/ubuntu ${VERSION_CODENAME} main" \
      > /etc/apt/sources.list.d/git-core.list \
 && echo "deb [signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      # Everyday tools
      locales sudo tini less man-db vim htop tree ripgrep jq \
      wget rsync openssh-client unzip xz-utils zstd \
      iputils-ping bind9-dnsutils netcat-openbsd iproute2 \
      # Shell and editor
      git zsh tmux emacs-nox \
      # GitHub CLI, Docker
      gh docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
      # Compilers
      build-essential pkgconf python3 \
 && rm -rf /var/lib/apt/lists/* \
 && locale-gen en_US.UTF-8

COPY --from=ghcr.io/jdx/mise:2026.11.2 \
    /usr/local/bin/mise /usr/local/bin/mise

RUN mise --version

# A Node.js just for running Paseo. It stays off PATH: users get their own Node
# from mise, and Paseo's launcher calls this one by its full path.
RUN case "$TARGETARCH" in amd64) arch=x64 ;; arm64) arch=arm64 ;; esac \
 && tarball="node-v${NODE_VERSION}-linux-${arch}.tar.xz" \
 && cd /tmp \
 && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${tarball}" \
 && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " ${tarball}\$" | sha256sum -c - \
 && mkdir -p /opt/workbench/node \
 && tar -xJf "$tarball" -C /opt/workbench/node --strip-components=1 \
 && rm -rf "$tarball" /opt/workbench/node/include /opt/workbench/node/share/doc

RUN PATH="/opt/workbench/node/bin:$PATH" \
    /opt/workbench/node/bin/npm install \
      --global \
      --prefix /opt/workbench/paseo \
      --no-audit \
      --no-fund \
      "@getpaseo/cli@${PASEO_VERSION}"

# Launch Paseo using the image's dedicated Node runtime,
# independently of mise-managed project Node versions.
RUN printf '%s\n' \
      '#!/bin/sh' \
      'exec /opt/workbench/node/bin/node /opt/workbench/paseo/lib/node_modules/@getpaseo/cli/bin/paseo "$@"' \
      > /usr/local/bin/paseo \
 && chmod 755 /usr/local/bin/paseo

RUN paseo --version

# Replace the image's `ubuntu` user (also UID 1000) with ours.
RUN userdel -r ubuntu \
 && useradd --create-home --shell /usr/bin/zsh --uid "$USER_UID" --user-group --groups docker "$USERNAME" \
 && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
 && chmod 0440 "/etc/sudoers.d/$USERNAME"

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PATH=/home/${USERNAME}/.local/share/mise/shims:/home/${USERNAME}/.local/bin:${PATH}

USER ${USERNAME}
WORKDIR /home/${USERNAME}
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]
