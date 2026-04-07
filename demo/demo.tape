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
# Select all 5: Claude Code, GitHub Copilot CLI, Google Gemini CLI, OpenAI Codex CLI, OpenCode
Sleep 500ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 500ms
Enter

# Wait for AI tool "installs" (6 spinners: Claude + Node + Copilot + Gemini + Codex + OpenCode)
Sleep 8s

# --- Editors (gum choose --no-limit) ---
# Select all 5: micro, edit, fresh, helix, nvim
Sleep 500ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 500ms
Enter

# Wait for editor "installs" (5 spinners)
Sleep 5s

# --- Terminal multiplexer (gum choose --no-limit) ---
# Select all 2: tmux, zellij
Sleep 500ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 500ms
Enter

# Wait for multiplexer "installs" (2 spinners)
Sleep 3s

# --- SDKs (gum choose --no-limit) ---
# Select all 4: Node.js, Python, Go, .NET
Sleep 500ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 500ms
Enter

# Wait for SDK "installs" (Node skip + 3 spinners) + Done + MOTD
Sleep 5s

# Linger on MOTD
Sleep 5s
