#!/usr/bin/env bash
# Smoke tests for workbench:base. Build first, then:
#
#   tests/base.sh             quick checks, no network needed
#   tests/base.sh --network   also Docker-in-Docker and a tool installed by mise
#
# The checks hand their commands to bash -c in single quotes on purpose: they
# expand inside the container, not here.
# shellcheck disable=SC2016
set -uo pipefail

IMAGE=${IMAGE:-workbench:base}
failures=0

check() {
  local name=$1 out
  shift
  if out=$("$@" 2>&1); then
    printf 'ok    %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name"
    printf '%s\n' "$out" | sed 's/^/      /'
    failures=$((failures + 1))
  fi
}

# A throwaway container.
run() {
  docker run --rm "$IMAGE" "$@"
}

# The image starts nothing itself: Coder starts dockerd and Paseo.
starts_nothing() {
  local id result=0
  id=$(docker run -d "$IMAGE") || return 1
  docker exec "$id" bash -c '
    [[ $(ps -o comm= -p 1) == tini ]] || { echo "PID 1 is not tini"; exit 1; }
    ! pgrep -x dockerd || { echo "dockerd is running"; exit 1; }
    ! pgrep -x node || { echo "Paseo (node) is running"; exit 1; }' || result=1
  docker rm -f "$id" >/dev/null
  return "$result"
}

check "user is dev (uid 1000, zsh, passwordless sudo)" run bash -c '
  [[ $(id -un):$(id -u) == dev:1000 && $(getent passwd dev | cut -d: -f7) == /usr/bin/zsh ]] &&
  sudo -n true'
check "tools are on PATH" run bash -c '
  for c in git gh zsh tmux emacs vim mise paseo docker dockerd curl wget ping dig nc \
           ssh rsync htop jq rg tree unzip xz zstd less man python3 make gcc; do
    command -v "$c" >/dev/null || { echo "missing: $c"; exit 1; }
  done'
check "UTF-8 locale" run bash -c '[[ $(locale charmap) == UTF-8 ]]'
check "man pages" run man -w git
check "tmux-256color terminfo" run infocmp tmux-256color
check "emacs runs" run emacs --batch --eval '(kill-emacs 0)'
check "default command keeps the container up and starts nothing" starts_nothing
check "mise's shims are on PATH" run bash -c '[[ ":$PATH:" == *":$HOME/.local/share/mise/shims:"* ]]'
check "the image's Node is not on PATH" run bash -c '! command -v node'
check "paseo runs on the image's Node, whatever node is on PATH" run bash -c '
  mkdir -p ~/.local/bin && printf "#!/bin/sh\nexit 1\n" >~/.local/bin/node &&
  chmod +x ~/.local/bin/node && paseo --version'
check "mise bootstrap applies a user's repo" run bash -c '
  git init -q /tmp/repo && cd /tmp/repo && mkdir home &&
  printf "from the repo\n" >home/dot-testrc &&
  printf "%s\n" "[dotfiles.\"~\"]" "source = \"~/.dotfiles/home\"" "mode = \"copy\"" \
    "dot_prefix = true" "[tasks.bootstrap]" "run = \"touch ~/.bootstrapped\"" >config.toml &&
  git add . && git -c user.name=test -c user.email=test@example.invalid commit -qm fixture || exit 1
  cd ~ && mise bootstrap --from /tmp/repo --from-dir ~/.dotfiles --config-dir . --yes >/dev/null || exit 1
  [[ $(cat ~/.testrc) == "from the repo" && -f ~/.bootstrapped && ~/.config/mise -ef ~/.dotfiles ]]'

if [[ ${1:-} == --network ]]; then
  check "Docker-in-Docker under --privileged, once dockerd is started" \
    docker run --rm --privileged -v /var/lib/docker "$IMAGE" bash -c '
      sudo /etc/init.d/docker start >/dev/null || exit 1
      for _ in {1..60}; do docker info >/dev/null 2>&1 && break; sleep 0.5; done
      docker run --rm hello-world'
  # A pinned version, so mise downloads the release without asking GitHub's API.
  check "mise installs a tool, and its shim works without a shell" run bash -c '
    mise use --global --yes yq@4.44.3 >/dev/null && yq --version'
fi

if ((failures)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
