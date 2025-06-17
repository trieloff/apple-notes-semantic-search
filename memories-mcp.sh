#!/bin/bash

# Memories MCP Server - Interface for Apple Notes semantic search
# Provides add() and search() tools that call existing scripts

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/memories-mcp-requests.log"

# Ensure log file exists
touch "$LOG_FILE"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Send JSON-RPC response
send_response() {
    local response="$1"
    echo "$response"
    log "Response: $response"
}

# Error response
error_response() {
    local id="$1"
    local code="$2"
    local message="$3"
    local response
    response=$(jq -cn --argjson id "$id" --argjson code "$code" --arg message "$message" '{
        jsonrpc: "2.0",
        id: $id,
        error: {
            code: $code,
            message: $message
        }
    }')
    send_response "$response"
}

# Success response
success_response() {
    local id="$1"
    local result="$2"
    local response
    response=$(jq -cn --argjson id "$id" --arg result "$result" '{
        jsonrpc: "2.0",
        id: $id,
        result: ($result | fromjson)
    }')
    send_response "$response"
}

# Add memory using add-note.sh
add_memory() {
    local content="$1"
    
    # Check if add-note.sh exists and is executable
    local add_script="$SCRIPT_DIR/add-note.sh"
    if [[ ! -x "$add_script" ]]; then
        jq -cn '{"error": "add-note.sh not found or not executable"}'
        return 1
    fi
    
    # Call add-note.sh and capture output
    local output
    local exit_code
    output=$("$add_script" "$content" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        jq -cn --arg output "$output" '{"success": true, "message": "Memory added successfully", "output": $output}'
    else
        jq -cn --arg output "$output" '{"error": "Failed to add memory", "details": $output}'
        return 1
    fi
}

# Search memories using search-notes.sh (includes full content for OpenAI compliance)
search_memories() {
    local query="$1"
    local limit="${2:-10}"
    
    # Load common functions to get COLLECTION_NAME and LLM_CMD
    if [[ ! -f "$SCRIPT_DIR/common.sh" ]]; then
        echo "Error: Cannot find common.sh at $SCRIPT_DIR/common.sh" >&2
        return 1
    fi
    source "$SCRIPT_DIR/common.sh"
    init_common
    
    # Call llm similar directly to get JSON results
    local search_results
    local exit_code
    search_results=$($LLM_CMD similar "$COLLECTION_NAME" -c "$query" -n "$limit" 2>/dev/null || echo "")
    exit_code=$?
    
    if [[ $exit_code -eq 0 && -n "$search_results" ]]; then
        # Parse JSONL results and return structured data with full content
        local results_array="[]"
        while IFS= read -r result_json; do
            [[ -z "$result_json" ]] && continue
            
            local note_id title date score content
            note_id=$(echo "$result_json" | jq -r '.id // "unknown"')
            title=$(echo "$result_json" | jq -r '.metadata.title // "Untitled"')
            date=$(echo "$result_json" | jq -r '.metadata.date // "Unknown date"')
            score=$(echo "$result_json" | jq -r '.score // "N/A"')
            content=$(echo "$result_json" | jq -r '.content // "No content"')
            
            # Clean content (remove Title: ... Content: prefix if present)
            local clean_content
            clean_content=$(echo "$content" | sed -n '/Content:/,$p' | sed '1d')
            if [[ -z "$clean_content" ]]; then
                clean_content="$content"
            fi
            
            # Add to results array
            results_array=$(echo "$results_array" | jq --arg id "$note_id" --arg title "$title" --arg date "$date" --arg score "$score" --arg content "$clean_content" '. += [{"id": $id, "title": $title, "date": $date, "score": $score, "content": $content}]')
        done <<< "$search_results"
        
        # Format response for both Claude (content) and ChatGPT (results) compatibility
        local content_text=$(echo "$results_array" | jq -r 'map("Title: \(.title)\nURL: \(.id)\nScore: \(.score)\n\(.content)\n\nTo get the full note details, use the fetch tool with the URL: \(.id)") | join("\n---\n")')
        # Transform results array to match ChatGPT schema (id, title, text, url) - use ID as URL for fetch
        local chatgpt_results=$(echo "$results_array" | jq 'map({id: .id, title: .title, text: .content, url: .id})')
        jq -cn --argjson results "$chatgpt_results" --arg text "$content_text" '{"content": [{"type": "text", "text": $text}], "results": $results}'
    else
        jq -cn --arg query "$query" '{"isError": true, "content": [{"type": "text", "text": ("Search failed or no results found for query: " + $query)}]}'
        return 1
    fi
}

# Fetch specific memory by URL (core data ID)
fetch_memory() {
    local note_url="$1"
    
    # Check if required tools are available
    if ! command -v notes-app &> /dev/null; then
        jq -cn --arg url "$note_url" '{"isError": true, "content": [{"type": "text", "text": "notes-app command not found"}]}'
        return 1
    fi
    
    # Use notes-app to fetch the note directly by core data ID
    local note_output
    note_output=$(notes-app show "$note_url" --properties all 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        # Note not found or error occurred
        jq -cn --arg url "$note_url" '{"isError": true, "content": [{"type": "text", "text": ("Note not found with URL: " + $url)}]}'
        return 1
    fi
    
    # Parse the notes-app output (format: id, folder, passwordProtected, creationDate, modificationDate, name, body)
    local lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done <<< "$note_output"
    
    local note_id="${lines[0]:-}"
    local creation_date="${lines[3]:-}"
    local modification_date="${lines[4]:-}"
    local title="${lines[5]:-Untitled}"
    local body="${lines[6]:-}"
    
    # Format response for both Claude (content) and ChatGPT (results) compatibility
    local content_text="Title: $title\nCreated: $creation_date\nModified: $modification_date\n\n$body"
    jq -cn --arg id "$note_id" --arg title "$title" --arg text "$body" --arg content_text "$content_text" --arg url "$note_url" '{"content": [{"type": "text", "text": $content_text}], "id": $id, "title": $title, "text": $text, "url": $url}'
}

# Initialize response
handle_initialize() {
    local id="$1"
    local response
    response=$(jq -cn '{
        protocolVersion: "2024-11-05",
        serverInfo: {
            name: "memories-mcp",
            version: "1.0.0"
        },
        capabilities: {
            tools: {}
        }
    }')
    success_response "$id" "$response"
}

# List available tools
handle_tools_list() {
    local id="$1"
    local tools
    tools=$(jq -cn '[
        {
            name: "add",
            description: "Add a new memory to Apple Notes with AI-generated tags and semantic indexing",
            inputSchema: {
                type: "object",
                properties: {
                    content: {
                        type: "string",
                        description: "The content of the memory to store. Can be single-line or multi-line text."
                    }
                },
                required: ["content"]
            },
            outputSchema: {
                type: "object",
                properties: {
                    content: {
                        type: "array",
                        items: {
                            type: "object",
                            properties: {
                                type: { type: "string", enum: ["text"] },
                                text: { type: "string" }
                            },
                            required: ["type", "text"]
                        }
                    }
                },
                required: ["content"]
            }
        },
        {
            name: "search",
            description: "Searches for memories using semantic similarity and returns matching results with full content",
            inputSchema: {
                type: "object",
                properties: {
                    query: {
                        type: "string",
                        description: "Search query to find related memories."
                    },
                    limit: {
                        type: "integer",
                        description: "Maximum number of results to return (default: 10)",
                        default: 10,
                        minimum: 1,
                        maximum: 50
                    }
                },
                required: ["query"]
            },
            outputSchema: {
                type: "object",
                properties: {
                    content: {
                        type: "array",
                        items: {
                            type: "object",
                            properties: {
                                type: { type: "string", enum: ["text"] },
                                text: { type: "string" }
                            },
                            required: ["type", "text"]
                        }
                    },
                    results: {
                        type: "array",
                        items: {
                            type: "object",
                            properties: {
                                id: { type: "string", description: "ID of the memory note." },
                                title: { type: "string", description: "Title of the memory note." },
                                text: { type: "string", description: "Full content of the memory note." },
                                url: { type: ["string", "null"], description: "URL reference (always null for local notes)." }
                            },
                            required: ["id", "title", "text"]
                        }
                    }
                },
                required: ["content", "results"]
            }
        },
        {
            name: "fetch",
            description: "Fetches a specific memory by URL and returns its full content. Use the exact URL from search results.",
            inputSchema: {
                type: "object",
                properties: {
                    url: {
                        type: "string",
                        description: "The core data URL of the memory to fetch (e.g., 'x-coredata://...')"
                    },
                    id: {
                        type: "string",
                        description: "Backward compatibility: The unique identifier of the memory to fetch"
                    }
                },
                required: ["url"]
            },
            outputSchema: {
                type: "object",
                properties: {
                    content: {
                        type: "array",
                        items: {
                            type: "object",
                            properties: {
                                type: { type: "string", enum: ["text"] },
                                text: { type: "string" }
                            },
                            required: ["type", "text"]
                        }
                    },
                    id: { type: "string", description: "ID of the memory note." },
                    title: { type: "string", description: "Title of the memory note." },
                    text: { type: "string", description: "Full content of the memory note." },
                    url: { type: ["string", "null"], description: "URL reference (always null for local notes)." }
                },
                required: ["content", "id", "title", "text"]
            }
        }
    ]')
    
    success_response "$id" "{ \"tools\": $tools }"
}

# Handle tool calls
handle_tools_call() {
    local id="$1"
    local tool_name="$2"
    local arguments="$3"
    
    case "$tool_name" in
        "add")
            local content
            content=$(echo "$arguments" | jq -r '.content // empty')
            
            if [[ -z "$content" ]]; then
                error_response "$id" -32602 "Missing required parameter: content"
                return
            fi
            
            local result
            result=$(add_memory "$content")
            local exit_code=$?
            
            if [[ $exit_code -eq 0 ]]; then
                # Parse success response
                local success_msg output_msg
                success_msg=$(echo "$result" | jq -r '.message // "Memory added"')
                output_msg=$(echo "$result" | jq -r '.output // ""')
                
                local content_text="✅ $success_msg"
                if [[ -n "$output_msg" ]]; then
                    content_text="$content_text\n\nDetails:\n$output_msg"
                fi
                
                local mcp_result
                mcp_result=$(jq -cn --arg text "$content_text" '{
                    content: [
                        {
                            type: "text",
                            text: $text
                        }
                    ]
                }')
                success_response "$id" "$mcp_result"
            else
                # Parse error response
                local error_msg details
                error_msg=$(echo "$result" | jq -r '.error // "Failed to add memory"')
                details=$(echo "$result" | jq -r '.details // ""')
                
                local full_error="$error_msg"
                if [[ -n "$details" ]]; then
                    full_error="$full_error: $details"
                fi
                
                error_response "$id" -32603 "$full_error"
            fi
            ;;
            
        "search")
            local query limit
            query=$(echo "$arguments" | jq -r '.query // empty')
            limit=$(echo "$arguments" | jq -r '.limit // 10')
            
            if [[ -z "$query" ]]; then
                error_response "$id" -32602 "Missing required parameter: query"
                return
            fi
            
            local result
            result=$(search_memories "$query" "$limit")
            local exit_code=$?
            
            if [[ $exit_code -eq 0 ]]; then
                # Use the dual-format response directly from search_memories
                success_response "$id" "$result"
            else
                # Since search_memories now returns MCP format errors, handle as MCP response
                success_response "$id" "$result"
            fi
            ;;
            
        "fetch")
            local fetch_url
            # Try both 'url' (ChatGPT standard) and 'id' (backward compatibility) parameters
            fetch_url=$(echo "$arguments" | jq -r '.url // .id // empty')
            
            if [[ -z "$fetch_url" ]]; then
                error_response "$id" -32602 "Missing required parameter: url or id"
                return
            fi
            
            local result
            result=$(fetch_memory "$fetch_url")
            local exit_code=$?
            
            # Always use success_response since fetch_memory returns MCP format
            success_response "$id" "$result"
            ;;
            
        *)
            error_response "$id" -32601 "Unknown tool: $tool_name"
            ;;
    esac
}

