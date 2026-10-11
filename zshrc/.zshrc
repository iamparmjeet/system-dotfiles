# ~/.zshrc

# ------------------------------------------------------------------------------
# ENVIRONMENT & ZINIT SETUP
# ------------------------------------------------------------------------------

# Set the directory for zinit and its plugins
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"

# Download Zinit if it's not there yet
if [[ -s "$ZINIT_HOME/zinit.zsh" ]]; then
  source "$ZINIT_HOME/zinit.zsh"
else
  print "⚠️ Zinit not found at $ZINIT_HOME"
fi

# ------------------------------------------------------------------------------
# PLUGINS & SNIPPETS (Loaded with Zinit)
# ------------------------------------------------------------------------------

# --- Core Plugins ---
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-completions
zinit light Aloxaf/fzf-tab
zinit light wfxr/forgit # Interactive git commands with fzf
zinit light MichaelAquilina/zsh-you-should-use # Alias reminders

# Syntax highlighting — this must be LAST
zinit light zsh-users/zsh-syntax-highlighting

# ------------------------------------------------------------------------------
# COMPLETION SYSTEM
# ------------------------------------------------------------------------------

autoload -Uz compinit
# Use cached compdump to speed up startup
if [[ ! -f ~/.zcompdump || ~/.zcompdump -nt ~/.zshrc ]]; then
  compinit
else
  compinit -C
fi

# # Source git's official zsh wrapper, if available
# if [[ -f /usr/share/git/completion/git-completion.zsh ]]; then
#   source /usr/share/git/completion/git-completion.zsh
# fi

# Native completions instead of OMZP snippets
(( $+commands[kubectl] )) && source <(kubectl completion zsh)
(( $+commands[docker] )) && source <(docker completion zsh)
(( $+commands[podman] )) && source <(podman completion zsh)
(( $+commands[gh] )) && source <(gh completion -s zsh)

zi lucid load'![[ $MYPROMPT = 8 ]]' unload'![[ $MYPROMPT != 8 ]]' \
  atload'!_zsh_git_prompt_precmd_hook' nocd for \
    woefe/git-prompt.zsh

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no

# Fzf-tab previews (careful with --tree for big dirs)
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --icons --tree --color=always $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza --icons --tree --color=always $realpath'


# ------------------------------------------------------------------------------
# SHELL OPTIONS
# ------------------------------------------------------------------------------
setopt prompt_subst
setopt autocd
setopt auto_menu menu_complete
setopt globdots
setopt always_to_end
setopt NO_BEEP
setopt NO_NOMATCH
setopt NO_NOTIFY
setopt EXTENDED_GLOB
setopt APPEND_HISTORY
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt INTERACTIVE_COMMENTS
setopt COMPLETE_IN_WORD

# ------------------------------------------------------------------------------
# HISTORY (native, Atuin will override if enabled)
# ------------------------------------------------------------------------------

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000


# ------------------------------------------------------------------------------
# KEYBINDINGS
# ------------------------------------------------------------------------------

bindkey -e                               # emacs keybindings
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region
bindkey '^[[A' up-line-or-search
bindkey '^[[B' down-line-or-search


unalias ga gd


# ------------------------------------------------------------------------------
# ALIASES
# ------------------------------------------------------------------------------

alias c='clear'
alias ff='fastfetch'

# Files & navigation
alias ls='eza --icons --git'
alias ll='eza --icons --git -l'
alias la='eza --icons --git -la'
alias lt='eza --icons --git --tree'

# System
alias ssn='sudo shutdown now'
alias sr='reboot'
alias sysfailed='systemctl list-units --failed'

# Arch Linux shortcuts
alias list="pacman -Qqe"
alias listt="pacman -Qqet"
alias listaur="pacman -Qqem"
alias probe="archlinux-probe"
alias a="sudo pacman -S"
alias ay="yay -S"
alias ap="paru -S"
alias r="sudo pacman -Rns"
alias u="sudo pacman -Syu"
alias uy="yay -Syu"
alias up="paru -Syu"

# BTRFS
alias btrfsfs="sudo btrfs filesystem df /"
alias btrfsli="sudo btrfs su li / -t"

# Node package managers
alias ni='npm i'
alias nid='npm i -D'
alias nig='npm i -g'
alias nr='npm run'
alias nrb='npm run build'
alias nrd='npm run dev'
alias nrs='npm run start'
alias bd='bun run dev'

alias lzd='lazydocker'

