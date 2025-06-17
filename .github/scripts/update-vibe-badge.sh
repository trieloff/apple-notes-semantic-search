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

# Counters for each AI type
CLAUDE_COUNT=0
CODEX_COUNT=0
WINDSURF_COUNT=0
CURSOR_COUNT=0
ZED_COUNT=0
OPENAI_COUNT=0
BOT_COUNT=0

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
  
  # Count AI commits by type
  if $IS_AI && [ -n "$AI_TYPE" ]; then
    case "$AI_TYPE" in
      "Claude") CLAUDE_COUNT=$((CLAUDE_COUNT + 1)) ;;
      "Codex") CODEX_COUNT=$((CODEX_COUNT + 1)) ;;
      "Windsurf") WINDSURF_COUNT=$((WINDSURF_COUNT + 1)) ;;
      "Cursor") CURSOR_COUNT=$((CURSOR_COUNT + 1)) ;;
      "Zed") ZED_COUNT=$((ZED_COUNT + 1)) ;;
      "OpenAI") OPENAI_COUNT=$((OPENAI_COUNT + 1)) ;;
      "Bot") BOT_COUNT=$((BOT_COUNT + 1)) ;;
    esac
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

# Determine which logo to use based on most common AI type
LOGO="githubcopilot"  # default
MAX_COUNT=0

# Check each AI type
if [ "$CLAUDE_COUNT" -gt "$MAX_COUNT" ]; then
  MAX_COUNT="$CLAUDE_COUNT"
  LOGO="claude"
fi
if [ "$CODEX_COUNT" -gt "$MAX_COUNT" ]; then
  MAX_COUNT="$CODEX_COUNT"
  LOGO="openai"
fi
if [ "$WINDSURF_COUNT" -gt "$MAX_COUNT" ]; then
  MAX_COUNT="$WINDSURF_COUNT"
  LOGO="windsurf"
fi
if [ "$CURSOR_COUNT" -gt "$MAX_COUNT" ]; then
  MAX_COUNT="$CURSOR_COUNT"
  LOGO="githubcopilot"
fi
if [ "$ZED_COUNT" -gt "$MAX_COUNT" ]; then
  MAX_COUNT="$ZED_COUNT"
  LOGO="githubcopilot"
fi
if [ "$OPENAI_COUNT" -gt "$MAX_COUNT" ]; then
  MAX_COUNT="$OPENAI_COUNT"
  LOGO="openai"
fi
if [ "$BOT_COUNT" -gt "$MAX_COUNT" ]; then
  MAX_COUNT="$BOT_COUNT"
  LOGO="githubcopilot"
fi

# Display debug output
if $DEBUG; then
  echo "=== Vibe Badge Debug Mode ==="
  echo "Total commits: $TOTAL"
  echo ""
  echo "AI-generated commits: $VIBE (${PERCENT}%)"
  echo "Human commits: $((TOTAL - VIBE)) ($((100 - PERCENT))%)"
  echo ""
  echo "AI Breakdown:"
  [ "$CLAUDE_COUNT" -gt 0 ] && printf "  %-10s: %d\n" "Claude" "$CLAUDE_COUNT"
  [ "$CODEX_COUNT" -gt 0 ] && printf "  %-10s: %d\n" "Codex" "$CODEX_COUNT"
  [ "$WINDSURF_COUNT" -gt 0 ] && printf "  %-10s: %d\n" "Windsurf" "$WINDSURF_COUNT"
  [ "$CURSOR_COUNT" -gt 0 ] && printf "  %-10s: %d\n" "Cursor" "$CURSOR_COUNT"
  [ "$ZED_COUNT" -gt 0 ] && printf "  %-10s: %d\n" "Zed" "$ZED_COUNT"
  [ "$OPENAI_COUNT" -gt 0 ] && printf "  %-10s: %d\n" "OpenAI" "$OPENAI_COUNT"
  [ "$BOT_COUNT" -gt 0 ] && printf "  %-10s: %d\n" "Bot" "$BOT_COUNT"
  echo ""
  echo "Selected logo: $LOGO"
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
  NEW_BADGE="[![${PERCENT}% Vibe Coded](https://img.shields.io/badge/${PERCENT}%25-Vibe_Coded-ff69b4?style=for-the-badge&logo=${LOGO}&logoColor=white)](https://github.com/trieloff/apple-notes-semantic-search)"
  ESC_BADGE=$(printf '%s\n' "$NEW_BADGE" | sed 's/[#&]/\\&/g')

  perl -0pi -e "s#\[!\[\d+% Vibe Coded\]\(https://img.shields.io/badge/\d+%25-Vibe_Coded-ff69b4\?style=for-the-badge&logo=[^&]*&logoColor=white\)\]\(https://github.com/trieloff/apple-notes-semantic-search\)#$ESC_BADGE#" README.md

  if ! git diff --quiet README.md; then
    git config user.name 'github-actions[bot]'
    git config user.email 'github-actions[bot]@users.noreply.github.com'
    git add README.md
    git commit -m "Update vibe-coded badge to ${PERCENT}% [skip vibe-badge]"
    touch /tmp/badge_changed
  fi
fi
