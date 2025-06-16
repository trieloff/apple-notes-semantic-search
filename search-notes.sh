#!/bin/bash

# Script to search Apple Notes using similarity search on embeddings
# Usage: ./search-notes.sh "search query" [--limit N]

set -e

COLLECTION_NAME="notes-memory"
DEFAULT_LIMIT=5

# Function to show usage
show_usage() {
    echo "Usage: $0 \"search query\" [--limit N]"
    echo "  search query: Text to search for in your notes"
    echo "  --limit N:    Number of results to return (default: $DEFAULT_LIMIT)"
    echo ""
    echo "Examples:"
    echo "  $0 \"vacation plans\""
    echo "  $0 \"meeting notes\" --limit 10"
    exit 1
}

# Parse arguments
QUERY=""
LIMIT=$DEFAULT_LIMIT

while [[ $# -gt 0 ]]; do
    case $1 in
        --limit)
            if [[ -z "$2" ]] || [[ "$2" =~ ^- ]]; then
                echo "Error: --limit requires a number"
                show_usage
            fi
            LIMIT="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            ;;
        -*)
            echo "Error: Unknown option $1"
            show_usage
            ;;
        *)
            if [[ -z "$QUERY" ]]; then
                QUERY="$1"
            else
                echo "Error: Multiple queries provided. Please quote your search query."
                show_usage
            fi
            shift
            ;;
    esac
done

# Check if query is provided
if [[ -z "$QUERY" ]]; then
    echo "Error: No search query provided"
    show_usage
fi

# Validate limit is a number
if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [[ "$LIMIT" -eq 0 ]]; then
    echo "Error: --limit must be a positive number"
    show_usage
fi

# Check if required tools are available
if ! command -v llm &> /dev/null; then
    echo "Error: llm command not found. Please install it first."
    exit 1
fi

if ! command -v notes-app &> /dev/null; then
    echo "Error: notes-app command not found. Please install it first."
    exit 1
fi

echo "Searching for: \"$QUERY\""
echo "Limit: $LIMIT results"
echo ""

# Perform similarity search (returns JSONL format - one JSON object per line)
search_results=$(llm similar "$COLLECTION_NAME" -c "$QUERY" -n "$LIMIT" 2>/dev/null || echo "")

if [[ -z "$search_results" ]]; then
    echo "No results found. The collection might be empty or the query didn't match any notes."
    echo "Try running ./index-notes.sh first to populate the collection."
    exit 0
fi

# Parse JSONL results and display with full note content
echo "$search_results" | while IFS= read -r result_json; do
    # Skip empty lines
    [[ -z "$result_json" ]] && continue
    
    # Extract fields from JSON
    note_id=$(echo "$result_json" | jq -r '.id // "unknown"')
    score=$(echo "$result_json" | jq -r '.score // "N/A"')
    content=$(echo "$result_json" | jq -r '.content // "No content"')
    title=$(echo "$result_json" | jq -r '.metadata.title // "Untitled"')
    date=$(echo "$result_json" | jq -r '.metadata.date // "Unknown date"')
    
    # Display the result
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Title: $title"
    echo "📅 Date: $date"
    if [[ "$score" != "N/A" ]]; then
        echo "🎯 Similarity: $score"
    fi
    echo "🆔 ID: $note_id"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Extract just the content part (remove "Title: ... Content:" prefix)
    clean_content=$(echo "$content" | sed -n '/Content:/,$p' | sed '1d')
    if [[ -z "$clean_content" ]]; then
        clean_content="$content"
    fi
    
    echo "$clean_content"
    echo ""
done

echo "Search completed."