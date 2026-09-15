# workbench base image: a general-purpose development environment.
# It holds tools only. Personal configuration comes from each user's dotfiles.

FROM ubuntu:26.04

ARG TARGETARCH
ARG USERNAME=dev
ARG USER_UID=1000

# Pinned downloads: bump each version together with its checksums.
ARG ASDF_VERSION=0.20.0
ARG ASDF_SHA256_AMD64=9c25e1af7cc4c9d59ff3736eba14fd000480c32929258f80d8c5a8b290ebee14
ARG ASDF_SHA256_ARM64=bbc1889886a9826ce3f57f56e4bae575767a4af3d35d649d62116ee14334e59a
ARG DIFF_SO_FANCY_VERSION=1.4.12
ARG DIFF_SO_FANCY_SHA256=fc94b757a65d39792727ec18aff6a33d7f16506842c48b37b662b8222b88eb51
# Checked against nodejs.org's SHASUMS256.txt at build time.
ARG NODE_VERSION=24.21.0
ARG PREZTO_COMMIT=cff2d01871425b1b80710f8ec6a475c5a53145b4
# Signing key of ppa:git-core/ppa, as published by Launchpad.
ARG GIT_PPA_FINGERPRINT=F911AB184317630C59970973E363C90F8F1B6217

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# The Ubuntu image is minimized. Keep man pages for everything installed below,
# and remove the stub that stands in for `man`.
RUN sed -i '\|^path-exclude=/usr/share/man/|d' /etc/dpkg/dpkg.cfg.d/excludes \
 && rm -f /usr/bin/man \
 && dpkg-divert --quiet --local --rename --remove /usr/bin/man

# Extra package repositories: Docker CE and the latest git.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL -o /etc/apt/keyrings/docker.asc https://download.docker.com/linux/ubuntu/gpg \
 && curl -fsSL -o /etc/apt/keyrings/git-core.asc \
      "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x${GIT_PPA_FINGERPRINT}" \
 && . /etc/os-release \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list \
 && echo "deb [signed-by=/etc/apt/keyrings/git-core.asc] https://ppa.launchpadcontent.net/git-core/ppa/ubuntu ${VERSION_CODENAME} main" \
      > /etc/apt/sources.list.d/git-core.list \
 && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      # Everyday tools
      locales sudo tini less man-db vim htop tree ripgrep jq \
      wget rsync openssh-client unzip xz-utils zstd \
      iputils-ping bind9-dnsutils netcat-openbsd iproute2 \
      # Shell and editor
      git zsh tmux atuin emacs-nox \
      # Docker, started by the entrypoint
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
      # Compilers, plus the libraries asdf needs to build Python
      build-essential pkgconf python3 \
      libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncurses-dev \
      libffi-dev liblzma-dev libgdbm-dev libgdbm-compat-dev uuid-dev libzstd-dev \
 && rm -rf /var/lib/apt/lists/* \
 && locale-gen en_US.UTF-8

# asdf manages language runtimes. Its plugins and installed versions live in $HOME.
RUN case "$TARGETARCH" in \
      amd64) sum=$ASDF_SHA256_AMD64 ;; \
      arm64) sum=$ASDF_SHA256_ARM64 ;; \
      *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o /tmp/asdf.tar.gz \
      "https://github.com/asdf-vm/asdf/releases/download/v${ASDF_VERSION}/asdf-v${ASDF_VERSION}-linux-${TARGETARCH}.tar.gz" \
 && echo "${sum}  /tmp/asdf.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/asdf.tar.gz -C /usr/local/bin asdf \
 && rm /tmp/asdf.tar.gz

RUN curl -fsSL -o /usr/local/bin/diff-so-fancy \
      "https://github.com/so-fancy/diff-so-fancy/releases/download/v${DIFF_SO_FANCY_VERSION}/diff-so-fancy" \
 && echo "${DIFF_SO_FANCY_SHA256}  /usr/local/bin/diff-so-fancy" | sha256sum -c - \
 && chmod 755 /usr/local/bin/diff-so-fancy

# A Node.js just for running pi. It stays off PATH so it never competes with
# the versions asdf manages.
RUN case "$TARGETARCH" in amd64) arch=x64 ;; arm64) arch=arm64 ;; esac \
 && tarball="node-v${NODE_VERSION}-linux-${arch}.tar.xz" \
 && cd /tmp \
 && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${tarball}" \
 && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " ${tarball}\$" | sha256sum -c - \
 && mkdir -p /opt/workbench/node \
 && tar -xJf "$tarball" -C /opt/workbench/node --strip-components=1 \
 && rm -rf "$tarball" /opt/workbench/node/include /opt/workbench/node/share/doc

# prezto, pinned. Dotfiles load it from here when there's no ~/.zprezto.
RUN git clone --quiet https://github.com/sorin-ionescu/prezto.git /usr/local/share/zsh/prezto \
 && git -C /usr/local/share/zsh/prezto -c advice.detachedHead=false checkout --quiet "$PREZTO_COMMIT" \
 && git -C /usr/local/share/zsh/prezto submodule --quiet update --init --recursive \
 && find /usr/local/share/zsh/prezto -name .git -prune -exec rm -rf {} +

COPY rootfs/ /

# Replace the image's `ubuntu` user (also UID 1000) with ours.
RUN userdel -r ubuntu \
 && useradd --create-home --shell /usr/bin/zsh --uid "$USER_UID" --user-group --groups docker "$USERNAME" \
 && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
 && chmod 0440 "/etc/sudoers.d/$USERNAME"

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    ASDF_DATA_DIR=/home/${USERNAME}/.asdf \
    PATH=/home/${USERNAME}/.asdf/shims:/home/${USERNAME}/.local/bin:${PATH}

USER ${USERNAME}
WORKDIR /home/${USERNAME}
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/workbench-entrypoint"]
