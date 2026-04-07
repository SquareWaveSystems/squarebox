#!/bin/bash
# squarebox MOTD — orange metallic banner with SDK info

# Orange metallic: bright orange heading, muted orange date
printf '\e[1;38;5;208m'
toilet -f smblock --metal "squarebox"
printf '\e[0m'

# Detect installed SDKs from config
sdks=()
sdk_config="/workspace/.squarebox/sdks"
if [ -f "$sdk_config" ]; then
	for sdk in $(tr ',' ' ' < "$sdk_config"); do
		case "$sdk" in
			node)   ver=$(node -v 2>/dev/null | tr -d 'v') && [ -n "$ver" ] && sdks+=("Node $ver") ;;
			python) ver=$(python3 --version 2>/dev/null | awk '{print $2}'); [ -z "$ver" ] && ver=$(uv --version 2>/dev/null | awk '{print $2}') && ver="uv $ver"; [ -n "$ver" ] && sdks+=("Python $ver") ;;
			go)     ver=$(go version 2>/dev/null | awk '{print $3}' | tr -d 'go') && [ -n "$ver" ] && sdks+=("Go $ver") ;;
			dotnet) ver=$(DOTNET_NOLOGO=1 dotnet --version 2>/dev/null | tail -1) && [ -n "$ver" ] && sdks+=(".NET $ver") ;;
		esac
	done
fi

printf '\e[38;5;172m  %s\e[0m\n' "$(date '+%A, %B %d %Y  %H:%M')"
if [ ${#sdks[@]} -gt 0 ]; then
	sdk_str=""
	for i in "${!sdks[@]}"; do
		if [ $i -gt 0 ]; then
			if (( i % 2 == 0 )); then
				printf '\e[38;5;245m  %s\e[0m\n' "$sdk_str"
				sdk_str=""
			else
				sdk_str+=" ◆ "
			fi
		fi
		sdk_str+="${sdks[$i]}"
	done
	[ -n "$sdk_str" ] && printf '\e[38;5;245m  %s\e[0m\n' "$sdk_str"
fi
echo
