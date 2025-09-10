# ~/.zshrc

# ------------------------------------------------------------------------------
# ENVIRONMENT & ZINIT SETUP
# ------------------------------------------------------------------------------

# Set the directory for zinit and its plugins
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"

# Download Zinit if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
  mkdir -p "$(dirname "$ZINIT_HOME")"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source Zinit
source "${ZINIT_HOME}/zinit.zsh"

# ------------------------------------------------------------------------------
# PLUGINS & SNIPPETS (Loaded with Zinit)
# ------------------------------------------------------------------------------

# --- Core Plugins ---
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-completions
zinit light Aloxaf/fzf-tab
zinit light wfxr/forgit # Interactive git commands with fzf
zinit light MichaelAquilina/zsh-you-should-use # Alias reminders
zinit light ntnyq/omz-plugin-pnpm

# --- Oh My Zsh Snippets (for aliases and functions) ---
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::archlinux
zinit snippet OMZP::aws
zinit snippet OMZP::kubectl
zinit snippet OMZP::kubectx
zinit snippet OMZP::command-not-found
zinit snippet OMZP::docker
zinit snippet OMZP::podman
zinit snippet OMZP::github
zinit snippet OMZP::mongo-atlas
zinit snippet OMZP::mongocli
zinit snippet OMZP::node
zinit snippet OMZP::postgres
zinit snippet OMZP::python
zinit snippet OMZP::tmux
zinit snippet OMZP::bun
# zinit snippet OMZP::pnpm

# ------------------------------------------------------------------------------
# SHELL OPTIONS (setopt)
# ------------------------------------------------------------------------------

# Change directory without typing 'cd'
# setopt AUTO_CD

# Don't beep on errors
setopt NO_BEEP

# Don't exit zsh if a command can't find a match
setopt NO_NOMATCH

# When a process is put in the background, don't print its status immediately
setopt NO_NOTIFY

# Use extended pattern matching features
setopt EXTENDED_GLOB

# ------------------------------------------------------------------------------
# HISTORY
# ------------------------------------------------------------------------------

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY       # Append to history file
setopt EXTENDED_HISTORY     # Add timestamps to history
setopt SHARE_HISTORY        # Share history between sessions
setopt HIST_IGNORE_ALL_DUPS # If a new command is a duplicate, remove the older one
setopt HIST_SAVE_NO_DUPS    # Don't save duplicate entries in the history file
setopt HIST_FIND_NO_DUPS    # Don't show duplicates when searching
setopt HIST_IGNORE_SPACE    # Don't save commands starting with a space

# ------------------------------------------------------------------------------
# COMPLETIONS
# ------------------------------------------------------------------------------

# Load and initialize the completion system
autoload -Uz compinit && compinit

# --- Completion Styling ---
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no

# --- fzf-tab preview settings with eza ---
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --icons --tree --color=always $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza --icons --tree --color=always $realpath'

# ------------------------------------------------------------------------------
# KEYBINDINGS
# ------------------------------------------------------------------------------

bindkey -e # Use emacs keybindings
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region
bindkey '^[[A' up-line-or-search   # Up arrow
bindkey '^[[B' down-line-or-search # Down arrow

# ------------------------------------------------------------------------------
# ALIASES
# ------------------------------------------------------------------------------

# --- General ---
alias c='clear'
alias ff="fastfetch"
alias omp="oh-my-posh"
alias ssn="sudo shutdown now"
alias sr="reboot"
alias sysfailed="systemctl list-units --failed"

# --- Navigation & Files (using eza) ---
alias ls='eza --icons --git'
alias ll='eza --icons --git -l'
alias la='eza --icons --git -la'
alias lt='eza --icons --git --tree'

# --- Arch Linux ---
#alias update='sudo pacman -Syyu'
alias list="sudo pacman -Qqe"      # All explicitly installed packages
alias listt="sudo pacman -Qqet"     # Explicitly installed, no dependencies
alias listaur="sudo pacman -Qqem"   # AUR packages
alias probe="sudo archlinux-probe"
alias add="sudo pacman -S"
alias addy="yay -S"
alias remove="sudo pacman -Rns"

# --- BTRFS ---
alias btrfsfs="sudo btrfs filesystem df /"
alias btrfsli="sudo btrfs su li / -t"

# --- Package Management ---
alias ni='npm i'
alias nid='npm i -D'
alias nig='npm i -g'
alias nr='npm run'
alias nrb='npm run build'
alias nrd='npm run dev'
alias nrs='npm run start'
alias nlg='npm list -g --depth=0'

alias ya='yarn add'
alias yad='yarn add -D'
alias yb='yarn build'
alias yd='yarn dev'
alias ys='yarn start'
alias yyb='yarn && yarn build'
alias yyd='yarn && yarn dev'
alias ylg='yarn global list'

alias pi='pnpm i'
alias pid='pnpm i -D'
alias prb='pnpm run build'
alias prd='pnpm run dev'
alias prs='pnpm run start'
alias plg='pnpm list -g --depth=0'
alias pc='pnpm create'

alias bd='bun run dev'


alias lzd='lazydocker'


# ------------------------------------------------------------------------------
# EXPORTS & PATH
# ------------------------------------------------------------------------------

update() {
  sudo -k
  # authenticate first in a quiet context so fingerprint works reliably
  sudo -v || return 1
  # now run pacman; use -Syu normally (drop the double -y unless you intentionally need it)
  sudo pacman -Syu "$@"
}


# --- Tmux ---
export TMUX_CONFIG="$HOME/.config/tmux/tmux.conf"
alias tmux="tmux -f $TMUX_CONFIG"
alias zed="/usr/bin/zeditor"
# ------------------------------------------------------------------------------
# FINAL INITIALIZATIONS
# ------------------------------------------------------------------------------

# --- Shell Integrations ---
eval "$(fzf --zsh)"
eval "$(zoxide init --cmd z zsh)"
eval "$(oh-my-posh init zsh --config ~/.config/oh-my-posh/themes/stelbent.minimal.omp.json)"

# --- Atuin Shell History ---
eval "$(atuin init zsh)"

# --- Startup Commands ---
fastfetch

# --- Auto-start Tmux only in Ghostty ---
if [[ "$TERM" == "xterm-ghostty" ]] && command -v tmux &> /dev/null && [ -z "$TMUX" ]; then
    SESSION_NAME="main"
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux new-window -t "$SESSION_NAME": -c "$(pwd)"
        exec tmux attach-session -t "$SESSION_NAME"
    else
        exec tmux new-session -s "$SESSION_NAME" -c "$(pwd)"
    fi
fi

eval "$(/usr/bin/mise activate zsh)"

. "$HOME/.local/share/../bin/env"
