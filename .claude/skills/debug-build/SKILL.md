---
name: debug-build
description: Debug the Docker build by running it in a loop with subagents until it passes. Use when the Docker image fails to build and you need to iteratively fix errors.
argument-hint: "[max-attempts (default: 10)]"
allowed-tools: Bash Agent Read Edit Grep Glob
---

# Debug Docker Build

You are an orchestrator that will iteratively fix the Dockerfile until `docker build` succeeds.

## Process

Set `max_attempts` to `$ARGUMENTS` if provided, otherwise default to 10.

Loop up to `max_attempts` times:

1. **Run the build** using Bash:
   ```
   docker build -t squarebox . 2>&1
   ```
   If the build succeeds (exit code 0), announce success and stop.

2. **On failure**, capture the full error output. Then spawn a subagent (Agent tool, subagent_type: "general-purpose") with a prompt that includes:
   - The complete build error output
   - The instruction: "Read the Dockerfile and any files referenced by the error. Diagnose the root cause and fix it by editing the necessary files. Do NOT run docker build yourself — just make the fix and report what you changed and why."

3. **After the subagent returns**, report what it changed, then loop back to step 1.

If you exhaust all attempts without a successful build, summarize the remaining errors and what was tried.

## Rules

- Always run `docker build` yourself in the main orchestrator — never delegate the build to a subagent.
- Each subagent gets the fresh error output from the most recent failed build.
- Do not retry the same fix twice. If a subagent's fix didn't resolve the error, include that context in the next subagent's prompt so it tries a different approach.
- Keep a running log of attempt number, error summary, and fix applied. Print a status line before each attempt like: `### Attempt N/max_attempts`
