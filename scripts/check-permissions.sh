#!/usr/bin/env bash
# Fails when Swift code uses an API behind a permission outside the places allowed to: Sources/Whippet/Permissions/,
# where PermissionGate checks each use against what the module declares, and WhippetCore's ScopedSession, the only
# network session. New code goes through those instead, so Settings › Commands shows everything Whippet does.
set -euo pipefail
cd "$(dirname "$0")/.."

apis='URLSession\(|URLSession\.shared|LPMetadataProvider|AXIsProcessTrusted|CGRequestScreenCaptureAccess|CGPreflightScreenCaptureAccess|SCShareableContent|SCScreenshotManager|NSAppleScript|UNUserNotificationCenter|CGEvent\(keyboardEventSource'

found="$(
    git ls-files --cached --others --exclude-standard -- '*.swift' \
        | grep -v -e '^Tests/' -e '^Sources/Whippet/Permissions/' -e '^Packages/WhippetCore/Sources/WhippetCore/ScopedSession\.swift$' \
        | while IFS= read -r file; do [ -f "$file" ] && printf '%s\0' "$file"; done \
        | xargs -0 grep -nE "$apis" || true
)"

if [ -n "$found" ]; then
    echo "These use an API behind a permission outside Sources/Whippet/Permissions/ or ScopedSession:" >&2
    echo "$found" >&2
    echo "Go through PermissionGate, or PermissionGate.network(for:), and declare the permission in the module's manifest." >&2
    exit 1
fi
