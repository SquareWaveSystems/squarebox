#!/bin/bash
# SquareBox MOTD — rainbow ASCII banner

figlet -f slant "SquareBox" | lolcat -f
echo ""
echo "  $(date '+%A, %B %d %Y  %H:%M')"
echo ""
