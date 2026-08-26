#!/usr/bin/env bash
# Claude Code status line · per-model weekly usage fetcher (Fable / Opus / Sonnet caps)
#
# Why this exists: the status line's stdin payload only ever carries the account-wide
# `five_hour` and `seven_day` windows. Claude Code builds that object from exactly two
# fields (verified in 2.1.246's payload builder), so the per-model weekly caps
# (the ones /usage renders as "Current week (Fable 5)") are simply not in it.
#
# Claude Code gets them from GET /api/oauth/usage on the same OAuth token it already
# holds. This script asks the same endpoint, on a throttle, and leaves a tiny cache the
# status line can read with no network and no forks:
#
#   $STATE_DIR/usage-scoped
#     <epoch when fetched>
#     <display name>\t<percent 0-100>\t<reset epoch or 0>
#     ...
#
# The endpoint is internal to Claude Code, so treat it as best-effort: a shape change
# upstream makes the segment disappear, never break the status line.
#
# The token is read from the login keychain (the same item Claude Code stores it in),
# is never printed, never written to disk, and is handed to curl through a --config
# file on stdin so it stays out of the process argument list (`ps` can't see it).
#
# Usage:
#   statusline-usage.sh              refresh the cache (silent; for the background call)
#   statusline-usage.sh --show       refresh, then print what was parsed
#   statusline-usage.sh --raw        print the raw JSON response (no token) and exit
#   statusline-usage.sh --cache      print the current cache without fetching

set -u

STATE_DIR="${TMPDIR:-/tmp}/cc-statusline"
CACHE="$STATE_DIR/usage-scoped"
STAMP="$STATE_DIR/usage-fetch"
ENDPOINT="${SL_USAGE_ENDPOINT:-https://api.anthropic.com/api/oauth/usage}"
BETA="oauth-2025-04-20"

mode="refresh"
case "${1:-}" in
  --show)  mode="show"  ;;
  --raw)   mode="raw"   ;;
  --cache) mode="cache" ;;
  '')      ;;
  *) printf 'usage: %s [--show|--raw|--cache]\n' "${0##*/}" >&2; exit 2 ;;
esac

if [ "$mode" = "cache" ]; then
  [ -f "$CACHE" ] && cat "$CACHE"
  exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null
command -v jq   >/dev/null 2>&1 || exit 1
command -v curl >/dev/null 2>&1 || exit 1

