#!/bin/bash
set -euo pipefail

# Parse debug flag
DEBUG=false
if [[ "${1:-}" == "--debug" || "${1:-}" == "-d" ]]; then
  DEBUG=true
fi

TOTAL=$(git rev-list --count HEAD)
VIBE=0

# Arrays to store commits by type
declare -a AI_COMMITS=()
declare -a HUMAN_COMMITS=()

for COMMIT in $(git rev-list HEAD); do
  AUTHOR="$(git show -s --format='%an <%ae>' "$COMMIT")"
  BODY="$(git show -s --format='%B' "$COMMIT")"
  SUBJECT="$(git show -s --format='%s' "$COMMIT")"
  DATE="$(git show -s --format='%ad' --date=short "$COMMIT")"
  
  IS_AI=false
  AI_TYPE=""
  
  # Check if commit is on a codex branch
  BRANCHES="$(git branch --contains "$COMMIT" --all 2>/dev/null | grep -E 'remotes/origin/.*codex/' || true)"
  
  # Check for bot commits
  if echo "$AUTHOR" | grep -F '[bot]' >/dev/null; then
    VIBE=$((VIBE + 1))
    IS_AI=true
    AI_TYPE="Bot"
  # Check for AI-generated commits by author or message content
  elif echo "$AUTHOR" | grep -iE 'claude|cursor|zed|windsurf|openai' >/dev/null \
     || echo "$BODY" | grep -iE '🤖|generated with|co-?authored-?by:.*(claude|cursor|zed|windsurf|openai)|signed-off-by:.*(claude|cursor|zed|windsurf|openai)' >/dev/null; then
    VIBE=$((VIBE + 1))
    IS_AI=true
    if echo "$AUTHOR" | grep -i 'claude' >/dev/null || echo "$BODY" | grep -i 'claude' >/dev/null; then
      AI_TYPE="Claude"
    elif echo "$AUTHOR" | grep -i 'cursor' >/dev/null || echo "$BODY" | grep -i 'cursor' >/dev/null; then
      AI_TYPE="Cursor"
    elif echo "$AUTHOR" | grep -i 'windsurf' >/dev/null || echo "$BODY" | grep -i 'windsurf' >/dev/null; then
      AI_TYPE="Windsurf"
    elif echo "$AUTHOR" | grep -i 'zed' >/dev/null || echo "$BODY" | grep -i 'zed' >/dev/null; then
      AI_TYPE="Zed"
    elif echo "$AUTHOR" | grep -i 'openai' >/dev/null || echo "$BODY" | grep -i 'openai' >/dev/null; then
      AI_TYPE="OpenAI"
    else
      AI_TYPE="Unknown AI"
    fi
  # Check for Codex commits (merge commits or any commit on codex branches)
  elif echo "$BODY" | grep -E '^Merge pull request .* from .*/.*codex/.*' >/dev/null || [ -n "$BRANCHES" ]; then
    VIBE=$((VIBE + 1))
    IS_AI=true
    AI_TYPE="Codex"
  fi
  
  if $DEBUG; then
    if $IS_AI; then
      AI_COMMITS+=("$(printf "%-7s | %-10s | %-40.40s | %s" "$COMMIT" "$AI_TYPE" "$SUBJECT" "$DATE")")
    else
      HUMAN_COMMITS+=("$(printf "%-7s | %-40.40s | %s" "$COMMIT" "$SUBJECT" "$DATE")")
    fi
  fi
done

if [ "$TOTAL" -eq 0 ]; then
  PERCENT=0
else
  PERCENT=$((100 * VIBE / TOTAL))
fi

# Display debug output
if $DEBUG; then
  echo "=== Vibe Badge Debug Mode ==="
  echo "Total commits: $TOTAL"
  echo ""
  echo "AI-generated commits: $VIBE (${PERCENT}%)"
  echo "Human commits: $((TOTAL - VIBE)) ($((100 - PERCENT))%)"
  echo ""
  echo "AI Commits:"
  echo "-----------"
  echo "SHA     | Type       | Subject                                  | Date"
  echo "--------|------------|------------------------------------------|----------"
  if [ ${#AI_COMMITS[@]} -gt 0 ]; then
    printf "%s\n" "${AI_COMMITS[@]}" | sort -k4 -r
  else
    echo "None"
  fi
  echo ""
  echo "Human Commits:"
  echo "--------------"
  echo "SHA     | Subject                                  | Date"
  echo "--------|------------------------------------------|----------"
  if [ ${#HUMAN_COMMITS[@]} -gt 0 ]; then
    printf "%s\n" "${HUMAN_COMMITS[@]}" | sort -k3 -r
  else
    echo "None"
  fi
  echo ""
fi

# Only update badge if not in debug mode
if ! $DEBUG; then
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
fi
