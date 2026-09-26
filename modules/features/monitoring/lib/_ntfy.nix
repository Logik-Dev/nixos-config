{ pkgs }:
# Shared ntfy publisher. Each caller sources this file and pipes the body:
#   printf '%s' "$body" | push_ntfy <topic> <title> <tags> <priority>
# One implementation for the service-failure notifier, the smartd mailer shim
# and the backup drills (previously three near-identical curl invocations).
pkgs.writeText "push-ntfy.sh" ''
  push_ntfy() {
    local topic="$1" title="$2" tags="$3" priority="$4"
    ${pkgs.curl}/bin/curl -s \
      -H "Title: $title" \
      -H "Priority: $priority" \
      -H "Tags: $tags" \
      --data-binary @- "http://localhost:2586/$topic" >/dev/null 2>&1 || true
  }
''
