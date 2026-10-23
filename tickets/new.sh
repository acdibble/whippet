#!/usr/bin/env bash
# Creates a backlog ticket with the next free ID and prints its path.
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "usage: $0 \"Ticket title\"" >&2
  exit 1
fi

dir="$(cd "$(dirname "$0")" && pwd)"
title="$*"
slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
last="$(find "$dir" -name '[0-9][0-9][0-9][0-9]-*.md' -exec basename {} \; | cut -c1-4 | sort -n | tail -1)"
id="$(printf '%04d' $((10#${last:-0} + 1)))"
path="$dir/backlog/$id-$slug.md"

cat > "$path" <<TICKET
---
priority: medium
labels: []
---

# $title

What and why, in a few sentences.

## Done when

- [ ] 

## Notes

TICKET

echo "$path"
