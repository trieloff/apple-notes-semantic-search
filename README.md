# Apple Notes Semantic Search

A collection of shell scripts that add semantic search capabilities to Apple Notes using embeddings and AI-powered tagging.

## Features

- 🔍 **Semantic Search**: Search your Apple Notes using natural language queries
- 🏷️ **AI-Powered Tagging**: Automatically generate relevant tags for your notes
- 📝 **Clean Formatting**: Simple, consistent note formatting without duplication
- ⚡ **Auto-Indexing**: New notes are automatically indexed and searchable
- 🔄 **Incremental Updates**: Efficient indexing with `--continue` flag

## Prerequisites

- macOS with Apple Notes
- [notes-app CLI](https://github.com/xwmx/notes-app-cli)
- [llm CLI](https://llm.datasette.io/)
- OpenAI API key (for embeddings and tagging)

## Installation

1. Install the required tools:
```bash
# Install notes-app CLI
brew install xwmx/taps/notes-app

# Install llm CLI
brew install llm
```

2. Configure LLM with your OpenAI API key:
```bash
llm keys set openai
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

## Usage

### 1. Add a Note with AI Tags

```bash
# Add a single-line note
./add-note.sh "Remember to buy milk and eggs"

# Add a multi-line note via stdin
echo -e "Meeting notes\n- Discuss Q4 goals\n- Review budget" | ./add-note.sh
```

The script will:
- Generate relevant tags using AI
- Create the note in your "Memories" folder
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

1. **add-note.sh**: Takes your input, uses LLM to generate relevant tags, and creates a formatted note in Apple Notes
2. **index-notes.sh**: Retrieves notes from the "Memories" folder and stores them with text-embedding-3-large embeddings
3. **search-notes.sh**: Performs semantic similarity search on your indexed notes and displays full content

## Note Format

Notes are created with a clean, minimal format:
- **Title**: First line of your input
- **Tags**: AI-generated hashtags (without "Tags:" prefix)
- **Body**: Additional content (for multi-line notes)

Example:
```
Title: Weekend plans
Tags: #personal #planning #social
Body: 
- Farmer's market
- Brunch with friends
- Work on hobby project
```

## Configuration

- **Folder**: Notes are stored in the "Memories" folder (create it in Apple Notes first)
- **Collection**: Embeddings are stored in the "notes-memory" collection
- **Model**: Uses OpenAI's text-embedding-3-large for embeddings

## Tips

- The incremental indexing feature stores timestamps in `~/.notes-indexer-config`
- Search is semantic - it finds related content even with different keywords
- Multi-line notes preserve formatting and line breaks
- Empty lines in multi-line notes are preserved

## License

MIT

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## Acknowledgments

Built using:
- [notes-app CLI](https://github.com/xwmx/notes-app-cli) by xwmx
- [LLM](https://llm.datasette.io/) by Simon Willison
- Claude Code by Anthropic