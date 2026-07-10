# Claude-Status-Line — single-line status bar for Claude Code (Windows / PowerShell 5.1+)
# Shows: model | cwd@branch (+/-) | tokens (%) | effort | session cost | usage block | version
#
# Usage block adapts to account type:
#   - Subscription (Pro/Max, OAuth): 5h / 7d rate-limit percentages + reset times, extra usage
#   - API key: burn rate ($/h), today's total spend, % of wall time spent in API calls
#
# Env vars:
#   STATUSLINE_CHECK_UPDATES=false   disable the GitHub release check (no network calls)
#   STATUSLINE_COST_LOW=2            $ threshold for green->yellow on cost segments
#   STATUSLINE_COST_MED=5            $ threshold for yellow->orange
#   STATUSLINE_COST_HIGH=10          $ threshold for orange->red

$ErrorActionPreference = "SilentlyContinue"
$Version = "1.0.0"

$rawInput = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-Output "Claude"
    exit 0
}

$data = $null
try { $data = $rawInput | ConvertFrom-Json } catch { Write-Output "Claude"; exit 0 }

# ===== Colors (truecolor ANSI, same palette as statusline.sh) =====
$Blue   = "$([char]27)[38;2;0;153;255m"
$Orange = "$([char]27)[38;2;255;176;85m"
$Green  = "$([char]27)[38;2;0;160;0m"
$Cyan   = "$([char]27)[38;2;46;149;153m"
$Red    = "$([char]27)[38;2;255;85;85m"
$Yellow = "$([char]27)[38;2;230;200;0m"
$Purple = "$([char]27)[38;2;167;139;250m"
$White  = "$([char]27)[38;2;220;220;220m"
$Dim    = "$([char]27)[2m"
$Reset  = "$([char]27)[0m"
$Sep    = " ${Dim}|${Reset} "

function Format-Tokens($n) {
    if ($n -ge 1000000) {
        $v = [math]::Round($n / 1000000.0, 1)
        if ($v -eq [math]::Floor($v)) { return "{0}m" -f [int]$v }
        return "{0:0.0}m" -f $v
    } elseif ($n -ge 1000) {
        return "{0}k" -f [int]([math]::Floor($n / 1000.0))
    }
    return "$n"
}

function Get-PctColor($pct) {
    if ($pct -ge 90) { return $Red }
    elseif ($pct -ge 70) { return $Orange }
    elseif ($pct -ge 50) { return $Yellow }
    else { return $Green }
}

function Get-CostColor($amount) {
    $low  = if ($env:STATUSLINE_COST_LOW)  { [double]$env:STATUSLINE_COST_LOW }  else { 2 }
    $med  = if ($env:STATUSLINE_COST_MED)  { [double]$env:STATUSLINE_COST_MED }  else { 5 }
    $high = if ($env:STATUSLINE_COST_HIGH) { [double]$env:STATUSLINE_COST_HIGH } else { 10 }
    if ($amount -ge $high) { return $Red }
    elseif ($amount -ge $med) { return $Orange }
    elseif ($amount -ge $low) { return $Yellow }
    else { return $Green }
}

function Test-VersionGt($a, $b) {
    try {
        $va = [version]($a.TrimStart("v"))
        $vb = [version]($b.TrimStart("v"))
        return $va -gt $vb
    } catch { return $false }
}

function Coalesce($val, $default) {
    if ($null -ne $val) { return $val }
    return $default
}

function Format-Epoch($epoch, $style) {
    if (-not $epoch) { return "" }
    $dt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$epoch).ToLocalTime()
    if ($style -eq "time") { return $dt.ToString("HH:mm") }
    return $dt.ToString("ddd MMM d, HH:mm")
}

$claudeConfigDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }

# ===== Core fields =====
$modelName = if ($data.model.display_name) { $data.model.display_name } else { "Claude" }
$cwd = $data.cwd
$sessionId = $data.session_id

$size = if ($data.context_window.context_window_size) { [int64]$data.context_window.context_window_size } else { 200000 }
if ($size -eq 0) { $size = 200000 }
$inputTokens  = [int64](Coalesce $data.context_window.current_usage.input_tokens 0)
$cacheCreate  = [int64](Coalesce $data.context_window.current_usage.cache_creation_input_tokens 0)
$cacheRead    = [int64](Coalesce $data.context_window.current_usage.cache_read_input_tokens 0)
$used = $inputTokens + $cacheCreate + $cacheRead
$pctUsed = if ($size -gt 0) { [int]($used * 100 / $size) } else { 0 }

$settingsPath = Join-Path $claudeConfigDir "settings.json"
$effortLevel = $data.effort.level
if (-not $effortLevel -and $env:CLAUDE_CODE_EFFORT_LEVEL) { $effortLevel = $env:CLAUDE_CODE_EFFORT_LEVEL }
if (-not $effortLevel -and (Test-Path $settingsPath)) {
    try { $effortLevel = (Get-Content $settingsPath -Raw | ConvertFrom-Json).effortLevel } catch {}
}
if (-not $effortLevel) { $effortLevel = "medium" }

