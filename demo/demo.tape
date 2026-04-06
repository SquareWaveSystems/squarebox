# SquareBox first-run demo — https://github.com/charmbracelet/vhs
#
# Generate:
#   vhs demo/demo.tape
#
# Requires: vhs, ttyd, ffmpeg

Output demo/squarebox-setup.gif

Set Shell "bash"
Set FontSize 18
Set Width 1200
Set Height 700
Set Padding 24
Set Theme "Catppuccin Frappe"
Set TypingSpeed 60ms
Set WindowBar ""
Set CursorBlink false
Set LoopOffset 0
Set LoopOffset 0%

Sleep 500ms

# Paste the install command (instant, not typed)
Hide
Type "curl -fsSL https://raw.githubusercontent.com/SquareWaveSystems/SquareBox/main/install.sh | bash"
Show
Sleep 1s

# Secretly swap to the demo script and press Enter
Hide
Ctrl+U
Type "bash demo/install-demo.sh"
Enter
Sleep 500ms
Show

# Wait for the full simulation to play out
Sleep 28s

Sleep 2s
