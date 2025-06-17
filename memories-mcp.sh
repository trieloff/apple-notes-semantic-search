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
    response=$(jq -cn --argjson id "$id" --argjson result "$result" '{
        jsonrpc: "2.0",
        id: $id,
        result: $result
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
    source "$SCRIPT_DIR/common.sh"
    
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
        
        jq -cn --argjson results "$results_array" '{"success": true, "results": $results}'
    else
        jq -cn --arg query "$query" '{"error": "Search failed or no results found", "query": $query}'
        return 1
    fi
}

# Fetch specific memory by ID
fetch_memory() {
    local note_id="$1"
    
    # Load common functions to get COLLECTION_NAME and LLM_CMD
    source "$SCRIPT_DIR/common.sh"
    
    # Call llm similar to find the specific note by ID
    local search_results
    search_results=$($LLM_CMD similar "$COLLECTION_NAME" -c "$note_id" -n 50 2>/dev/null || echo "")
    
    if [[ -z "$search_results" ]]; then
        jq -cn --arg id "$note_id" '{"error": "Note not found", "id": $id}'
        return 1
    fi
    
    # Find exact ID match
    local found_note=""
    while IFS= read -r result_json; do
        [[ -z "$result_json" ]] && continue
        
        local current_id
        current_id=$(echo "$result_json" | jq -r '.id // ""')
        
        if [[ "$current_id" == "$note_id" ]]; then
            found_note="$result_json"
            break
        fi
    done <<< "$search_results"
    
    if [[ -z "$found_note" ]]; then
        jq -cn --arg id "$note_id" '{"error": "Note not found", "id": $id}'
        return 1
    fi
    
    # Extract full note details
    local content title date score
    content=$(echo "$found_note" | jq -r '.content // "No content"')
    title=$(echo "$found_note" | jq -r '.metadata.title // "Untitled"')
    date=$(echo "$found_note" | jq -r '.metadata.date // "Unknown date"')
    score=$(echo "$found_note" | jq -r '.score // "N/A"')
    
    # Clean content (remove Title: ... Content: prefix if present)
    local clean_content
    clean_content=$(echo "$content" | sed -n '/Content:/,$p' | sed '1d')
    if [[ -z "$clean_content" ]]; then
        clean_content="$content"
    fi
    
    jq -cn --arg id "$note_id" --arg title "$title" --arg date "$date" --arg content "$clean_content" --arg score "$score" '{
        "success": true,
        "note": {
            "id": $id,
            "title": $title,
            "date": $date,
            "content": $content,
            "score": $score
        }
    }'
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
                required: ["results"]
            }
        },
        {
            name: "fetch",
            description: "Fetches a specific memory by ID and returns its full content",
            inputSchema: {
                type: "object",
                properties: {
                    id: {
                        type: "string",
                        description: "The unique identifier of the memory to fetch"
                    }
                },
                required: ["id"]
            },
            outputSchema: {
                type: "object",
                properties: {
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
                required: ["results"]
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
                # Parse success response and transform to required format
                local search_results
                search_results=$(echo "$result" | jq -r '.results')
                
                # Transform results to match OpenAI schema (id, title, text, url)
                local transformed_results
                transformed_results=$(echo "$search_results" | jq 'map({
                    id: .id,
                    title: .title,
                    text: .content,
                    url: null
                })')
                
                local mcp_result
                mcp_result=$(jq -cn --argjson results "$transformed_results" '{
                    results: $results
                }')
                success_response "$id" "$mcp_result"
            else
                # Parse error response
                local error_msg
                error_msg=$(echo "$result" | jq -r '.error // "Search failed"')
                error_response "$id" -32603 "$error_msg"
            fi
            ;;
            
        "fetch")
            local fetch_id
            fetch_id=$(echo "$arguments" | jq -r '.id // empty')
            
            if [[ -z "$fetch_id" ]]; then
                error_response "$id" -32602 "Missing required parameter: id"
                return
            fi
            
            local result
            result=$(fetch_memory "$fetch_id")
            local exit_code=$?
            
            if [[ $exit_code -eq 0 ]]; then
                # Parse success response and transform to required format
                local note_data
                note_data=$(echo "$result" | jq -r '.note')
                
                # Transform to match OpenAI schema (return as single-item array)
                local transformed_result
                transformed_result=$(echo "$note_data" | jq '{
                    id: .id,
                    title: .title, 
                    text: .content,
                    url: null
                }')
                
                local mcp_result
                mcp_result=$(jq -cn --argjson result "$transformed_result" '{
                    results: [$result]
                }')
                success_response "$id" "$mcp_result"
            else
                # Parse error response
                local error_msg
                error_msg=$(echo "$result" | jq -r '.error // "Fetch failed"')
                error_response "$id" -32603 "$error_msg"
            fi
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