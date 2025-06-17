#!/bin/bash
set -euo pipefail

TOTAL=$(git rev-list --count HEAD)
VIBE=0
for COMMIT in $(git rev-list HEAD); do
  AUTHOR="$(git show -s --format='%an <%ae>' "$COMMIT")"
  BODY="$(git show -s --format='%B' "$COMMIT")"
  if echo "$AUTHOR" | grep -iE 'claude|codex|cursor|zed|windsurf|openai' >/dev/null \
     || echo "$BODY" | grep -iE '🤖|generated with|co-?authored-?by:.*(claude|codex|cursor|zed|windsurf|openai)|signed-off-by:.*(claude|codex|cursor|zed|windsurf|openai)' >/dev/null; then
    VIBE=$((VIBE + 1))
  fi
done

if [ "$TOTAL" -eq 0 ]; then
  PERCENT=0
else
  PERCENT=$((100 * VIBE / TOTAL))
fi

NEW_BADGE="[![${PERCENT}% Vibe Coded](https://img.shields.io/badge/${PERCENT}%25-Vibe_Coded-ff69b4?style=for-the-badge&logo=headphones&logoColor=white)](https://github.com/trieloff/apple-notes-semantic-search)"
ESC_BADGE=$(printf '%s\n' "$NEW_BADGE" | sed 's/[#&]/\\&/g')

perl -0pi -e "s#\[!\[\d+% Vibe Coded\]\(https://img.shields.io/badge/\d+%25-Vibe_Coded-ff69b4\?style=for-the-badge&logo=headphones&logoColor=white\)\]\(https://github.com/trieloff/apple-notes-semantic-search\)#$ESC_BADGE#" README.md

if ! git diff --quiet README.md; then
  git config user.name 'github-actions[bot]'
  git config user.email 'github-actions[bot]@users.noreply.github.com'
  git add README.md
  git commit -m "Update vibe-coded badge to ${PERCENT}% [skip vibe-badge]"
  touch /tmp/badge_changed
fi
