# Installation

This document is the authoritative install guide. It is written to be executed step-by-step by Claude Code when a user asks to install or update this status line.

## 1. Detect the operating system

- **macOS or Linux** → use `statusline.sh`
- **Windows** (PowerShell, CMD, Git Bash, or WSL) → use `statusline.ps1`

## 2. Clone the repo

Clone to `~/.claude/statusline/` on Unix, or `%USERPROFILE%\.claude\statusline\` on Windows. If that directory already exists and is a git clone of this repo, run `git pull` in it instead of re-cloning. If the user has multiple Claude Code profiles (custom `CLAUDE_CONFIG_DIR` per profile), a single shared clone is fine — point every profile's `settings.json` at the same path.

**macOS / Linux**

```bash
git clone https://github.com/icarloscornejo/Claude-Status-Line ~/.claude/statusline
chmod +x ~/.claude/statusline/statusline.sh
```

**Windows (PowerShell)**

```powershell
git clone https://github.com/icarloscornejo/Claude-Status-Line "$env:USERPROFILE\.claude\statusline"
```

## 3. Configure `settings.json`

Add (or update) the `statusLine` key in `~/.claude/settings.json` (Unix) or `%USERPROFILE%\.claude\settings.json` (Windows). If the file already contains other keys, merge — do not overwrite. If a custom `CLAUDE_CONFIG_DIR` is in use, edit that directory's `settings.json` instead.

**macOS / Linux**

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline/statusline.sh"
  }
}
```

**Windows**

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File ~/.claude/statusline/statusline.ps1"
  }
}
```

If PowerShell 7+ (`pwsh`) is not installed, fall back to Windows PowerShell 5.1:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/statusline/statusline.ps1"
  }
}
```

> `-ExecutionPolicy Bypass` is **process-scoped** — it does not change the machine's PowerShell policy. Without it, a default `Restricted` or `AllSigned` policy silently rejects the unsigned script and Claude Code shows no status line with no error.
>
> `~` is expanded by Claude Code on both Unix and Windows. On older Claude Code versions, replace `~/.claude/statusline/statusline.ps1` with `%USERPROFILE%\.claude\statusline\statusline.ps1` (CMD / PowerShell) or `$USERPROFILE\.claude\statusline\statusline.ps1` (Git Bash / WSL) — `%VAR%` expands only in CMD/PowerShell, `$VAR` only in bash shells.

## 4. Restart Claude Code

The status line is loaded at startup. After saving `settings.json`, restart Claude Code (or start a new session) for the change to take effect.

## Updating

Pull the latest release:

```bash
git -C ~/.claude/statusline pull
```

No `settings.json` changes are needed — the command path is stable across versions.

## Uninstalling

1. Remove the `statusLine` block from `settings.json`.
2. Delete the clone: `rm -rf ~/.claude/statusline` (or the Windows equivalent).

## Requirements

- `git` in `PATH`
- macOS / Linux: `jq` and `curl`
- Windows: PowerShell 5.1+ (default on Windows 10/11)

If `jq` is missing on macOS/Linux, install it with the system package manager (`brew install jq`, `apt install jq`, etc.).
