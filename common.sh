#!/bin/bash

# Common functionality for Apple Notes semantic search scripts

# Default configuration
CONFIG_DIR="$HOME/.config/notes"
CONFIG_FILE="$CONFIG_DIR/config"
COLLECTION_NAME="notes-memory"
FOLDER_NAME="Memories"
DEFAULT_TAGGING_MODEL=""
DEFAULT_EMBEDDING_MODEL="text-embedding-3-large"

# Function to read config file
read_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Function to set up LLM command with fallback
setup_llm_command() {
    LLM_CMD=""
    if command -v llm &> /dev/null; then
        LLM_CMD="llm"
    elif command -v uv &> /dev/null && uv tool run llm --version &> /dev/null; then
        LLM_CMD="uv tool run llm"
    else
        echo "Error: llm command not found. Please install it or ensure uv tool is available."
        exit 1
    fi
}

# Function to check required tools
check_required_tools() {
    if ! command -v notes-app &> /dev/null; then
        echo "Error: notes-app command not found. Please install it first."
        exit 1
    fi

    # jq is used for JSON parsing across several scripts
    if ! command -v jq &> /dev/null; then
        echo "Error: jq command not found. Please install it first."
        exit 1
    fi
}

# Function to set up API keys from config
setup_api_keys() {
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        export OPENAI_API_KEY
    fi
    
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        export ANTHROPIC_API_KEY
    fi
    
    # Add support for other API keys as needed
    if [[ -n "${GEMINI_API_KEY:-}" ]]; then
        export GEMINI_API_KEY
    fi
}

# Function to get tagging model
get_tagging_model() {
    echo "${TAGGING_MODEL:-$DEFAULT_TAGGING_MODEL}"
}

# Function to get embedding model
get_embedding_model() {
    echo "${EMBEDDING_MODEL:-$DEFAULT_EMBEDDING_MODEL}"
}

# Initialize common setup
init_common() {
    # Read config file
    read_config
    
    # Set up API keys
    setup_api_keys
    
    # Set up LLM command
    setup_llm_command
    
    # Check required tools
    check_required_tools
}

# Export variables that scripts might need
export CONFIG_DIR CONFIG_FILE COLLECTION_NAME FOLDER_NAME