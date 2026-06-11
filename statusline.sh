#!/bin/bash
input=$(cat)

# ── features (0/1) — defaults below, override via env or ~/.claude/statusline.conf
SHOW_TECH="${SHOW_TECH:-1}"          # language/version icon
SHOW_DIRTY="${SHOW_DIRTY:-1}"        # git dirty counts (staged/unstaged/untracked)
SHOW_ACTIVITY="${SHOW_ACTIVITY:-1}"  # waiting/running/thinking
SHOW_COST="${SHOW_COST:-1}"          # session cost
SHOW_BURN="${SHOW_BURN:-1}"          # $/min burn rate
SHOW_MCP="${SHOW_MCP:-1}"            # connected MCP servers
SHOW_LIMITS="${SHOW_LIMITS:-1}"      # 5h rate-limit gauge
SHOW_ONLY_TICKET="${SHOW_ONLY_TICKET:-1}" # show JIRA ticket ID instead of full branch name

[ -f "$HOME/.claude/statusline.conf" ] && source "$HOME/.claude/statusline.conf"

# ── colors ────────────────────────────────────────────────────────────────────
RESET=$'\033[0m'
BOLD=$'\033[1m'
BRIGHT_CYAN=$'\033[96m'
BRIGHT_YELLOW=$'\033[93m'
BRIGHT_MAGENTA=$'\033[95m'
BRIGHT_GREEN=$'\033[92m'
BRIGHT_RED=$'\033[91m'
ORANGE=$'\033[38;5;214m'
SALMON=$'\033[38;5;210m'
GRAY=$'\033[90m'

SEP="${RESET}  ${GRAY}│${RESET}  "
SPC="${RESET} ${GRAY}·${RESET} "
SP="${RESET} "

