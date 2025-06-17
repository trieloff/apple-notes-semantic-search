#!/bin/bash

# Process remaining memories from the JSON files
# This script adds each memory as a note

# Remaining memories to process (starting after "User is interested in planning cycling directions and routes")
memories=(
    "June 2025 — Prefers Warren Zevon's original \"Poor Poor Pitiful Me\" over Linda Ronstadt's cover."
    "June 2025 — Lars Trieloff has spoken on Edge Delivery Services, a project he's worked on since its start five years ago (though he wasn't the sole creator)."
    "June 2025 — Lars is building a fast, powerful personal website."
    "June 2025 — At Adobe he works on AEM Sites as a Cloud Service, focusing on document-based authoring."
    "June 2025 — Twitter account was closed in 2016 and re-opened in June 2025 to follow AI news"
    "June 2025 — He rarely re-reads books or re-watches shows, seeking fresh experiences instead."
    "June 2025 — Prefers digital music for quality yet keeps vinyl for nostalgia."
    "June 2025 — Night owl schedule maximises overlap with U.S. teams."
    "June 2025 — Top travel picks: Japan, Denmark, and Israel—he favours small countries."
    "June 2025 — Adventurous eater but a non-ambitious cook."
    "June 2025 — Signature drink at the desk: blood-orange lemonade with iced matcha; he also enjoys Thai Iced Tea, Iced Matcha Latte, Red Bull Simply Cola, and Coke Zero."
    "June 2025 — He listens to tech, philosophy, and sci-fi podcasts or audiobooks."
    "June 2025 — He aims for a creative yet minimalist workspace, though mild clutter appears at times."
)

echo "Processing ${#memories[@]} memories..."

# Process each memory
for memory in "${memories[@]}"; do
    echo "Adding: ${memory:0:50}..."
    if ./add-note.sh "$memory"; then
        echo "✅ Added"
    else
        echo "❌ Failed to add: ${memory:0:100}"
        echo "Continuing with next memory..."
    fi
    echo ""
done

echo "All memories processed!"