$totalCostUsd = [double](Coalesce $data.cost.total_cost_usd 0)
$totalDurationMs = [int64](Coalesce $data.cost.total_duration_ms 0)
$totalApiDurationMs = [int64](Coalesce $data.cost.total_api_duration_ms 0)

# ===== Build line =====
$out = "${Blue}${modelName}${Reset}"

if ($cwd) {
    $displayDir = Split-Path $cwd -Leaf
    $gitBranch = $null
    try { $gitBranch = (git -C $cwd rev-parse --abbrev-ref HEAD 2>$null) } catch {}
    $out += "${Sep}${Cyan}${displayDir}${Reset}"
    if ($gitBranch) {
        $out += "${Dim}@${Reset}${Green}${gitBranch}${Reset}"
        try {
            $numstat = git -C $cwd diff --numstat 2>$null
            $add = 0; $del = 0
            foreach ($line in $numstat) {
                $parts = $line -split "`t"
                if ($parts.Length -ge 2 -and $parts[0] -match '^\d+$') { $add += [int]$parts[0]; $del += [int]$parts[1] }
            }
            if (($add + $del) -gt 0) {
                $out += " ${Dim}(${Reset}${Green}+${add}${Reset} ${Red}-${del}${Reset}${Dim})${Reset}"
            }
        } catch {}
    }
}

$out += "${Sep}${Orange}$(Format-Tokens $used)/$(Format-Tokens $size)${Reset} ${Dim}(${Reset}${Green}${pctUsed}%${Reset}${Dim})${Reset}"

$out += "${Sep}effort: "
switch ($effortLevel) {
    "low"    { $out += "${Dim}${effortLevel}${Reset}" }
    "medium" { $out += "${Orange}med${Reset}" }
    "high"   { $out += "${Green}${effortLevel}${Reset}" }
    "xhigh"  { $out += "${Purple}${effortLevel}${Reset}" }
    "max"    { $out += "${Red}${effortLevel}${Reset}" }
    default  { $out += "${Green}${effortLevel}${Reset}" }
}

if ($totalCostUsd -gt 0) {
    $sessionCostFmt = "{0:0.00}" -f $totalCostUsd
    $scColor = Get-CostColor $totalCostUsd
    $out += "${Sep}${White}session${Reset} ${scColor}`$${sessionCostFmt}${Reset}"
}

# ===== Usage block: subscription vs API =====
$fiveHourPct = $data.rate_limits.five_hour.used_percentage
$sevenDayPct = $data.rate_limits.seven_day.used_percentage

$tempDir = Join-Path $env:TEMP "claude"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

