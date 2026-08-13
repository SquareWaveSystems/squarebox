Regenerate the demo animation for the README.

## Prerequisites

Make sure VHS and its dependencies are installed:
- `vhs` — https://github.com/charmbracelet/vhs
- `ffmpeg`
- `ttyd`

If VHS is not installed, install it before proceeding. On macOS: `brew install vhs`. On Linux, download the latest .deb or binary from the VHS GitHub releases page.

## Steps

1. Work from the current review branch and keep the generated asset with the
   source changes that produced it.

2. If the setup flow changed, update `demo/setup-demo.sh`. It simulates the
   first-run experience and should match `setup.sh`. Keep these sections in sync:
   - Git identity prompts
   - GitHub CLI auth
   - AI coding assistant selection
   - Text editor (including Helix), default-editor, and TUI selection
   - Multiplexer and shell selection
   - SDK selection (Node.js, Python, Go, .NET, Rust)

3. If the user wants to change the recording settings (dimensions, theme, timing), update `demo/demo.tape`.

4. Run VHS to regenerate the animation:
   ```
   vhs demo/demo.tape
   ```
   This produces `demo/squarebox-setup.gif`.

5. Verify the output looks correct by checking the file size and extracting a few sample frames with ffmpeg if available.

6. Confirm README references the tracked `demo/squarebox-setup.gif` asset and
   include the regenerated GIF in the same review as the flow changes.
