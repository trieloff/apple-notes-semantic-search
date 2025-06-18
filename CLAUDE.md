## Git Guidelines
- never use git add -A always add each file one by one, so you don't accidentally commit a file that does not belong into git
- after running a git push, tell the user that you "pushed it good" or make some other corny reference to the salt-n-peppa song

## Shell Script Standards
- Always make shell scripts executable with chmod +x
- Use proper error handling with set -e
- Include usage instructions and help text
- Check for required commands before using them

## Apple Notes Integration
- Use notes-app CLI (not apple-notes) for interacting with Apple Notes
- The "Memories" folder is used for storing searchable notes
- notes-app automatically adds the title as the first line of the body
- Avoid duplicating content between title and body

## Testing Approach
- Test each script individually before integration
- Use simple test cases first, then complex multi-line inputs
- Always verify the actual output format before parsing
- Check both synchronous and background processes work correctly

## LLM/Embeddings Configuration
- Use text-embedding-3-large model for embeddings
- Collection name: notes-memory
- Always use --store flag with llm embed to store content
- llm similar returns JSONL format (one JSON object per line)

## MCP Server Testing
- Best approach: Use echo, pipe, timeout, and jq for testing MCP commands
- Example: `{ echo '{"jsonrpc":"2.0","id":0,"method":"initialize"...}'; echo '{"jsonrpc":"2.0","id":1,"method":"tools/call"...}'; } | timeout 10 ./memories-mcp.sh | jq`
- Avoid HTTP endpoints - they require persistent SSE sessions which are harder to maintain
- Using the bash script directly doesn't require server restarts between tests
- For production restarts, use the mcpctl command (not pkill or manual restarts)