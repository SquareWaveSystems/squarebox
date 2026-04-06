Regenerate the demo animation for the README.

## Prerequisites

Make sure VHS and its dependencies are installed:
- `vhs` — https://github.com/charmbracelet/vhs
- `ffmpeg`
- `ttyd`

If VHS is not installed, install it before proceeding. On macOS: `brew install vhs`. On Linux, download the latest .deb or binary from the VHS GitHub releases page.

## Steps

1. Make sure you are on the `demo` branch. If not, check it out first.

2. If the user mentioned changes to the setup flow, update `demo/install-demo.sh` to reflect those changes. The script simulates the first-run setup experience — it should match what `setup.sh` actually does. Key sections to keep in sync:
   - Git identity prompts
   - GitHub CLI auth
   - AI coding assistant selection (Claude Code, OpenCode, Both)
   - Text editor selection (micro, edit, fresh, helix, nvim)
   - SDK selection (Node.js, Python, Go, .NET)

3. If the user wants to change the recording settings (dimensions, theme, timing), update `demo/demo.tape`.

4. Run VHS to regenerate the animation:
   ```
   vhs demo/demo.tape
   ```
   This produces `demo/squarebox-setup.webp`.

5. Verify the output looks correct by checking the file size and extracting a few sample frames with ffmpeg if available.

6. Commit the updated files and push to the `demo` branch.

7. Remind the user that the README on `main` references this file via raw GitHub URL (`https://raw.githubusercontent.com/BrettKinny/SquareBox/demo/demo/squarebox-setup.webp`), so the update will be live as soon as the push lands.
