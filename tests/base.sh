#!/usr/bin/env bash
# Smoke tests for workbench:base. Build first, then:
#
#   tests/base.sh             quick checks, no network needed
#   tests/base.sh --network   also Docker-in-Docker and the first-start installs
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

# A throwaway container with no dockerd and no network installs.
run() {
  docker run --rm -e WORKBENCH_START_DOCKERD=0 -e WORKBENCH_INSTALL_AGENTS=0 \
    -e WORKBENCH_ASDF_PLUGINS= "$IMAGE" "$@"
}

check "user is dev (uid 1000, zsh, passwordless sudo)" run bash -c '
  [[ $(id -un):$(id -u) == dev:1000 && $(getent passwd dev | cut -d: -f7) == /usr/bin/zsh ]] &&
  sudo -n true'
check "tools are on PATH" run bash -c '
  for c in git zsh tmux emacs atuin rg tree diff-so-fancy asdf docker dockerd curl wget \
           ping dig nc ssh rsync htop jq unzip xz zstd less man vim python3 make gcc; do
    command -v "$c" >/dev/null || { echo "missing: $c"; exit 1; }
  done'
check "UTF-8 locale" run bash -c '[[ $(locale charmap) == UTF-8 ]]'
check "man pages" run man -w git
check "tmux-256color terminfo" run infocmp tmux-256color
check "emacs runs" run emacs --batch --eval '(kill-emacs 0)'
check "prezto loads" run zsh -c 'source /usr/local/share/zsh/prezto/init.zsh'
check "diff-so-fancy runs" run bash -c '
  printf "%s\n" "--- a/f" "+++ b/f" "@@ -1 +1 @@" "-old" "+new" | diff-so-fancy'
check "asdf runs" run asdf version
check "pi's Node is >= 22.19" run /opt/workbench/node/bin/node -e '
  const [major, minor] = process.versions.node.split(".").map(Number);
  process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1)'
check "home is seeded, no zsh new-user wizard" run bash -c '
  [[ -f ~/.zshrc ]] && ! zsh -i -c exit </dev/null 2>&1 | grep -q "new users"'

check "~/.zprezto points at the image's prezto" run zsh -c '
  [[ -L ~/.zprezto ]] && source ~/.zprezto/init.zsh'
check "dotfiles: clone, install.sh, then post-install.sh" run bash -c '
  wait_for_setup() {
    for _ in {1..60}; do [[ -f ~/.cache/workbench/setup-status ]] && return; sleep 0.5; done
  }
  wait_for_setup
  git init -q /tmp/dotfiles && cd /tmp/dotfiles &&
    printf "#!/bin/sh\ntouch ~/.installed\n" >install.sh &&
    printf "#!/bin/sh\ntouch ~/.post-installed\n" >post-install.sh &&
    chmod +x install.sh post-install.sh && git add . &&
    git -c user.name=test -c user.email=test@example.invalid commit -qm fixture || exit 1
  cd ~ && WORKBENCH_DOTFILES_REPO=/tmp/dotfiles workbench-init >/dev/null && wait_for_setup
  [[ -d ~/.dotfiles/.git && -f ~/.installed && -f ~/.post-installed &&
     $(cat ~/.cache/workbench/setup-status) == ok ]]'

if [[ ${1:-} == --network ]]; then
  check "dockerd starts under --privileged" docker run --rm --privileged -v /var/lib/docker \
    -e WORKBENCH_INSTALL_AGENTS=0 -e WORKBENCH_ASDF_PLUGINS= "$IMAGE" \
    docker info --format '{{.ServerVersion}}'
  check "first start installs Claude Code, pi and asdf plugins; pi updates itself" \
    docker run --rm -e WORKBENCH_START_DOCKERD=0 "$IMAGE" bash -c '
      for _ in {1..300}; do [[ -f ~/.cache/workbench/setup-status ]] && break; sleep 1; done
      cat ~/.cache/workbench/setup.log
      [[ $(cat ~/.cache/workbench/setup-status) == ok ]] || exit 1
      claude --version && pi --version && asdf plugin list || exit 1
      # Neither pi nor `pi update` may depend on whichever node comes first on PATH.
      printf "#!/bin/sh\nexit 1\n" >~/.local/bin/node && chmod +x ~/.local/bin/node
      pi --version && pi update --self --force && pi --version'
fi

if ((failures)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
