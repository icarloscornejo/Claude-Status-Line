# Claude-Status-Line

A custom status line for [Claude Code](https://claude.com/claude-code) that shows model info, token usage, and cost/usage tracking in a single compact line. It runs as an external shell command, so it doesn't slow down Claude Code or consume extra tokens.

Unlike status lines that only show Pro/Max rate limits, this one adapts to **API-key-based accounts** too, where there's no subscription quota to report — instead it tracks live session cost, burn rate, and daily spend.

## What it shows

| Segment | Description | Shown when |
|---------|-------------|------------|
| **Model** | Current model name (e.g., Sonnet 5) | always |
| **cwd@branch (+/-)** | Current folder name, git branch, uncommitted diff stat | always |
| **Tokens** | Used / total context window (%) | always |
| **Effort** | Reasoning effort level (low, med, high, xhigh, max) | always |
| **session** | Session cost so far (`$X.XX`) | when `cost` data is present |
| **5h / 7d** | Rate-limit usage % and reset time | Pro/Max subscription (OAuth) accounts |
| **extra** | Extra usage credits spent / monthly limit | Pro/Max accounts with extra usage enabled |
| **burn** | Burn rate (`$/h`) for the current session | API key accounts, after 2 minutes of session time |
| **day** | Total spend across all sessions today | API key accounts |
| **api NN%** | Share of wall-clock time spent in API calls | API key accounts |
| **vX.Y.Z** | Installed Claude Code CLI version | always |
| **Update available** | Second line when a newer release exists | checked every 24h |

Account type is auto-detected: if the stdin JSON includes `rate_limits`, the subscription block (5h/7d/extra) renders; otherwise the API-key block (burn/day/api%) renders.

Dollar and percentage segments are color-coded: green → yellow → orange → red as usage/spend climbs. Thresholds for the dollar segments are configurable:

```bash
export STATUSLINE_COST_LOW=2     # green -> yellow
export STATUSLINE_COST_MED=5     # yellow -> orange
export STATUSLINE_COST_HIGH=10   # orange -> red
```

## Installation

Ask Claude Code:

> Clone https://github.com/icarloscornejo/Claude-Status-Line to `~/.claude/statusline/` (or `%USERPROFILE%\.claude\statusline\` on Windows) and configure it as my status bar by following its INSTALL.md.

Claude will clone the repo, pick the right script for your OS, and update `settings.json`. Full step-by-step instructions live in [INSTALL.md](INSTALL.md).

Restart Claude Code after Claude saves the configuration.

### Updating

When the status line shows a new release is available, ask Claude:

> Find my installed status bar and update it.

Or update it yourself:

```bash
git -C ~/.claude/statusline pull
```

No `settings.json` changes are needed — the path stays valid across versions.

## Requirements

- `git` in `PATH`
- macOS / Linux: `jq` and `curl`
- Windows: PowerShell 5.1+ (default on Windows 10/11)
- Pro/Max subscription for the `5h` / `7d` / `extra` segments (needs OAuth login); any account gets `session` cost and, on API key auth, `burn` / `day` / `api%`

## Caching

- Extra-usage data from the Anthropic API: 60s at `/tmp/claude/status-line-extra-usage-<hash>.json` (`%TEMP%\claude\...` on Windows)
- Daily spend totals: `~/.cache/claude-statusline/daily-<date>.json` (`%LOCALAPPDATA%\claude-statusline\` on Windows), pruned after 7 days
- Release check: 24h, `/tmp/claude/status-line-version-cache.json`

All caches are shared across concurrent Claude Code instances/profiles to avoid redundant API calls.

## Disabling the update check

```bash
export STATUSLINE_CHECK_UPDATES=false
```

## License

MIT

## Author

Carlos Cornejo