# Main request processing loop
main() {
    log "Memories MCP Server started from $SCRIPT_DIR"
    
    while IFS= read -r line; do
        log "Request: $line"
        
        # Parse JSON-RPC request
        local method id params
        method=$(echo "$line" | jq -r '.method // empty' 2>/dev/null || echo "")
        id=$(echo "$line" | jq '.id // null' 2>/dev/null || echo "null")
        params=$(echo "$line" | jq '.params // {}' 2>/dev/null || echo "{}")
        
        if [[ -z "$method" ]]; then
            error_response "$id" -32700 "Parse error"
            continue
        fi
        
        case "$method" in
            "initialize")
                handle_initialize "$id"
                ;;
            "tools/list")
                handle_tools_list "$id"
                ;;
            "tools/call")
                local tool_name arguments
                tool_name=$(echo "$params" | jq -r '.name // empty')
                arguments=$(echo "$params" | jq '.arguments // {}')
                handle_tools_call "$id" "$tool_name" "$arguments"
                ;;
            "resources/list")
                # Return empty resources list for OpenAI compatibility
                success_response "$id" '{"resources": []}'
                ;;
            "prompts/list")
                # Return empty prompts list for OpenAI compatibility  
                success_response "$id" '{"prompts": []}'
                ;;
            "notifications/initialized")
                # Ignore this notification
                ;;
            *)
                error_response "$id" -32601 "Method not found: $method"
                ;;
        esac
    done
}

# Run the server
main