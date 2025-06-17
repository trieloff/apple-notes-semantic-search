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

# Search memories using search-notes.sh
search_memories() {
    local query="$1"
    local limit="${2:-10}"
    
    # Check if search-notes.sh exists and is executable
    local search_script="$SCRIPT_DIR/search-notes.sh"
    if [[ ! -x "$search_script" ]]; then
        jq -cn '{"error": "search-notes.sh not found or not executable"}'
        return 1
    fi
    
    # Call search-notes.sh and capture output
    local output
    local exit_code
    output=$("$search_script" "$query" --limit "$limit" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        jq -cn --arg output "$output" '{"success": true, "results": $output}'
    else
        jq -cn --arg output "$output" '{"error": "Search failed", "details": $output}'
        return 1
    fi
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
            }
        },
        {
            name: "search",
            description: "Search through your memories using semantic similarity search",
            inputSchema: {
                type: "object",
                properties: {
                    query: {
                        type: "string",
                        description: "The search query. Uses semantic similarity to find related memories."
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
                # Parse success response
                local search_results
                search_results=$(echo "$result" | jq -r '.results // ""')
                
                local content_text="🔍 Search results for: $query\n\n$search_results"
                
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
                error_msg=$(echo "$result" | jq -r '.error // "Search failed"')
                details=$(echo "$result" | jq -r '.details // ""')
                
                local full_error="$error_msg"
                if [[ -n "$details" ]]; then
                    full_error="$full_error: $details"
                fi
                
                error_response "$id" -32603 "$full_error"
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