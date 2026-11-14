# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# ============================================================
# 自定义提示符样式（改这个数字即可，重新 . ~/.bashrc 或新开终端生效）
#   1 = 用户@主机:目录$
#   2 = 用户:目录$
#   3 = 目录 $       （绿色；不显示用户名和主机名）
# ============================================================
PROMPT_STYLE=2

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth:erasedups

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

case "${PROMPT_COMMAND:-}" in
    *"history -a"*) ;;
    *) PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
esac

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

# 按 PROMPT_STYLE 决定提示符前面的“用户@主机”部分
case "${PROMPT_STYLE:-1}" in
    1) __prompt_name='\u@\h' ;;
    2) __prompt_name='\u' ;;
    3) __prompt_name='' ;;
    *) __prompt_name='\u@\h' ;;   # 写成别的值就按 1 处理
esac

if [ -n "$__prompt_name" ]; then
    __prompt_name_color='\[\033[01;32m\]'"$__prompt_name"'\[\033[00m\]:'
    __prompt_name_plain="${__prompt_name}:"
    __prompt_path_color='\[\033[01;34m\]'   # 目录蓝色
    __prompt_path_sep=''
    __prompt_title="${__prompt_name}: "     # 窗口标题里的“用户@主机: ”
else
    # 只显示目录：目录改绿色，并与 $ 之间空一格
    __prompt_name_color=''
    __prompt_name_plain=''
    __prompt_path_color='\[\033[01;32m\]'
    __prompt_path_sep=' '
    __prompt_title=''
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}'"$__prompt_name_color$__prompt_path_color"'\w\[\033[00m\]'"$__prompt_path_sep"'\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}'"$__prompt_name_plain"'\w'"$__prompt_path_sep"'\$ '
fi

# If this is an xterm set the title to user@host:dir（跟 PROMPT_STYLE 保持一致）
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}${__prompt_title}\w\a\]$PS1"
    ;;
*)
    ;;
esac

unset color_prompt force_color_prompt __prompt_name __prompt_name_color __prompt_name_plain __prompt_path_color __prompt_path_sep __prompt_title

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

export LANG=zh_CN.UTF-8
export LANGUAGE=zh_CN:zh

# Hermes Agent command
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

alias cl='clear'

# ---- 快捷命令 ----
hermes() ( printf '\033]0;Hermes\007'; command hermes "$@" )
ldmbot() ( printf "\033]0;ldmbot\007"; cd "$HOME/ldmbot" && exec "$HOME/ldmbot/.venv/bin/python" main.py "$@" )
ldmapi() ( printf "\033]0;LDMAPI\007"; cd "$HOME/ldm-api" && exec ./ldmapi "$@" )
newapi() ( printf "\033]0;NewAPI\007"; cd "$HOME/new-api" && exec ./newapi "$@" )
napcat() ( printf "\033]0;NapCat\007"; cd "$HOME/napcat" && exec bash start_napcat.sh "$@" )

ondl() {
  local proxy=${1:-ldm.ccb:7890}
  local ip=${proxy%:*}
  local port=${proxy##*:}

  export http_proxy="http://$ip:$port"
  export https_proxy="http://$ip:$port"
  export all_proxy="socks5://$ip:$port"
  echo "✅ 当前终端全局代理已启用: $ip:$port"
}

offdl() ( unset http_proxy https_proxy all_proxy; echo "❌ 当前终端全局代理已关闭" )

testdl() {
  local proxy=${1:-ldm.ccb:7890}
  local ip=${proxy%:*}
  local port=${proxy##*:}

  curl -I --proxy "http://$ip:$port" \
    -w "\n代理地址: $ip:$port\n状态码:   %{http_code}\n连接耗时: %{time_connect}s\n总耗时:   %{time_total}s\n" \
    https://www.google.com
}

# ---- 启动时对历史文件去重（保留每个命令最后一次出现的位置）----
__hist_dedup() {
    [ -n "$__HIST_DEDUP_RAN" ] && return 0
    export __HIST_DEDUP_RAN=1
    local hf="${HISTFILE:-$HOME/.bash_history}"
    [ -f "$hf" ] || return 0
    # 若历史文件带时间戳(#1234567890)，跳过以免破坏格式
    if grep -q '^#[0-9]\{9,\}$' "$hf" 2>/dev/null; then return 0; fi
    local tmp lfd=""
    tmp=$(mktemp "${hf}.XXXXXX") || return 0
    if command -v flock >/dev/null 2>&1; then
        exec {lfd}<"$hf"
        flock -w 2 "$lfd" || { exec {lfd}<&-; rm -f "$tmp"; return 0; }
    fi
    tac "$hf" | awk 'NF && !seen[$0]++' | tac > "$tmp"
    if cmp -s "$hf" "$tmp"; then
        rm -f "$tmp"
    else
        cat "$tmp" > "$hf"      # 原地覆盖，保留原文件权限/属主
        rm -f "$tmp"
    fi
    [ -n "$lfd" ] && exec {lfd}<&-
    history -c; history -r "$hf"
}
__hist_dedup
