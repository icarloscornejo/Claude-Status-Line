# Claude-Status-Line

One line, no wasted tokens: a `statusLine` command for [Claude Code](https://claude.com/claude-code) that reads the CLI's own stdin JSON and renders it back as a colored prompt segment. No polling loop inside Claude Code itself - the binary just shells out to this script on redraw.

On an API key:

<img width="780" height="54" alt="image" src="https://github.com/user-attachments/assets/ab6a334a-8c94-4145-961e-73dd3504ef8e" />

<img width="773" height="45" alt="image" src="https://github.com/user-attachments/assets/c737dad7-29df-41bd-b270-444b43a0e877" />



On a subscription (Pro/Max):

<img width="1037" height="51" alt="image" src="https://github.com/user-attachments/assets/ce231d08-941c-4f88-a0d2-d4575eeee6f0" />

<img width="1031" height="51" alt="image" src="https://github.com/user-attachments/assets/1069fd1b-5b92-404e-a574-5f8d84559c25" />



## Getting it running

Tell Claude Code:

> Clone https://github.com/icarloscornejo/Claude-Status-Line into `~/.claude/statusline/` and wire it up as my status line - follow INSTALL.md.

That's the whole install: it clones, picks `statusline.sh` or `statusline.ps1` for your OS, merges the `statusLine` key into `settings.json`, and tells you to restart. See [INSTALL.md](INSTALL.md) if you'd rather do it by hand.

To pick up a new version later: `git -C ~/.claude/statusline pull` - the settings path never changes between releases.

## The problem this solves

Most Claude Code status lines assume a Pro/Max subscription: they read `rate_limits` from stdin and show a 5-hour / 7-day quota bar. That's dead weight if you're billed by API usage - there's no quota to bar-chart, so those scripts just print `-`.

This one looks at the same stdin payload and picks a different story depending on what's actually there:

- **stdin has `rate_limits`** -> you're on a subscription. Show the 5h/7d bars plus extra-usage credits (pulled from the OAuth usage endpoint, not exposed via stdin).
- **stdin has no `rate_limits`** -> you're paying per token. Show what actually matters instead: burn rate and running total for the day.

Either way, session cost (`cost.total_cost_usd` from stdin) is a segment on its own - every account type gets it, and the old scripts never surfaced it at all.

## Segments

Always on: model name, `cwd@branch` with a live `+adds -dels` diff stat, context-window tokens used/total, and the current effort level.

Then, conditionally:

**On a subscription:**
- `5h` / `7d` - percentage used and local reset time
- `extra` - extra-usage credits spent vs. monthly limit, if enabled on the account

**On an API key:**
- `burn` - dollars per hour at the current rate, shown once a session has run past 2 minutes (too noisy before that)
- `day` - sum of every session's cost today, persisted across restarts

Cost segments shift from green through yellow/orange to red as they climb. The three breakpoints are yours to move:

```bash
export STATUSLINE_COST_LOW=2     # below this: green
export STATUSLINE_COST_MED=5     # below this: yellow, above: orange
export STATUSLINE_COST_HIGH=10   # at/above this: red
```

A second line shows up once a day when a newer release is tagged on GitHub; set `STATUSLINE_CHECK_UPDATES=false` to turn that check off completely.

## What it needs

| | macOS / Linux | Windows |
|---|---|---|
| Shell | `statusline.sh`, needs `jq` + `curl` | `statusline.ps1`, PowerShell 5.1+ |
| `git` | in `PATH` | in `PATH` |
| Subscription segments | OAuth login (Pro/Max) | same |
| API-key segments | any auth method | same |

## Where it writes

Nothing is sent anywhere except the two things this script already talks to on your behalf: the Anthropic OAuth usage endpoint (subscription accounts only, cached 60s) and GitHub's releases API (cached 24h). Locally:

- `/tmp/claude/` (`%TEMP%\claude\` on Windows) - release cache
- `~/.cache/claude-statusline/` (`%LOCALAPPDATA%\claude-statusline\` on Windows) - daily spend ledger, one file per day, auto-pruned after a week

Multiple Claude Code profiles pointing at the same script share these caches, so running several instances doesn't multiply the API calls.

## License

MIT - Carlos Cornejo
