#!/bin/bash

# Script to add a note with AI-generated tags to Apple Notes Memories folder
# Usage: ./add-note.sh "note content"
# Or: echo "note content" | ./add-note.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "$SCRIPT_DIR/common.sh"
init_common

# Function to show usage
show_usage() {
    echo "Usage: $0 \"note content\""
    echo "   or: echo \"note content\" | $0"
    echo ""
    echo "This script will:"
    echo "1. Add relevant tags to your note using AI"
    echo "2. Store the tagged note in the '$FOLDER_NAME' folder in Apple Notes"
    echo "3. Trigger a background reindex of the notes collection"
    echo ""
    echo "Examples:"
    echo "  $0 \"Had a great meeting with the team about the new project\""
    echo "  echo \"Planning vacation to Japan next summer\" | $0"
    exit 1
}

# Function to generate tags using LLM
generate_tags() {
    local content="$1"
    
    local prompt="Please analyze the following text and suggest up to 5 relevant tags from this list: #work #coding #personal #family #travel #health #finance #learning #creative #social #planning #ideas #goals #memories #projects #meetings #food #entertainment #sports #books #music #technology #home #shopping #career #education #relationships #hobbies #fitness #mental-health #inspiration #quotes #recipes #tips #events #news #research #documentation #tasks #reminders #reviews #reflections #gratitude #achievements #challenges #solutions #decisions #insights #questions #observations #experiences #discoveries #breakthroughs #lessons-learned #feedback #brainstorming #strategy #collaboration #communication #leadership #productivity #organization #time-management #self-improvement #mindfulness #creativity #innovation #problem-solving #networking #mentorship #coaching #teaching #presenting #writing #reading #listening #watching #exploring #experimenting #building #designing #analyzing #evaluating #prioritizing #scheduling #tracking #monitoring #reviewing #updating #maintaining #optimizing #automating #streamlining #simplifying #clarifying #documenting #sharing #connecting #engaging #participating #contributing #supporting #helping #volunteering #celebrating #appreciating #recognizing #encouraging #motivating #inspiring #empowering #growing #developing #evolving #transforming #changing #adapting #improving #enhancing #upgrading #expanding #advancing #progressing #succeeding #achieving #accomplishing #completing #finishing #delivering #launching #releasing #publishing #promoting #marketing #investing #saving #budgeting #earning #trading #negotiating #contracting #resolving #creating #constructing #architecting #engineering #programming #scripting #debugging #testing #deploying #training #studying #researching #investigating #discovering #revealing #focusing #concentrating #dedicating #committing #ensuring #securing #protecting #defending #preserving #sustaining #continuing #persisting #persevering #enduring #surviving #thriving #flourishing #prospering #overcoming #conquering #surpassing #exceeding #transcending #elevating #ascending #reaching #attaining #realizing #fulfilling #satisfying #concluding #finalizing #strengthening #reinforcing #supporting #backing #endorsing #validating #confirming #verifying #proving #demonstrating #revealing #displaying #exhibiting #presenting #introducing #unveiling #broadcasting #announcing #declaring #communicating #expressing #conveying #imparting #transmitting #furnishing #equipping #preparing #arranging #organizing #structuring #formatting #styling #decorating #beautifying #modernizing #renovating #refurbishing #restoring #repairing #fixing #mending #healing #curing #treating #addressing #handling #managing #dealing #coping #coordinating #directing #guiding #mentoring #instructing #advising #consulting #counseling #assisting #serving #involving #incorporating #integrating #combining #merging #joining #connecting #linking #relating #associating #partnering #collaborating #cooperating #teaming #grouping #gathering #assembling #congregating #convening #summoning #calling #inviting #welcoming #greeting #receiving #accepting #embracing #adopting #obtaining #acquiring #gaining #securing #capturing #seizing #grasping #holding #keeping #retaining #guaranteeing #promising #devoting #investing #donating #providing #offering #supplying #delivering #sending #transmitting #showing #validating #checking #examining #inspecting #assessing #studying #investigating #exploring #finding #locating #identifying #recognizing #detecting #spotting #noticing #observing #monitoring #following #pursuing #chasing #hunting #searching #seeking #looking #uncovering #exposing #highlighting #emphasizing #stressing #underlining #accentuating #amplifying #magnifying #enlarging #extending #stretching #spreading #progressing #moving #shifting #converting #turning #becoming #transitioning #switching #swapping #exchanging #replacing #substituting #alternating #rotating #cycling #repeating #recurring #returning #coming #going #leaving #departing #arriving

The text of the note to analyze:

$content

Please respond with ONLY the tags, separated by spaces, with no additional text or explanation. Example response: #work #personal #planning"
    
    local model_args=""
    local tagging_model=$(get_tagging_model)
    if [[ -n "$tagging_model" ]]; then
        model_args="-m $tagging_model"
    fi
    
    # Get LLM response and extract only hashtags
    local response=$(echo "$prompt" | $LLM_CMD $model_args "$@" 2>/dev/null | head -1)
    # Extract only valid hashtags using regex
    echo "$response" | grep -oE '#[a-zA-Z0-9_-]+' | tr '\n' ' '
}

