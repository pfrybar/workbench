# Default zsh setup from the workbench image. Your own dotfiles replace this file.

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt share_history hist_ignore_all_dups

bindkey -e
PROMPT='%n@%m:%~%# '
