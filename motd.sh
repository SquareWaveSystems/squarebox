#!/bin/bash
# squarebox MOTD — orange metallic banner with SDK info

# Orange metallic: bright orange heading, muted orange date
printf '\e[1;38;5;208m'
toilet -f smblock --metal "squarebox"
printf '\e[0m'

# Detect installed SDKs
sdks=()
command -v node  &>/dev/null && sdks+=("Node $(node -v 2>/dev/null | tr -d 'v')")
command -v python3 &>/dev/null && [[ -d "$HOME/.local/share/uv" || -f /workspace/.squarebox/sdks ]] && sdks+=("Python $(python3 --version 2>/dev/null | awk '{print $2}')")
command -v go    &>/dev/null && sdks+=("Go $(go version 2>/dev/null | awk '{print $3}' | tr -d 'go')")
command -v dotnet &>/dev/null && sdks+=("$(dotnet --version 2>/dev/null | sed 's/^/.NET /')")

printf '\e[38;5;172m  %s\e[0m\n' "$(date '+%A, %B %d %Y  %H:%M')"
if [ ${#sdks[@]} -gt 0 ]; then
	sdk_str=$(IFS=', '; echo "${sdks[*]}")
	printf '\e[38;5;172m  %s\e[0m\n' "$sdk_str"
fi
echo
