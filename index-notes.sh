#!/bin/bash

# Script to index Apple Notes from "Memories" folder into LLM embeddings
# Usage: ./index-notes.sh [--continue]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "$SCRIPT_DIR/common.sh"
init_common

# Script-specific config
INDEXER_CONFIG_FILE="$HOME/.notes-indexer-config"

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to read last run timestamp
get_last_run() {
    if [[ -f "$INDEXER_CONFIG_FILE" ]]; then
        cat "$INDEXER_CONFIG_FILE"
    else
        echo ""
    fi
}

# Function to save current timestamp
save_timestamp() {
    echo "$(get_timestamp)" > "$INDEXER_CONFIG_FILE"
}

# Function to check if a note is newer than last run
is_note_newer() {
    local note_date="$1"
    local last_run="$2"
    
    if [[ -z "$last_run" ]]; then
        return 0  # No last run, so include all notes
    fi
    
    # Parse notes-app date format: "date Tuesday, 17. June 2025 at 06:39:34"
    # Extract just the date/time portion and use date command to parse it
    local date_part=$(echo "$note_date" | sed 's/date [^,]*, //' | sed 's/ at / /')
    
    # Try to convert the date to epoch seconds using date command's flexible parsing
    local note_seconds=$(date -j -f "%d. %B %Y %H:%M:%S" "$date_part" "+%s" 2>/dev/null || echo "0")
    local last_run_seconds=$(date -j -f "%Y-%m-%d %H:%M:%S" "$last_run" "+%s" 2>/dev/null || echo "0")
    
    [[ $note_seconds -gt $last_run_seconds ]]
}

# Check if --continue flag is provided
CONTINUE_MODE=false
if [[ "$1" == "--continue" ]]; then
    CONTINUE_MODE=true
fi

# Get last run timestamp if in continue mode
LAST_RUN=""
if [[ "$CONTINUE_MODE" == true ]]; then
    LAST_RUN=$(get_last_run)
    if [[ -z "$LAST_RUN" ]]; then
        echo "No previous run found. Running full index..."
        CONTINUE_MODE=false
    else
        echo "Continuing from last run: $LAST_RUN"
    fi
fi

# Tools are already checked in init_common

echo "Starting notes indexing..."
if [[ "$CONTINUE_MODE" == true ]]; then
    echo "Mode: Incremental (since $LAST_RUN)"
else
    echo "Mode: Full index"
fi

# Get notes from the Memories folder
echo "Retrieving notes from '$FOLDER_NAME' folder..."

# First get list of note names to iterate over
NOTES_NAMES=$(notes-app list --folder "$FOLDER_NAME" 2>/dev/null || echo "")

if [[ -z "$NOTES_NAMES" ]]; then
    echo "No notes found in '$FOLDER_NAME' folder."
    exit 0
fi

# Process each note by name
echo "$NOTES_NAMES" | while IFS= read -r note_name; do
    # Skip empty lines
    if [[ -z "$note_name" ]]; then
        continue
    fi
    
    echo "Processing note: $note_name"
    
    # Get note properties
    note_properties=$(notes-app show "$note_name" --folder "$FOLDER_NAME" --properties id,modificationDate,body 2>/dev/null || echo "")
    
    if [[ -z "$note_properties" ]]; then
        echo "Warning: Could not retrieve properties for note '$note_name'"
        continue
    fi
    
    # Parse properties (they come line by line)
    note_id=$(echo "$note_properties" | sed -n '1p')
    note_date=$(echo "$note_properties" | sed -n '2p')
    # Body starts from line 3 and may be multi-line
    note_content=$(echo "$note_properties" | sed -n '3,$p')
    
    # Check if note is newer than last run (if in continue mode)
    if [[ "$CONTINUE_MODE" == true ]] && [[ -n "$note_date" ]] && [[ -n "$LAST_RUN" ]]; then
        if ! is_note_newer "$note_date" "$LAST_RUN"; then
            echo "Skipping unchanged note: $note_name"
            continue
        fi
    fi
    
    # Create a combined text for embedding (title + content)
    combined_text="Title: $note_name

Content:
$note_content"
    
    # Store in LLM embeddings with metadata
    embedding_model=$(get_embedding_model)
    echo "$combined_text" | $LLM_CMD embed \
        -m "$embedding_model" \
        "$COLLECTION_NAME" \
        "$note_id" \
        --metadata "{\"title\":\"$note_name\",\"date\":\"$note_date\",\"folder\":\"$FOLDER_NAME\"}" \
        --store \
        2>/dev/null || echo "Warning: Failed to embed note '$note_name'"
    
    echo "Embedded note: $note_name"
done

# Save current timestamp
save_timestamp
echo "Indexing completed at $(get_timestamp)"
echo "Next run can use --continue flag for incremental updates"