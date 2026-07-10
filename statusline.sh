#!/bin/bash
# Claude-Status-Line — single-line status bar for Claude Code (macOS/Linux)
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

set -f  # disable globbing
VERSION="1.0.0"

input=$(cat)
[ -z "$input" ] && { printf "Claude"; exit 0; }

# ===== Colors =====
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;160;0m'
cyan='\033[38;2;46;149;153m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
purple='\033[38;2;167;139;250m'
white='\033[38;2;220;220;220m'
dim='\033[2m'
reset='\033[0m'
sep=" ${dim}|${reset} "

# ===== Formatting helpers =====
format_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        awk -v n="$n" 'BEGIN{v=n/1000000; if (v==int(v)) printf "%dm", v; else printf "%.1fm", v}'
    elif [ "$n" -ge 1000 ]; then
        awk -v n="$n" 'BEGIN{printf "%.0fk", n/1000}'
    else
        printf "%d" "$n"
    fi
}

# Color by percentage: <50 green, <70 yellow, <90 orange, else red
pct_color() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then echo "$red"
    elif [ "$pct" -ge 70 ]; then echo "$orange"
    elif [ "$pct" -ge 50 ]; then echo "$yellow"
    else echo "$green"
    fi
}

# Color by dollar amount, thresholds configurable via STATUSLINE_COST_*
cost_color() {
    local amount=$1
    local low="${STATUSLINE_COST_LOW:-2}" med="${STATUSLINE_COST_MED:-5}" high="${STATUSLINE_COST_HIGH:-10}"
    awk -v a="$amount" -v low="$low" -v med="$med" -v high="$high" \
        'BEGIN{ if (a>=high) print "red"; else if (a>=med) print "orange"; else if (a>=low) print "yellow"; else print "green" }'
}
resolve_color() {
    case "$1" in
        red) echo "$red" ;; orange) echo "$orange" ;; yellow) echo "$yellow" ;; *) echo "$green" ;;
    esac
}

version_gt() {
    local a="${1#v}" b="${2#v}"
    local IFS='.'
    read -r a1 a2 a3 <<< "$a"
    read -r b1 b2 b3 <<< "$b"
    a1=${a1:-0}; a2=${a2:-0}; a3=${a3:-0}
    b1=${b1:-0}; b2=${b2:-0}; b3=${b3:-0}
    [ "$a1" -gt "$b1" ] 2>/dev/null && return 0
    [ "$a1" -lt "$b1" ] 2>/dev/null && return 1
    [ "$a2" -gt "$b2" ] 2>/dev/null && return 0
    [ "$a2" -lt "$b2" ] 2>/dev/null && return 1
    [ "$a3" -gt "$b3" ] 2>/dev/null && return 0
    return 1
}

# Epoch -> local HH:MM / weekday-date-time, cross-platform (GNU date first, BSD date fallback)
fmt_epoch() {
    local epoch="$1" style="$2"
    [ -z "$epoch" ] || [ "$epoch" = "null" ] && return
    case "$style" in
        time)     date -d "@$epoch" +"%H:%M" 2>/dev/null || date -j -r "$epoch" +"%H:%M" 2>/dev/null ;;
        datetime) date -d "@$epoch" +"%a %b %-d, %H:%M" 2>/dev/null || date -j -r "$epoch" +"%a %b %-d, %H:%M" 2>/dev/null ;;
    esac
}

claude_config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# ===== Core fields =====
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cwd=$(echo "$input" | jq -r '.cwd // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')

size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
used=$(( input_tokens + cache_create + cache_read ))
pct_used=$(( size > 0 ? used * 100 / size : 0 ))

settings_path="$claude_config_dir/settings.json"
effort_level=$(echo "$input" | jq -r '.effort.level // empty')
if [ -z "$effort_level" ] && [ -n "$CLAUDE_CODE_EFFORT_LEVEL" ]; then
    effort_level="$CLAUDE_CODE_EFFORT_LEVEL"
elif [ -z "$effort_level" ] && [ -f "$settings_path" ]; then
    effort_level=$(jq -r '.effortLevel // empty' "$settings_path" 2>/dev/null)
fi
[ -z "$effort_level" ] && effort_level="medium"

total_cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
total_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
total_api_duration_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')

# ===== Build line =====
out="${blue}${model_name}${reset}"

if [ -n "$cwd" ]; then
    display_dir="${cwd##*/}"
    git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
    out+="${sep}${cyan}${display_dir}${reset}"
    if [ -n "$git_branch" ]; then
        out+="${dim}@${reset}${green}${git_branch}${reset}"
        git_stat=$(git -C "$cwd" diff --numstat 2>/dev/null | awk '{a+=$1; d+=$2} END {if (a+d>0) printf "+%d -%d", a, d}')
        [ -n "$git_stat" ] && out+=" ${dim}(${reset}${green}${git_stat%% *}${reset} ${red}${git_stat##* }${reset}${dim})${reset}"
    fi