if ($fiveHourPct -or $sevenDayPct) {
    # ---- Subscription mode ----
    if ($fiveHourPct) {
        $fh = [int][math]::Round($fiveHourPct)
        $out += "${Sep}${White}5h${Reset} $(Get-PctColor $fh)${fh}%${Reset}"
        $fhTime = Format-Epoch $data.rate_limits.five_hour.resets_at "time"
        if ($fhTime) { $out += " ${Dim}@${fhTime}${Reset}" }
    }
    if ($sevenDayPct) {
        $sd = [int][math]::Round($sevenDayPct)
        $out += "${Sep}${White}7d${Reset} $(Get-PctColor $sd)${sd}%${Reset}"
        $sdTime = Format-Epoch $data.rate_limits.seven_day.resets_at "datetime"
        if ($sdTime) { $out += " ${Dim}@${sdTime}${Reset}" }
    }

    function Get-OAuthToken {
        if ($env:CLAUDE_CODE_OAUTH_TOKEN) { return $env:CLAUDE_CODE_OAUTH_TOKEN }
        $credsFile = Join-Path $claudeConfigDir ".credentials.json"
        if (Test-Path $credsFile) {
            try {
                $creds = Get-Content $credsFile -Raw | ConvertFrom-Json
                if ($creds.claudeAiOauth.accessToken) { return $creds.claudeAiOauth.accessToken }
            } catch {}
        }
        return $null
    }

    $dirHash = [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($claudeConfigDir))
    ).Replace("-", "").ToLower().Substring(0, 8)
    $extraCache = Join-Path $tempDir "status-line-extra-usage-$dirHash.json"
    $extraData = $null
    $refresh = $true
    if (Test-Path $extraCache) {
        $age = (Get-Date) - (Get-Item $extraCache).LastWriteTime
        if ($age.TotalSeconds -lt 60) { $refresh = $false }
        try { $extraData = Get-Content $extraCache -Raw | ConvertFrom-Json } catch {}
    }
    if ($refresh) {
        New-Item -ItemType File -Force -Path $extraCache | Out-Null
        $token = Get-OAuthToken
        if ($token) {
            try {
                $resp = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" -TimeoutSec 10 -Headers @{
                    "Accept" = "application/json"
                    "Content-Type" = "application/json"
                    "Authorization" = "Bearer $token"
                    "anthropic-beta" = "oauth-2025-04-20"
                }
                if ($resp.extra_usage) {
                    $extraData = $resp
                    $resp | ConvertTo-Json -Depth 10 | Set-Content $extraCache
                }
            } catch {}
        }
        if ((Test-Path $extraCache) -and (Get-Item $extraCache).Length -eq 0) { Remove-Item $extraCache -Force }
    }
    if ($extraData -and $extraData.extra_usage.is_enabled) {
        $euPct = [int][math]::Round([double](Coalesce $extraData.extra_usage.utilization 0))
        $euUsed = "{0:0.00}" -f ([double](Coalesce $extraData.extra_usage.used_credits 0) / 100)
        $euLimit = "{0:0.00}" -f ([double](Coalesce $extraData.extra_usage.monthly_limit 0) / 100)
        $out += "${Sep}${White}extra${Reset} $(Get-PctColor $euPct)`$${euUsed}/`$${euLimit}${Reset}"
    }
} else {
    # ---- API key mode ----
    if ($totalDurationMs -gt 120000) {
        $burn = "{0:0.00}" -f ($totalCostUsd * 3600000 / $totalDurationMs)
        $out += "${Sep}${White}burn${Reset} $(Get-CostColor ([double]$burn))`$${burn}/h${Reset}"
    }

    if ($sessionId) {
        $cacheDir = Join-Path $env:LOCALAPPDATA "claude-statusline"
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
        Get-ChildItem -Path $cacheDir -Filter "daily-*.json" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        $dayFile = Join-Path $cacheDir "daily-$(Get-Date -Format 'yyyy-MM-dd').json"
        $dayData = [ordered]@{}
        if (Test-Path $dayFile) {
            try {
                $existing = Get-Content $dayFile -Raw | ConvertFrom-Json
                if ($existing) {
                    foreach ($prop in $existing.PSObject.Properties) { $dayData[$prop.Name] = $prop.Value }
                }
            } catch {}
        }
        $dayData[$sessionId] = $totalCostUsd
        $dayData | ConvertTo-Json | Set-Content $dayFile

        $dayTotal = ($dayData.Values | Measure-Object -Sum).Sum
        $dayTotalFmt = "{0:0.00}" -f $dayTotal
        $out += "${Sep}${White}day${Reset} $(Get-CostColor $dayTotal)`$${dayTotalFmt}${Reset}"
    }

    if ($totalDurationMs -gt 0) {
        $apiPct = [int]($totalApiDurationMs * 100 / $totalDurationMs)
        $out += "${Sep}${Dim}api ${apiPct}%${Reset}"
    }
}

# ===== CLI version (cached 1h) =====
$cliVersionCache = Join-Path $tempDir "status-line-cli-version"
$cliVersion = $null
if (Test-Path $cliVersionCache) {
    $age = (Get-Date) - (Get-Item $cliVersionCache).LastWriteTime
    if ($age.TotalSeconds -lt 3600) { $cliVersion = Get-Content $cliVersionCache -Raw }
}
if (-not $cliVersion) {
    try {
        $verOut = & claude --version 2>$null
        if ($verOut) {
            $cliVersion = ($verOut -split '\s+')[0]
            Set-Content -Path $cliVersionCache -Value $cliVersion
        }
    } catch {}
}
if ($cliVersion) { $out += "${Sep}${Orange}v${cliVersion}${Reset}" }

# ===== Update check (cached 24h) =====
$updateLine = ""
if ($env:STATUSLINE_CHECK_UPDATES -ne "false") {
    $versionCache = Join-Path $tempDir "status-line-version-cache.json"
    $versionData = $null
    $refreshVersion = $true
    if (Test-Path $versionCache) {
        $age = (Get-Date) - (Get-Item $versionCache).LastWriteTime
        if ($age.TotalSeconds -lt 86400) { $refreshVersion = $false }
        try { $versionData = Get-Content $versionCache -Raw | ConvertFrom-Json } catch {}
    }
    if ($refreshVersion) {
        New-Item -ItemType File -Force -Path $versionCache | Out-Null
        try {
            $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/icarloscornejo/Claude-Status-Line/releases/latest" `
                -TimeoutSec 5 -Headers @{ "Accept" = "application/vnd.github+json" }
            if ($resp.tag_name) {
                $versionData = $resp
                $resp | ConvertTo-Json -Depth 10 | Set-Content $versionCache
            }
        } catch {}
        if ((Test-Path $versionCache) -and (Get-Item $versionCache).Length -eq 0) { Remove-Item $versionCache -Force }
    }
    if ($versionData -and $versionData.tag_name -and (Test-VersionGt $versionData.tag_name $Version)) {
        $updateLine = "`n${Dim}Update available: $($versionData.tag_name) -> Tell Claude: `"Find my installed status bar and update it`"${Reset}"
    }
}

Write-Output "$out$updateLine"
exit 0