# ── input ─────────────────────────────────────────────────────────────────────
# \x1f delimiter: unlike tab, it's not IFS whitespace, so empty fields
# (e.g. no effort level) don't collapse and shift the ones after them
IFS=$'\x1f' read -r MODEL EFFORT CWD CTX_PCT COST_NUM SESSION_ID TRANSCRIPT LIMIT_PCT LIMIT_RESET < <(
  jq -r '[
    (.model.display_name // "unknown" | gsub(" *\\(.*\\)$"; "")),
    (.effort.level // ""),
    (.cwd // "."),
    ((.context_window.used_percentage // 0) | floor | tostring),
    (.cost.total_cost_usd // 0 | tostring),
    (.session_id // ""),
    (.transcript_path // ""),
    ((.rate_limits.five_hour.used_percentage // -1) | floor | tostring),
    ((.rate_limits.five_hour.resets_at // 0) | tostring)
  ] | join("\u001f")' <<< "$input"
)
printf -v COST "%.3f" "$COST_NUM"

# ── SEC_PATH ──────────────────────────────────────────────────────────────────

# folder
FOLDER=$(echo "${CWD/$HOME/~}" | sed -E 's|([^/])[^/]*/|\1/|g')

# branch & dirty state
BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git")
[ "$BRANCH" = "HEAD" ] && BRANCH=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null || echo "HEAD")
TICKET=""
[ "$SHOW_ONLY_TICKET" = 1 ] && [[ "$BRANCH" =~ ([A-Za-z]+-[0-9]+) ]] && TICKET=$(tr '[:lower:]' '[:upper:]' <<<"${BASH_REMATCH[1]}")
BRANCH_DISPLAY="${TICKET:-$BRANCH}"

DIRTY=""
if [ "$SHOW_DIRTY" = 1 ]; then
  STATUS=$(git -C "$CWD" status --porcelain 2>/dev/null)
  STAGED=$(grep -c '^[MADRCU]' <<< "$STATUS" || true)
  UNSTAGED=$(grep -c '^.[MD]' <<< "$STATUS" || true)
  UNTRACKED=$(grep -c '^??' <<< "$STATUS" || true)
  [ "$STAGED" -gt 0 ]    && DIRTY+="${BRIGHT_GREEN}●${STAGED}${RESET}"
  [ "$UNSTAGED" -gt 0 ]  && DIRTY+="${ORANGE}✚${UNSTAGED}${RESET}"
  [ "$UNTRACKED" -gt 0 ] && DIRTY+="${GRAY}?${UNTRACKED}${RESET}"
fi

BRANCH_PART="${BRIGHT_MAGENTA}⎇ ${BRANCH_DISPLAY}${RESET}"
[ -n "$DIRTY" ] && BRANCH_PART+=" ${DIRTY}"

# tech stack (reads config files, never runs runtimes)
_emit() { local icon="$1" v="$2"; [ -n "$v" ] && echo "$icon $v" || echo "$icon"; }

detect_tech() {
  local dir="$1"
  if [ -f "$dir/pom.xml" ]; then
    local v
    v=$(grep -m1 '<java.version>\|maven.compiler.source' "$dir/pom.xml" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    _emit "☕ " "$v"; return
  fi
  if [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then
    local v
    v=$(grep -shm1 'sourceCompatibility\|JavaVersion' "$dir/build.gradle" "$dir/build.gradle.kts" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    _emit "☕ " "$v"; return
  fi
  if [ -f "$dir/package.json" ]; then
    local v
    v=$(jq -r '.engines.node // .volta.node // ""' "$dir/package.json" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    _emit "⬡ " "$v"; return
  fi
  if [ -f "$dir/go.mod" ]; then
    local v
    v=$(awk '/^go /{print $2; exit}' "$dir/go.mod" 2>/dev/null)
    _emit "go" "$v"; return
  fi
  if [ -f "$dir/Cargo.toml" ]; then
    local v
    v=$(grep -m1 '^edition' "$dir/Cargo.toml" 2>/dev/null | grep -oE '[0-9]+')
    _emit "🦀 " "$v"; return
  fi
  if [ -f "$dir/pyproject.toml" ] || [ -f "$dir/requirements.txt" ] || [ -f "$dir/setup.py" ]; then
    local v
    { read -r v < "$dir/.python-version"; } 2>/dev/null; v="${v//[[:space:]]/}"
    [ -z "$v" ] && v=$(grep -m1 'python_requires\|python-requires' "$dir/pyproject.toml" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    _emit "🐍 " "$v"; return
  fi
  echo ""
}
TECH_DISPLAY=""
if [ "$SHOW_TECH" = 1 ]; then
  TECH=$(detect_tech "$CWD")
  [ -n "$TECH" ] && TECH_DISPLAY="${ORANGE}${TECH}"
fi

# ── SEC_MODEL ─────────────────────────────────────────────────────────────────

# model & effort
MODEL_DISPLAY="$MODEL"
[[ -n "$EFFORT" ]] && MODEL_DISPLAY="${MODEL}  ${EFFORT}"

case "$MODEL" in
  *Haiku*)  MODEL_COLOR="$BRIGHT_GREEN" ;;
  *Sonnet*) MODEL_COLOR="$BRIGHT_CYAN" ;;
  *Opus*)   MODEL_COLOR="$ORANGE" ;;
  *Fable*)  MODEL_COLOR="$SALMON" ;;
  *)        MODEL_COLOR="$BRIGHT_CYAN" ;;
esac

# context bar
(( CTX_PCT > 100 )) && CTX_PCT=100
(( CTX_PCT < 0 ))   && CTX_PCT=0
_filled=$(( CTX_PCT * 8 / 100 ))
_empty=$(( 8 - _filled ))
printf -v BAR '%*s' "$_filled" ''; BAR="${BAR// /█}"
printf -v _ebar '%*s' "$_empty" ''; BAR+="${_ebar// /░}"
if [ "$CTX_PCT" -ge 80 ]; then
  CTX_COLOR="$BRIGHT_RED";   CTX_LABEL="!!${CTX_PCT}%"
elif [ "$CTX_PCT" -ge 50 ]; then
  CTX_COLOR="$ORANGE";       CTX_LABEL="~${CTX_PCT}%"
else
  CTX_COLOR="$BRIGHT_GREEN"; CTX_LABEL="${CTX_PCT}%"
fi

# activity (SEC_MODEL) — last user/assistant entry in the transcript tail
ACTIVITY=""
[ "$SHOW_ACTIVITY" = 1 ] && ACTIVITY="${GRAY}waiting"
if [ "$SHOW_ACTIVITY" = 1 ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # last user/assistant line → "type:first_content_block_type"; tr strips raw
  # control bytes (except \t) that would make jq reject the string
  TRANSCRIPT_STATE=$(tail -c 65536 "$TRANSCRIPT" 2>/dev/null \
    | grep -a '"type":"user"\|"type":"assistant"' | tail -n 1 \
    | tr '\000-\010\013\014\016-\037' ' ' \
    | jq -r '(.type // "") + ":" + (.message.content | if type == "array" then (.[0].type // "") else "" end)' 2>/dev/null)
  case "${TRANSCRIPT_STATE}" in
    assistant:text)             ACTIVITY="${GRAY}waiting" ;;
    assistant:tool_use)         ACTIVITY="${ORANGE}⚙ running" ;;
    assistant:thinking)         ACTIVITY="${BRIGHT_CYAN}⟳ thinking" ;;
    user:tool_result|user:text) ACTIVITY="${BRIGHT_CYAN}⟳ thinking" ;;
  esac
fi

# burn rate (SEC_COST) — rolling ~5min window via state file: S_TIME S_COST LAST_BURN
if [ -n "$SESSION_ID" ]; then
  STATE_KEY="$SESSION_ID"
else
  _base=$(basename "$CWD")
  STATE_KEY="${_base//[^a-zA-Z0-9_-]/_}"
fi
STATE_FILE="${TMPDIR:-/tmp}/.claude_state_${STATE_KEY}"
BURN_DISPLAY=""
if [ "$SHOW_BURN" = 1 ]; then
  NOW=$(date +%s)
  S_TIME="" S_COST="" LAST_BURN=""

  [ -f "$STATE_FILE" ] && read -r S_TIME S_COST LAST_BURN < "$STATE_FILE" 2>/dev/null
  if ! [[ "$S_TIME" =~ ^[0-9]+$ && "$S_COST" =~ ^[0-9.]+$ ]]; then
    S_TIME=$NOW; S_COST=$COST_NUM; LAST_BURN=""
  fi
  [[ "$LAST_BURN" =~ ^[0-9]+\.[0-9]+$ ]] || LAST_BURN=""
  ELAPSED=$(( NOW - S_TIME ))

  if [ "$ELAPSED" -gt 30 ]; then
    BURN=$(awk -v c="$COST_NUM" -v sc="$S_COST" -v e="$ELAPSED" \
      'BEGIN { r=(c-sc)/e*60; if(r>0.0001) printf "%.4f", r; else print "" }')
    [ -n "$BURN" ] && LAST_BURN="$BURN"
    if [ "$ELAPSED" -gt 300 ]; then
      S_TIME=$NOW; S_COST=$COST_NUM
    fi
  fi
  [ -n "$LAST_BURN" ] && BURN_DISPLAY="${GRAY}↑ \$${LAST_BURN}/min"
  printf '%s %s %s\n' "$S_TIME" "$S_COST" "$LAST_BURN" > "$STATE_FILE"
fi

# ── SEC_MCP ───────────────────────────────────────────────────────────────────
# Scan transcript for mcp__SERVER__TOOL patterns, incrementally: a cache file
# holds the last-scanned byte offset and the servers found so far, so each
# render only reads transcript bytes appended since the previous one.
# Excludes: auth-only servers, disabled servers from ~/.claude.json, all-caps placeholders.
MCP_DISPLAY=""
if [ "$SHOW_MCP" = 1 ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  MCP_CACHE="${STATE_FILE}_mcp"
  TSIZE=$(wc -c < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')
  OFFSET=0 KNOWN=""
  [ -f "$MCP_CACHE" ] && read -r OFFSET KNOWN < "$MCP_CACHE" 2>/dev/null
  if ! [[ "$OFFSET" =~ ^[0-9]+$ ]] || [ "$OFFSET" -gt "$TSIZE" ]; then
    OFFSET=0; KNOWN=""
  fi

  NEW_SERVERS=$(tail -c +"$((OFFSET + 1))" "$TRANSCRIPT" 2>/dev/null \
    | grep -oE 'mcp__[a-zA-Z0-9_-]+__[a-zA-Z0-9_-]+' \
    | sed -E 's/^mcp__//' \
    | awk -F'__' '
      {
        srv = $1
        tool = $2
        if (srv ~ /^[A-Z_]+$/) next
        if (tool != "authenticate" && tool != "complete_authentication") connected[srv] = 1
      }
      END { for (s in connected) print s }
    ' \
    | sed -E 's/^claude_ai_//')
  SERVERS=$({ tr ',' '\n' <<< "$KNOWN"; printf '%s\n' "$NEW_SERVERS"; } \
    | grep -v '^$' | sort -u | paste -sd, -)
  printf '%s %s\n' "$TSIZE" "$SERVERS" > "$MCP_CACHE"

  if [ -n "$SERVERS" ]; then
    DISABLED_MCPS=$(jq -r --arg cwd "$CWD" \
      '.projects[$cwd].disabledMcpServers // [] | map(sub("^claude\\.ai "; "") | gsub(" "; "_")) | join("|")' \
      ~/.claude.json 2>/dev/null)
    MCP_LIST=$(tr ',' '\n' <<< "$SERVERS" \
      | grep -vE "^(server|${DISABLED_MCPS:-__nomatch__})$" \
      | paste -sd, -)
    [ -n "$MCP_LIST" ] && MCP_DISPLAY="${GRAY}🔌  ${MCP_LIST//,/ · }${RESET}"
  fi
fi

# ── SEC_LIMITS ────────────────────────────────────────────────────────────────
# 5h rate-limit window: only present for Pro/Max after the first API response
LIMITS_DISPLAY=""
if [ "$SHOW_LIMITS" = 1 ] && [ "$LIMIT_PCT" -ge 0 ] 2>/dev/null; then
  if [ "$LIMIT_PCT" -ge 80 ]; then
    LIMIT_COLOR="$BRIGHT_RED"
  elif [ "$LIMIT_PCT" -ge 50 ]; then
    LIMIT_COLOR="$ORANGE"
  else
    LIMIT_COLOR="$BRIGHT_GREEN"
  fi
  if [ "$LIMIT_PCT" -ge 95 ]; then
    LIMIT_ICON="●"
  elif [ "$LIMIT_PCT" -ge 70 ]; then
    LIMIT_ICON="◕"
  elif [ "$LIMIT_PCT" -ge 40 ]; then
    LIMIT_ICON="◑"
  elif [ "$LIMIT_PCT" -ge 10 ]; then
    LIMIT_ICON="◔"
  else
    LIMIT_ICON="○"
  fi
  LIMITS_DISPLAY="${LIMIT_COLOR}${LIMIT_ICON} ${LIMIT_PCT}%"
  if [ "$LIMIT_RESET" -gt 0 ] 2>/dev/null; then
    RESET_TIME=$(date -r "$LIMIT_RESET" +%H:%M 2>/dev/null \
      || date -d "@$LIMIT_RESET" +%H:%M 2>/dev/null)
    [ -n "$RESET_TIME" ] && LIMITS_DISPLAY+="${SPC}${GRAY}↻ ${RESET_TIME}"
  fi
fi

# ── output ────────────────────────────────────────────────────────────────────
SEC_PATH=""
SEC_PATH+="${BRIGHT_YELLOW}${FOLDER}"
SEC_PATH+="${SP}${BRANCH_PART}"
SEC_PATH+="${TECH_DISPLAY:+${SPC}${TECH_DISPLAY}}"

SEC_MODEL=""
SEC_MODEL+="${BOLD}${MODEL_COLOR}◆ ${MODEL_DISPLAY}"
SEC_MODEL+="${SPC}${CTX_COLOR}${BAR} ${CTX_LABEL}"
SEC_MODEL+="${ACTIVITY:+${SPC}${ACTIVITY}}"

SEC_COST=""
[ "$SHOW_COST" = 1 ] && SEC_COST+="${GRAY}\$${COST}"
SEC_COST+="${BURN_DISPLAY:+${SEC_COST:+${SPC}}${BURN_DISPLAY}}"
SEC_COST=${SEC_COST:+${SEP}${SEC_COST}}

SEC_LIMITS=""
SEC_LIMITS+=${LIMITS_DISPLAY:+${SEP}${LIMITS_DISPLAY}}

SEC_MCP=""
SEC_MCP+=${MCP_DISPLAY:+${SEP}${MCP_DISPLAY}}

echo "${SEC_PATH}${SEP}${SEC_MODEL}${SEC_COST}${SEC_LIMITS}${SEC_MCP}${RESET}"
