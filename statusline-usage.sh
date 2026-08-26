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
token=""
if command -v security >/dev/null 2>&1; then
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
          | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
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
# Shape-tolerant on purpose: walk the whole document for the per-model weekly entries
# rather than assuming where the server nests them. Claude Code picks them out as
# `kind == "weekly_scoped"` with a `scope.model.display_name`, reading `percent` and
# `resets_at`; utilization/used_percentage are accepted as aliases in case the field
# is renamed. The label is scrubbed to plain text so nothing from the wire can inject
# escape codes or a line break into the status line. Values arrive as either a 0-1
# fraction or a 0-100 percentage, and anything
# at or below 1 is treated as a fraction, which is how Claude Code reads utilization.
parsed=$(printf '%s' "$resp" | jq -r '
  def pct: if . == null then null
           elif . <= 1 then (. * 100)
           else . end;
  def epoch:
    if . == null then 0
    elif (type == "number") then (. | floor)
    else (try (fromdateiso8601) catch 0) end;
  [ .. | objects
    | select((.kind? // "") == "weekly_scoped")
    | select(.scope?.model?.display_name? != null)
    | { name:  (.scope.model.display_name | tostring | gsub("[^A-Za-z0-9 ._+-]"; "") | .[0:24]),
        p:     ((.percent // .utilization // .used_percentage) | pct),
        r:     ((.resets_at // .reset_at // null) | epoch) }
    | select(.p != null) ]
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
