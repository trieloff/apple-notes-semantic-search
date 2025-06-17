# Apple Notes Semantic Search

[![40% Vibe Coded](https://img.shields.io/badge/40%25-Vibe_Coded-ff69b4?style=for-the-badge&logo=headphones&logoColor=white)](https://github.com/trieloff/apple-notes-semantic-search)

A collection of shell scripts that add semantic search capabilities to Apple Notes using local AI models and embeddings for privacy-focused note management.

## Features

- 🔍 **Semantic Search**: Search your Apple Notes using natural language queries
- 🏷️ **AI-Powered Tagging**: Automatically generate relevant tags using local MLX models
- 📝 **Clean Formatting**: Simple, consistent note formatting with full content preservation
- ⚡ **Auto-Indexing**: New notes are automatically indexed and searchable
- 🔄 **Incremental Updates**: Efficient indexing with `--continue` flag
- 🔒 **Privacy-First**: Local inference with MLX models - no API calls required
- 🚀 **Apple Silicon Optimized**: Leverages MLX framework for fast local AI
- 🖧 **MCP Server**: Expose add/search via JSON-RPC for MCP clients

## Prerequisites

- macOS with Apple Notes
- [notes-app CLI](https://github.com/xwmx/notes-app-cli)
- [llm CLI](https://llm.datasette.io/) with plugins
- [jq](https://stedolan.github.io/jq/) for JSON parsing
- Python environment (for local models)

### Special Thanks

This project wouldn't exist without these amazing tools:
- **[notes-app CLI](https://github.com/xwmx/notes-app-cli)** by [xwmx](https://github.com/xwmx) - A fantastic command-line interface for Apple Notes that makes programmatic access possible
- **[LLM](https://llm.datasette.io/)** by [Simon Willison](https://github.com/simonw) - An incredible CLI tool for working with large language models and embeddings
- **[MLX](https://github.com/ml-explore/mlx)** by Apple - Machine learning framework optimized for Apple Silicon

## Installation

1. Install the required tools:
```bash
# Install notes-app CLI
brew install xwmx/taps/notes-app

# Install jq for JSON handling
brew install jq

# Install llm CLI (via uv for isolation)
uv tool install llm

# Install sentence transformers plugin for local embeddings
uv tool run llm install llm-sentence-transformers

# Install MLX plugin for local language models
uv tool run llm install llm-mlx
```

2. Download local models:
```bash
# Download MLX Phi model for tagging (replace with your preferred model)
uv tool run llm mlx download-model mlx-community/Phi-3.5-mini-instruct-4bit

# The sentence transformer model will be downloaded automatically on first use
```

3. Clone this repository:
```bash
git clone https://github.com/trieloff/apple-notes-semantic-search.git
cd apple-notes-semantic-search
```

4. Make scripts executable:
```bash
chmod +x *.sh
```

5. Configure your models (optional):
```bash
# Copy example config and customize
cp config.example ~/.config/notes/config
# Edit ~/.config/notes/config to set your preferred models
```

## Configuration

Create `~/.config/notes/config` to customize models:

```bash
# Tagging model - using MLX Phi-3.5-mini for local inference
TAGGING_MODEL="mlx-community/Phi-3.5-mini-instruct-4bit"

# Embedding model - local sentence transformers (384 dimensions)
EMBEDDING_MODEL="sentence-transformers/all-MiniLM-L6-v2"

# Collection and Folder Names (optional)
COLLECTION_NAME="notes-memory"
FOLDER_NAME="Memories"
```

**Note**: If you prefer to use OpenAI models instead of local ones, you can set:
- `TAGGING_MODEL=""` (uses default LLM model)
- `EMBEDDING_MODEL="text-embedding-3-large"`
- Add your API key: `OPENAI_API_KEY="your-key"`

## Usage

### 1. Add a Note with AI Tags

```bash
# Add a single-line note
./add-note.sh "Remember to buy milk and eggs"

# Add a multi-line note via stdin
echo -e "Meeting notes\n- Discuss Q4 goals\n- Review budget" | ./add-note.sh
```

The script will:
- Generate relevant tags using local AI (Phi-3.5-mini)
- Extract only clean hashtags (regex filtered)
- Create the note in your "Memories" folder with full content preservation
- Automatically index it for searching

### 2. Index Your Notes

```bash
# Full index of all notes in Memories folder
./index-notes.sh

# Incremental index (only new/changed notes)
./index-notes.sh --continue
```

### 3. Search Your Notes

```bash
# Basic search
./search-notes.sh "coffee shop"

# Limit results
./search-notes.sh "vacation plans" --limit 3
```

## How It Works

1. **add-note.sh**: Takes your input, uses local MLX model to generate clean hashtags, and creates a formatted note in Apple Notes with full content preservation
2. **index-notes.sh**: Retrieves notes from the "Memories" folder and stores them with local sentence transformer embeddings (384-dimensional vectors)
3. **search-notes.sh**: Performs semantic similarity search on your indexed notes using local embeddings and displays full content
4. **common.sh**: Shared functionality including model configuration, LLM command detection (with `uv tool run llm` fallback), and API key management

## Note Format

Notes are created with a clean, minimal format:
- **Title**: First 50 characters of your input (with "..." if truncated)
- **Tags**: AI-generated clean hashtags (regex extracted: `#[a-zA-Z0-9_-]+`)
- **Body**: Full original content preserved

Example:
```
Title: Weekend plans for the family
Tags: #personal #planning #family #weekend
Body: 
Weekend plans for the family
- Farmer's market
- Brunch with friends  
- Work on hobby project
```

## Architecture

- **Local Models**: Phi-3.5-mini (tagging) + all-MiniLM-L6-v2 (embeddings)
- **Privacy**: All AI processing happens locally on your machine
- **Storage**: Apple Notes for human-readable notes, local SQLite for embeddings
- **Search**: Semantic similarity using cosine distance on 384-dimensional vectors
- **Platform**: Optimized for Apple Silicon using MLX framework

## Tips

- The incremental indexing feature stores timestamps in `~/.notes-indexer-config`
- Search is semantic - it finds related content even with different keywords
- Single-line and multi-line notes both preserve full content
- Local models provide privacy and work offline
- MLX models are optimized for Apple Silicon performance
- The system supports both local and cloud models via configuration
## MCP Server Setup

This repository also includes `memories-mcp.sh`, a JSON-RPC server implementing the [MCP protocol](https://github.com/mcp-protocol/spec). It exposes `add` and `search` tools so editors can interact with your notes. Start the server from the repo directory:
```bash
./memories-mcp.sh
```
Logs are written to `/tmp/memories-mcp-requests.log`.

### Client Setup
- **Claude Desktop**: Add a custom MCP server and point it to the `memories-mcp.sh` script.
- **Claude Code**: Use the MCP settings to register `./memories-mcp.sh` as a server.
- **Zed**: In Preferences → AI, enable a custom MCP server and specify the script path.
- **Cursor**: Configure the MCP command to run `memories-mcp.sh`.
- **GitHub Co-Pilot**: Enable the experimental MCP endpoint and set it to `./memories-mcp.sh`.


## Troubleshooting

**Models not found**: Make sure you've downloaded the MLX model and installed the sentence transformers plugin.

**Command not found**: The scripts use `uv tool run llm` as a fallback if `llm` isn't in your PATH.

**Indexing issues**: Delete `~/.notes-indexer-config` to force a full reindex.

**Empty search results**: Run `./index-notes.sh` to ensure your notes are indexed.

## License

MIT

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## Acknowledgments

Built using:
- [notes-app CLI](https://github.com/xwmx/notes-app-cli) by xwmx
- [LLM](https://llm.datasette.io/) by Simon Willison
- [MLX](https://github.com/ml-explore/mlx) by Apple
- [sentence-transformers](https://github.com/UKPLab/sentence-transformers) by UKP Lab
- Claude Code by Anthropic