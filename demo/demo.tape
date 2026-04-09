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
Set Height 600
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

# --- Container creation + header + gh auth ---
Sleep 3s

# --- AI assistant (gum choose --no-limit) ---
# Select only Claude Code (1st item)
Sleep 500ms
Space
Sleep 500ms
Enter

# Wait for AI tool "installs" (1 spinner: Claude Code)
Sleep 2s

# --- Editors (gum choose --no-limit) ---
# Select micro (1st) and fresh (3rd)
Sleep 500ms
Space
Sleep 300ms
Down
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 500ms
Enter

# Wait for editor "installs" (2 spinners)
Sleep 3s

# --- Terminal multiplexer (gum choose --no-limit) ---
# Select tmux (1st item)
Sleep 500ms
Space
Sleep 500ms
Enter

# Wait for multiplexer "install" (1 spinner)
Sleep 2s

# --- SDKs (gum choose --no-limit) ---
# Select Node.js (1st) and Python (2nd)
Sleep 500ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 500ms
Enter

# Wait for SDK "installs" (2 spinners) + Done + MOTD
Sleep 4s

# Linger on MOTD
Sleep 5s