fi

out+="${sep}${orange}$(format_tokens "$used")/$(format_tokens "$size")${reset} ${dim}(${reset}${green}${pct_used}%${reset}${dim})${reset}"

out+="${sep}effort: "
case "$effort_level" in
    low)    out+="${dim}${effort_level}${reset}" ;;
    medium) out+="${orange}med${reset}" ;;
    high)   out+="${green}${effort_level}${reset}" ;;
    xhigh)  out+="${purple}${effort_level}${reset}" ;;
    max)    out+="${red}${effort_level}${reset}" ;;
    *)      out+="${green}${effort_level}${reset}" ;;
esac

# Session cost (always shown when cost data present — works for both account types)
if awk -v c="$total_cost_usd" 'BEGIN{exit !(c>0)}'; then
    session_cost_fmt=$(awk -v c="$total_cost_usd" 'BEGIN{printf "%.2f", c}')
    sc_color=$(resolve_color "$(cost_color "$total_cost_usd")")
    out+="${sep}${white}session${reset} ${sc_color}\$${session_cost_fmt}${reset}"
fi

# ===== Usage block: subscription vs API =====
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

if [ -n "$five_hour_pct" ] || [ -n "$seven_day_pct" ]; then
    # ---- Subscription mode ----
    if [ -n "$five_hour_pct" ]; then
        fh=$(printf "%.0f" "$five_hour_pct")
        fh_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
        out+="${sep}${white}5h${reset} $(pct_color "$fh")${fh}%${reset}"
        fh_time=$(fmt_epoch "$fh_reset" time)
        [ -n "$fh_time" ] && out+=" ${dim}@${fh_time}${reset}"
    fi
    if [ -n "$seven_day_pct" ]; then
        sd=$(printf "%.0f" "$seven_day_pct")
        sd_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
        out+="${sep}${white}7d${reset} $(pct_color "$sd")${sd}%${reset}"
        sd_time=$(fmt_epoch "$sd_reset" datetime)
        [ -n "$sd_time" ] && out+=" ${dim}@${sd_time}${reset}"
    fi

    # Extra usage credits — only exposed via the OAuth usage endpoint, cached 60s
    get_oauth_token() {
        [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && { echo "$CLAUDE_CODE_OAUTH_TOKEN"; return; }
        if command -v security >/dev/null 2>&1; then
            local svc="Claude Code-credentials"
            if [ -n "$CLAUDE_CONFIG_DIR" ]; then
                svc="Claude Code-credentials-$(echo -n "$CLAUDE_CONFIG_DIR" | shasum -a 256 | cut -c1-8)"
            fi
            local blob token
            blob=$(security find-generic-password -s "$svc" -w 2>/dev/null)
            if [ -n "$blob" ]; then
                token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
                [ -n "$token" ] && [ "$token" != "null" ] && { echo "$token"; return; }
            fi
        fi
        local creds_file="${claude_config_dir}/.credentials.json"
        if [ -f "$creds_file" ]; then
            local token
            token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
            [ -n "$token" ] && [ "$token" != "null" ] && { echo "$token"; return; }
        fi
        if command -v secret-tool >/dev/null 2>&1; then
            local blob token
            blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
            if [ -n "$blob" ]; then
                token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
                [ -n "$token" ] && [ "$token" != "null" ] && { echo "$token"; return; }
            fi
        fi
        echo ""
    }

    mkdir -p /tmp/claude
    dir_hash=$(echo -n "$claude_config_dir" | shasum -a 256 | cut -c1-8)
    extra_cache="/tmp/claude/status-line-extra-usage-${dir_hash}.json"
    extra_data=""
    refresh=true
    if [ -f "$extra_cache" ] && [ -s "$extra_cache" ]; then
        mtime=$(stat -f %m "$extra_cache" 2>/dev/null || stat -c %Y "$extra_cache" 2>/dev/null)
        age=$(( $(date +%s) - mtime ))
        [ "$age" -lt 60 ] && refresh=false
        extra_data=$(cat "$extra_cache")
    fi
    if $refresh; then
        touch "$extra_cache"
        token=$(get_oauth_token)
        if [ -n "$token" ]; then
            resp=$(curl -s --max-time 10 \
                -H "Accept: application/json" -H "Content-Type: application/json" \
                -H "Authorization: Bearer $token" -H "anthropic-beta: oauth-2025-04-20" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
            if [ -n "$resp" ] && echo "$resp" | jq -e '.extra_usage' >/dev/null 2>&1; then
                extra_data="$resp"
                echo "$resp" > "$extra_cache"
            fi
        fi
        [ -f "$extra_cache" ] && [ ! -s "$extra_cache" ] && rm -f "$extra_cache"
    fi
    if [ -n "$extra_data" ]; then
        enabled=$(echo "$extra_data" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null)
        if [ "$enabled" = "true" ]; then
            eu_pct=$(echo "$extra_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
            eu_used=$(echo "$extra_data" | jq -r '.extra_usage.used_credits // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
            eu_limit=$(echo "$extra_data" | jq -r '.extra_usage.monthly_limit // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
            out+="${sep}${white}extra${reset} $(pct_color "$eu_pct")\$${eu_used}/\$${eu_limit}${reset}"
        fi
    fi
else
    # ---- API key mode ----
    if [ "$total_duration_ms" -gt 120000 ] 2>/dev/null; then
        burn=$(awk -v c="$total_cost_usd" -v d="$total_duration_ms" 'BEGIN{printf "%.2f", c*3600000/d}')
        out+="${sep}${white}burn${reset} $(resolve_color "$(cost_color "$burn")")\$${burn}/h${reset}"
    fi

    if [ -n "$session_id" ]; then
        cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
        mkdir -p "$cache_dir"
        find "$cache_dir" -name 'daily-*.json' -mtime +7 -delete 2>/dev/null
        day_file="$cache_dir/daily-$(date +%Y-%m-%d).json"
        [ -f "$day_file" ] || echo '{}' > "$day_file"
        tmp_file=$(mktemp "${cache_dir}/.daily.XXXXXX")
        jq --arg sid "$session_id" --argjson cost "$total_cost_usd" '.[$sid] = $cost' "$day_file" > "$tmp_file" 2>/dev/null \
            && mv "$tmp_file" "$day_file" || rm -f "$tmp_file"
        day_total=$(jq '[.[]] | add // 0' "$day_file" 2>/dev/null)
        day_total_fmt=$(awk -v c="$day_total" 'BEGIN{printf "%.2f", c}')
        out+="${sep}${white}day${reset} $(resolve_color "$(cost_color "$day_total")")\$${day_total_fmt}${reset}"
    fi

    if [ "$total_duration_ms" -gt 0 ] 2>/dev/null; then
        api_pct=$(( total_api_duration_ms * 100 / total_duration_ms ))
        out+="${sep}${dim}api ${api_pct}%${reset}"
    fi
fi

# ===== CLI version (cached 1h) =====
cli_version_cache="/tmp/claude/status-line-cli-version"
cli_version=""
if [ -f "$cli_version_cache" ]; then
    mtime=$(stat -f %m "$cli_version_cache" 2>/dev/null || stat -c %Y "$cli_version_cache" 2>/dev/null)
    age=$(( $(date +%s) - mtime ))
    [ "$age" -lt 3600 ] && cli_version=$(cat "$cli_version_cache" 2>/dev/null)
fi
if [ -z "$cli_version" ]; then
    cli_version=$(claude --version 2>/dev/null | awk '{print $1}')
    if [ -n "$cli_version" ]; then
        mkdir -p /tmp/claude
        echo "$cli_version" > "$cli_version_cache"
    fi
fi
[ -n "$cli_version" ] && out+="${sep}${orange}v${cli_version}${reset}"

# ===== Update check (cached 24h) =====
update_line=""
if [ "${STATUSLINE_CHECK_UPDATES:-true}" != "false" ]; then
    version_cache="/tmp/claude/status-line-version-cache.json"
    version_data=""
    refresh_version=true
    if [ -f "$version_cache" ]; then
        mtime=$(stat -f %m "$version_cache" 2>/dev/null || stat -c %Y "$version_cache" 2>/dev/null)
        age=$(( $(date +%s) - mtime ))
        [ "$age" -lt 86400 ] && refresh_version=false
        version_data=$(cat "$version_cache" 2>/dev/null)
    fi
    if $refresh_version; then
        touch "$version_cache" 2>/dev/null
        resp=$(curl -s --max-time 5 -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/icarloscornejo/Claude-Status-Line/releases/latest" 2>/dev/null)
        if [ -n "$resp" ] && echo "$resp" | jq -e '.tag_name' >/dev/null 2>&1; then
            version_data="$resp"
            echo "$resp" > "$version_cache"
        elif [ ! -s "$version_cache" ]; then
            rm -f "$version_cache" 2>/dev/null
        fi
    fi
    if [ -n "$version_data" ]; then
        latest_tag=$(echo "$version_data" | jq -r '.tag_name // empty')
        if [ -n "$latest_tag" ] && version_gt "$latest_tag" "$VERSION"; then
            update_line="\n${dim}Update available: ${latest_tag} → Tell Claude: \"Find my installed status bar and update it\"${reset}"
        fi
    fi
fi

printf "%b" "$out$update_line"
exit 0
