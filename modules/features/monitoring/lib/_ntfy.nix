{ pkgs }:
# Shared ntfy publisher. Each caller sources this file and pipes the body:
#   printf '%s' "$body" | push_ntfy <topic> <title> <tags> <priority>
# Optional extras come from the environment so the signature stays stable:
#   NTFY_CLICK=<url>       -> tapping the notification opens this
#   NTFY_ACTIONS=<spec>    -> ntfy action buttons, e.g. "view, Grafana, https://…"
# One implementation for the service-failure notifier, the smartd mailer shim
# and the backup drills (previously three near-identical curl invocations).
#
# Publication is RETRIED and, as a last resort, SPOOLED to disk. The previous
# one-shot `curl -s … >/dev/null 2>&1 || true` lost alerts silently: measured on
# 2026-09-28, cf-ddns failed at 14:03:07 (no DNS yet at boot), notify-failure ran,
# and the message never arrived because ntfy-sh only started listening at
# 14:03:08. A failed publish was indistinguishable from no failure at all.
# The race is structural — every boot and every `nh os switch` restarts ntfy-sh
# while units are failing around it. See docs/notifications-plan.md §2.1.
#
# Callers run under `set -Eeuo pipefail` (the drills' reportLib) or with no
# flags at all, so every statement here must be safe under -e/-u/pipefail and
# push_ntfy must always return 0: spooling *is* success from the caller's point
# of view, and a notifier that kills its caller would be worse than a late
# message.
let
  # 0 = first attempt, then back off. Worst case ≈ 28 s (8 s of sleeps + 4 curl
  # timeouts), comfortably inside the 90 s DefaultTimeoutStartSec of the oneshot
  # units that call this. Anything longer belongs to the spool, not to a retry.
  attemptDelays = "0 1 2 5";
  spoolDir = "/var/lib/ntfy-spool";
in
pkgs.writeText "push-ntfy.sh" ''
  NTFY_URL="''${NTFY_URL:-http://localhost:2586}"
  NTFY_SPOOL_DIR="''${NTFY_SPOOL_DIR:-${spoolDir}}"

  # One "Header: value" line per header, which is both what curl needs and what
  # the spool stores — a spooled line IS the HTTP header, so adding a header
  # never needs a new spool format. Verified against ntfy 2.24/2.27: raw UTF-8
  # in a header value round-trips untouched, emoji and em-dash included, so the
  # titles built by notify-failure need no RFC 2047 encoding.
  _ntfy_headers() {
    printf 'Title: %s\n' "$2"
    printf 'Priority: %s\n' "$4"
    printf 'Tags: %s\n' "$3"
    if [ -n "''${NTFY_CLICK:-}" ]; then
      printf 'Click: %s\n' "$NTFY_CLICK"
    fi
    if [ -n "''${NTFY_ACTIONS:-}" ]; then
      printf 'Actions: %s\n' "$NTFY_ACTIONS"
    fi
    return 0
  }

  # POST one message: $1 = topic, $2 = the header block, body on stdin. Returns
  # non-zero on transport error AND on HTTP >= 400 (-f), so an ACL rejection is
  # treated as a failure instead of being reported as a delivered notification.
  _ntfy_post() {
    local topic="$1" headers="$2" line
    local -a args=()
    while IFS= read -r line; do
      if [ -n "$line" ]; then
        args+=(-H "$line")
      fi
    done <<<"$headers"
    ${pkgs.curl}/bin/curl -sS -f -m 5 \
      "''${args[@]}" \
      --data-binary @- "$NTFY_URL/$topic" >/dev/null 2>&1
  }

  # Last resort: hand the message to ntfy-spool-drain.service (every 2 min).
  # Written as .part then renamed so the drain never reads a half-written file.
  # The spool dir is a 1733 drop-box (tmpfiles, notification.nix), so the
  # non-root callers — the postgres restore drill runs as `postgres` — can
  # create and rename their own files without being able to list the others'.
  _ntfy_spool() {
    local topic="$1" headers="$2" body="$3" title f
    title="$(printf '%s\n' "$headers" | ${pkgs.gnused}/bin/sed -n 's/^Title: //p')"
    f="$NTFY_SPOOL_DIR/$(${pkgs.coreutils}/bin/date +%s)-$$-$RANDOM.msg"
    if {
      printf 'Topic: %s\n' "$topic"
      printf '%s\n' "$headers"
      printf '\n'
      printf '%s' "$body"
    } >"$f.part" 2>/dev/null && ${pkgs.coreutils}/bin/mv -f "$f.part" "$f" 2>/dev/null; then
      echo "push_ntfy: '$topic' injoignable, message mis en attente dans $f" >&2
    else
      # Nothing left to try; make the loss loud in the journal rather than silent.
      ${pkgs.coreutils}/bin/rm -f "$f.part" 2>/dev/null || :
      echo "push_ntfy: '$topic' injoignable ET spool impossible ($NTFY_SPOOL_DIR) — MESSAGE PERDU : $title" >&2
    fi
    return 0
  }

  push_ntfy() {
    local topic="$1" title="$2" tags="$3" priority="$4" body headers delay

    body="$(${pkgs.coreutils}/bin/cat)"

    # A newline in a header value is rejected by HTTP and would also break the
    # one-header-per-line spool block; strip it rather than lose the message.
    # Only the smartd shim builds a title from external input (a mail Subject).
    title="$(printf '%s' "$title" | ${pkgs.coreutils}/bin/tr -d '\n\r')"
    tags="$(printf '%s' "$tags" | ${pkgs.coreutils}/bin/tr -d '\n\r')"
    headers="$(_ntfy_headers "$topic" "$title" "$tags" "$priority")"

    for delay in ${attemptDelays}; do
      if [ "$delay" -gt 0 ]; then
        ${pkgs.coreutils}/bin/sleep "$delay"
      fi
      if printf '%s' "$body" | _ntfy_post "$topic" "$headers"; then
        return 0
      fi
    done

    _ntfy_spool "$topic" "$headers" "$body"
  }
''
