# SquareBox first-run demo — https://github.com/charmbracelet/vhs
#
# Record:
#   vhs demo/demo.tape
#
# Requires: vhs, ttyd, ffmpeg, gum, toilet

Output demo/squarebox-setup.gif

Set Shell "bash"
Set FontSize 16
Set Width 900
Set Height 550
Set Padding 20
Set Theme "Catppuccin Frappe"
Set TypingSpeed 60ms
Set WindowBar ""
Set CursorBlink false
Set LoopOffset 0
Set LoopOffset 0%

Sleep 500ms

# Show the pasted curl command, then run the demo script
Hide
Type "bash demo/setup-demo.sh"
Enter
Show

# --- Install phase plays out automatically (~4s) ---
Sleep 7s

# --- AI assistant (gum choose, single select) ---
# Claude Code is first option — just press Enter
Sleep 300ms
Enter

# Wait for Claude Code "install" (spinner ~1s + 0.3s sleep + gum render)
Sleep 2s

# --- Editors (gum choose --no-limit) ---
# Select micro (1st) and fresh (3rd)
Sleep 500ms
Space
Sleep 400ms
Down
Sleep 300ms
Down
Sleep 400ms
Space
Sleep 500ms
Enter

# Wait for editor "installs"
Sleep 1.5s

# --- Terminal multiplexer (gum choose --no-limit) ---
# Select tmux (1st)
Sleep 500ms
Space
Sleep 500ms
Enter

# Wait for multiplexer "install"
Sleep 1.5s

# --- SDKs (gum choose --no-limit) ---
# Select Node.js and Python
Sleep 500ms
Space
Sleep 400ms
Down
Sleep 400ms
Space
Sleep 500ms
Enter

# Wait for SDK "installs" + Done + MOTD
Sleep 3s

# Linger on MOTD
Sleep 5s
