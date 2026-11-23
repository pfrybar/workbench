# workbench base image: a general-purpose development environment.
# It holds tools only. Personal configuration comes from each user's dotfiles.

FROM ubuntu:26.04

ARG USERNAME=dev
ARG USER_UID=1000

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# The Ubuntu image is minimized. Keep man pages for everything installed below,
# and remove the stub that stands in for `man`.
RUN sed -i '\|^path-exclude=/usr/share/man/|d' /etc/dpkg/dpkg.cfg.d/excludes \
 && rm -f /usr/bin/man \
 && dpkg-divert --quiet --local --rename --remove /usr/bin/man

# Install Docker CE from its upstream package repository.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL -o /etc/apt/keyrings/docker.asc https://download.docker.com/linux/ubuntu/gpg \
 && . /etc/os-release \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list \
 && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      # Everyday tools
      locales sudo tini less man-db vim htop tree ripgrep jq \
      wget rsync openssh-client unzip xz-utils zstd \
      iputils-ping bind9-dnsutils netcat-openbsd iproute2 \
      # Shell and editor
      git zsh tmux emacs-nox \
      # Docker
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
      # Compilers
      build-essential pkgconf python3 \
 && rm -rf /var/lib/apt/lists/* \
 && locale-gen en_US.UTF-8

COPY --from=ghcr.io/jdx/mise:2026.11.2 \
    /usr/local/bin/mise /usr/local/bin/mise

# zsh completion for mise, where zsh looks first, as Homebrew's mise has. It
# completes by calling this mise, so it always matches its version.
RUN mise --version \
 && mkdir -p /usr/local/share/zsh/site-functions \
 && mise completion zsh > /usr/local/share/zsh/site-functions/_mise

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