# Directories
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Tools
alias oc='opencode'
alias cx='printf "\033[2J\033[3J\033[H" && claude --allow-dangerously-skip-permissions'
alias d='docker'
alias t='tmux attach || tmux new -s Work'
n() { if [ "$#" -eq 0 ]; then command nvim . ; else command nvim "$@"; fi; }

# functions
for f in $OMARCHY_PATH/default/bash/fns/*; do source "$f"; done

# --- Oh My Zsh Snippets (for aliases and functions) ---
# Nvim OPTIONS

alias nvim-lazy="NVIM_APPNAME=LazyVim nvim"
alias nvim-kick="NVIM_APPNAME=kickstart nvim"
alias nvim-chad="NVIM_APPNAME=NvChad"
alias nvim-astro="NVIM_APPNAME=AstroNvim nvim"

function nvims() {
  items=("default" "kickstart" "LazyVim" "NvChad" "AstroNvim")
  config=$(printf "%s\n" "${items[@]}" | fzf --prompt=" Neovim Config  " --height=~50% --layout=reverse --border --exit-0)
  if [[ -z $config ]]; then
    echo "Nothing selected"
    return 0
  elif [[ $config == "default" ]]; then
    config=""
  fi
  NVIM_APPNAME=$config nvim $@
}

bindkey -s '^A' "nvims\n"

# zinit snippet OMZP::git
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::archlinux
zinit snippet OMZP::aws
zinit snippet OMZP::command-not-found
zinit snippet OMZP::mongo-atlas
zinit snippet OMZP::mongocli
zinit snippet OMZP::node
zinit snippet OMZP::postgres
zinit snippet OMZP::python
zinit snippet OMZP::tmux
zinit snippet OMZP::bun



# ------------------------------------------------------------------------------
# EXPORTS & PATH
# ------------------------------------------------------------------------------

# --- Tmux ---
export TMUX_CONFIG="$HOME/.config/tmux/tmux.conf"
alias tmux="tmux -f $TMUX_CONFIG"
alias zed="/usr/bin/zeditor"
# ------------------------------------------------------------------------------
# FINAL INITIALIZATIONS
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# SHELL INTEGRATIONS
# ------------------------------------------------------------------------------
#
(( $+commands[fzf] )) && eval "$(fzf --zsh)"
(( $+commands[zoxide] )) && eval "$(zoxide init --cmd z zsh)"
(( $+commands[oh-my-posh] )) && eval "$(oh-my-posh init zsh --config ~/.config/oh-my-posh/themes/stelbent.minimal.omp.json)"
(( $+commands[atuin] )) && eval "$(atuin init zsh)"
(( $+commands[mise] )) && eval "$(/usr/bin/mise activate zsh)"

# ------------------------------------------------------------------------------
# STARTUP COMMANDS
# ------------------------------------------------------------------------------
fastfetch
# ------------------------------------------------------------------------------
# TMUX AUTO-START (Optional: better in ~/.zlogin)
# ------------------------------------------------------------------------------

if [[ "$TERM" == "xterm-ghostty" ]] && command -v tmux &> /dev/null && [ -z "$TMUX" ]; then
  SESSION_NAME="main"
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux new-window -t "$SESSION_NAME": -c "$(pwd)"
    exec tmux attach-session -t "$SESSION_NAME"
  else
    exec tmux new-session -s "$SESSION_NAME" -c "$(pwd)"
  fi
fi

# ------------------------------------------------------------------------------
# PROFILING (uncomment to debug slow startup)
# ------------------------------------------------------------------------------
# zmodload zsh/zprof
# At end it will auto-run: zprof

# Force makepkg to use Arch system Python
export PYTHON=/usr/bin/python

#AI

alias lc="llama-cli"
alias ol="ollama"
# Added by LM Studio CLI (lms)
export PATH="$PATH:/home/parm/.lmstudio/bin"
# End of LM Studio CLI section

### End of Zinit's installer chunk
### End of Zinit's installer chunk
alias docker-start="sudo systemctl start docker containerd"
alias docker-stop="sudo systemctl stop docker containerd"



# Pi
export PATH="/home/parm/.local/share/mise/installs/node/26.8.1/bin:$PATH"

# Deepseek harnes
export PATH="/home/parm/.cache/.bun/bin:$PATH"

. "$HOME/.local/share/../bin/env"

# bun completions
[ -s "/tmp/bun-1.3.13/_bun" ] && source "/tmp/bun-1.3.13/_bun"

# Added by codebase-memory-mcp install
export PATH="/home/parm/.local/bin:$PATH"