# Function to generate a concise title using LLM
generate_title() {
    local content="$1"
    
    local prompt="Please create a concise, descriptive title for the following note content. The title should:
- Be maximum 40 characters long
- Capture the main topic/idea
- Be clear and searchable
- NOT include quotes or special characters
- Be a short phrase, not a full sentence

Note content:
$content

Respond with ONLY the title, no quotes, no explanations."
    
    local model_args=""
    local tagging_model=$(get_tagging_model)
    if [[ -n "$tagging_model" ]]; then
        model_args="-m $tagging_model"
    fi
    
    # Get LLM response and clean it up thoroughly
    local response=$(echo "$prompt" | $LLM_CMD $model_args "$@" 2>/dev/null | head -1)
    # Extract first line and clean up LLM artifacts
    response=$(echo "$response" | sed 's/<|.*|>.*//g' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/^"//; s/"$//')
    # Get just the first part before any explanations
    response=$(echo "$response" | cut -d'<' -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    
    # Ensure it's not too long, fallback to truncation if needed
    if [[ ${#response} -gt 40 ]] || [[ -z "$response" ]]; then
        echo "$(echo "$content" | head -1 | cut -c1-37 | sed 's/[[:space:]]*$//')..."
    else
        echo "$response"
    fi
}

# Function to add note to Apple Notes
add_to_notes() {
    local title="$1"
    local content="$2"
    
    # Use notes-app to create a new note in the Memories folder
    # Match the format of "Remember this" note exactly
    notes-app add "$title" --folder "$FOLDER_NAME" --body "$content" 2>/dev/null
}

# Function to trigger reindex in background
trigger_reindex() {
    local index_script="$SCRIPT_DIR/index-notes.sh"
    
    if [[ -x "$index_script" ]]; then
        echo "Triggering background reindex..."
        # Run indexing in background using nohup to ensure it continues even if parent terminates
        # Redirect output to avoid blocking and ensure process doesn't hang
        (sleep 1 && "$index_script" --continue > /dev/null 2>&1) &
        disown
        echo "Background reindex started."
    else
        echo "Warning: index-notes.sh not found or not executable. Skipping reindex."
    fi
}

# Get note content from arguments or stdin
NOTE_CONTENT=""

if [[ $# -eq 0 ]]; then
    # No arguments provided, check if there's input from stdin
    if [[ -t 0 ]]; then
        # No stdin input either
        show_usage
    else
        # Read from stdin
        NOTE_CONTENT=$(cat)
    fi
else
    # Check for help flag
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        show_usage
    fi
    
    # Use first argument as note content
    NOTE_CONTENT="$1"
fi

# Validate input
if [[ -z "$NOTE_CONTENT" ]]; then
    echo "Error: No note content provided"
    show_usage
fi

# Tools are already checked in init_common

echo "Processing note content..."

# Generate tags using LLM
echo "Generating tags..."
TAGS=$(generate_tags "$NOTE_CONTENT")

if [[ -z "$TAGS" ]]; then
    echo "Warning: No tags generated. Proceeding without tags."
    TAGS=""
fi

# Clean up tags (remove any extra whitespace)
TAGS=$(echo "$TAGS" | xargs)

echo "Generated tags: $TAGS"

# Generate a concise title using LLM
echo "Generating title..."
NOTE_TITLE=$(generate_title "$NOTE_CONTENT")

# For single-line notes, use the content as body too
# For multi-line notes, everything after the first line is body
if [[ $(echo "$NOTE_CONTENT" | wc -l) -eq 1 ]]; then
    # Single line - use full content as body
    NOTE_BODY="$NOTE_CONTENT"
else
    # Multi-line - skip first line for body
    NOTE_BODY=$(echo "$NOTE_CONTENT" | tail -n +2)
fi

# Convert body lines to HTML divs to preserve formatting
if [[ -n "$NOTE_BODY" ]]; then
    FORMATTED_BODY=""
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            FORMATTED_BODY="${FORMATTED_BODY}<div>$line</div>"
        else
            FORMATTED_BODY="${FORMATTED_BODY}<div><br></div>"
        fi
    done <<< "$NOTE_BODY"
else
    FORMATTED_BODY=""
fi

# Create formatted content: tags, then body (if different from title)
# Since notes-app auto-adds the title as first line, we don't repeat it
if [[ -n "$TAGS" ]] && [[ -n "$FORMATTED_BODY" ]]; then
    FORMATTED_CONTENT="<div>$TAGS</div>
<div><br></div>
$FORMATTED_BODY"
elif [[ -n "$TAGS" ]]; then
    FORMATTED_CONTENT="<div>$TAGS</div>"
elif [[ -n "$FORMATTED_BODY" ]]; then
    FORMATTED_CONTENT="<div><br></div>
$FORMATTED_BODY"
else
    # Just the title, no additional content needed
    FORMATTED_CONTENT=""
fi

# Add note to Apple Notes
echo "Adding note to Apple Notes..."
note_id=$(add_to_notes "$NOTE_TITLE" "$FORMATTED_CONTENT")

if [[ $? -eq 0 ]]; then
    echo "✅ Note added successfully to '$FOLDER_NAME' folder"
    echo "📝 Title: $NOTE_TITLE"
    if [[ -n "$TAGS" ]]; then
        echo "🏷️  Tags: $TAGS"
    fi
    
    # Trigger background reindex
    trigger_reindex
else
    echo "❌ Failed to add note to Apple Notes"
    exit 1
fi