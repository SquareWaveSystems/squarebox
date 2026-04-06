#!/bin/bash
# SquareBox MOTD — rainbow ASCII banner

# Orange metallic: bright orange heading, muted orange date
printf '\e[1;38;5;208m'
toilet -f smslant --metal "SquareBox"
printf '\e[0m'
printf '\e[38;5;172m  %s\e[0m\n\n' "$(date '+%A, %B %d %Y  %H:%M')"