# --- token ---------------------------------------------------------------------------
# Keychain first (where Claude Code keeps it on macOS), then the file fallback used on
# Linux / by `claude setup-token`. Captured into a variable, never echoed.
#
# The account matters. Two generic-password items share the service name
# "Claude Code-credentials": the one keyed to your username holds claudeAiOauth, and a
# second one (acct "unknown") holds only per-server mcpOAuth tokens. A lookup by service
# alone returns whichever the keychain hands back first, which is how this first came
# back tokenless. Claude Code itself always passes -a, so this asks for the username
# first and only then falls back to a service-only match.
token=""
if command -v security >/dev/null 2>&1; then
  for _acct in "${USER:-$(id -un 2>/dev/null)}" ""; do
    if [ -n "$_acct" ]; then
      token=$(security find-generic-password -s "Claude Code-credentials" -a "$_acct" -w 2>/dev/null \
              | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    else
      token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
              | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    fi
    [ -n "$token" ] && break
  done
  unset _acct
fi
if [ -z "$token" ] && [ -f "$HOME/.claude/.credentials.json" ]; then
  token=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
fi
if [ -z "$token" ]; then
  [ "$mode" != "refresh" ] && echo "no OAuth token found (keychain item 'Claude Code-credentials')" >&2
  exit 1
fi

# --- fetch ---------------------------------------------------------------------------
# --config - keeps the Authorization header off the command line. -f so a 401/5xx is a
# failure rather than an HTML body we would try to parse.
resp=$(printf 'header = "Authorization: Bearer %s"\nheader = "anthropic-beta: %s"\nheader = "Content-Type: application/json"\nsilent\nshow-error\nfail\nmax-time = 8\nurl = "%s"\n' \
         "$token" "$BETA" "$ENDPOINT" | curl --config - 2>/dev/null)
rc=$?          # must be read before anything else runs, `unset` would clobber it
unset token

# Record the attempt either way so a failing endpoint backs off instead of retrying
# on every render.
date '+%s' > "$STAMP" 2>/dev/null

if [ $rc -ne 0 ] || [ -z "$resp" ]; then
  [ "$mode" != "refresh" ] && echo "fetch failed (curl exit $rc)" >&2
  exit 1
fi

if [ "$mode" = "raw" ]; then
  printf '%s' "$resp" | jq . 2>/dev/null || printf '%s\n' "$resp"
  exit 0
fi

# --- parse ---------------------------------------------------------------------------
# The endpoint answers with a `limits` array whose entries look like
#   {kind, group, is_active, percent, resets_at, scope, severity}
# and kind is one of session / weekly_all / weekly_scoped. The per-model rows are the
# weekly_scoped ones, carrying scope.model.display_name ("Fable"). `percent` is already
# 0-100; `utilization`, which is what Claude Code reads elsewhere, is a 0-1 fraction, so
# it is scaled only if that alias is what turns up.
#
# The walk is deliberately shape-tolerant (.. rather than .limits[]) because the endpoint
# is internal and undocumented. The label is scrubbed to plain text so nothing from the
# wire can inject escape codes or a line break into the status line.
#
# resets_at arrives as "2026-09-01T14:00:00.246196+00:00": jq's fromdateiso8601 rejects
# both the fractional seconds and the numeric offset, so both are normalised away first
# and the offset is added back by hand.
parsed=$(printf '%s' "$resp" | jq -r '
  def epoch:
    if . == null then 0
    elif type == "number" then floor
    else ( tostring
           | sub("\\.[0-9]+"; "")
           | capture("^(?<t>[^+Z]+)(?<z>Z|[+-][0-9]{2}:[0-9]{2})?$")
           | ((.t + "Z") | fromdateiso8601) as $base
           | if (.z // "Z") == "Z" then $base
             else ( (.z | sub(":"; "")) as $off
                    | (($off[1:3] | tonumber) * 3600 + ($off[3:5] | tonumber) * 60) as $secs
                    | if $off[0:1] == "-" then $base + $secs else $base - $secs end )
             end )
    end;
  [ .. | objects
    | select((.kind? // "") == "weekly_scoped")
    | select(.scope?.model?.display_name? != null)
    | { name: (.scope.model.display_name | tostring | gsub("[^A-Za-z0-9 ._+-]"; "") | .[0:24]),
        p:    (if .percent != null then .percent
               elif .utilization != null then (.utilization * 100)
               else .used_percentage end),
        r:    ((.resets_at // .reset_at // .resetsAt // null) | (try epoch catch 0)) }
    | select(.p != null and .name != "") ]
  | unique_by(.name)
  | .[] | "\(.name)\t\(.p | round)\t\(.r)"
' 2>/dev/null)

# An empty parse is a legitimate answer (the account may have no per-model cap), so
# refresh the cache anyway: a stale reading is worse than an honest blank.
{ date '+%s'; [ -n "$parsed" ] && printf '%s\n' "$parsed"; } > "$CACHE.$$" 2>/dev/null &&
  chmod 600 "$CACHE.$$" 2>/dev/null &&
  mv -f "$CACHE.$$" "$CACHE" 2>/dev/null

if [ "$mode" = "show" ]; then
  if [ -n "$parsed" ]; then
    printf '%s\n' "$parsed" | while IFS=$'\t' read -r n p r; do
      printf '%-12s %3s%%  resets_at=%s\n' "$n" "$p" "$r"
    done
  else
    echo "no per-model weekly windows in the response"
    echo "(run with --raw to see what the endpoint returned)"
  fi
fi
exit 0
