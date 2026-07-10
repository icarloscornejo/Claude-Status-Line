# Setting this up

Written so Claude Code can follow it step-by-step when a user asks to install or update this status line - but readable if you're doing it by hand too.

## The whole thing, if you're on macOS/Linux

```bash
git clone https://github.com/icarloscornejo/Claude-Status-Line ~/.claude/statusline
chmod +x ~/.claude/statusline/statusline.sh
```

Then merge this into `~/.claude/settings.json` (don't clobber other keys already in there):

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline/statusline.sh"
  }
}
```

Restart Claude Code. Done.

## The whole thing, if you're on Windows

```powershell
git clone https://github.com/icarloscornejo/Claude-Status-Line "$env:USERPROFILE\.claude\statusline"
```

Merge into `%USERPROFILE%\.claude\settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File ~/.claude/statusline/statusline.ps1"
  }
}
```

No `pwsh` (PowerShell 7+) installed? Use Windows PowerShell 5.1 instead - swap `pwsh` for `powershell` in the command above. Two things worth knowing about that line:

- `-ExecutionPolicy Bypass` only applies to this one process - it doesn't touch your machine's actual execution policy. Skip it and a locked-down `Restricted`/`AllSigned` policy will reject the script silently, with no status line and no error to explain why.
- `~` gets expanded by Claude Code itself. On an older build that predates `~` expansion, spell it out: `%USERPROFILE%\.claude\statusline\statusline.ps1` for CMD/PowerShell, or `$USERPROFILE\.claude\statusline\statusline.ps1` if you're launching from Git Bash or WSL.

Restart Claude Code. Done.

## If you run multiple Claude Code profiles

Each profile can have its own `CLAUDE_CONFIG_DIR` and therefore its own `settings.json` - but there's no need for separate clones of this repo. Point every profile's `statusLine.command` at the same `~/.claude/statusline/` checkout; the caches this script writes are already keyed so they can be shared safely.

## Picking up updates

```bash
git -C ~/.claude/statusline pull
```

The command path in `settings.json` doesn't change between releases, so that's the only step.

## Taking it back out

Delete the `statusLine` block from `settings.json`, then remove the checkout: `rm -rf ~/.claude/statusline` (or the Windows equivalent).

## If something's not rendering

- `jq` missing on macOS/Linux -> `brew install jq` or your distro's package manager
- Blank status line on Windows -> almost always the execution-policy issue above; add `-ExecutionPolicy Bypass` back
- Still nothing -> run the script directly with a sample payload to see the error: `echo '{}' | ~/.claude/statusline/statusline.sh`
