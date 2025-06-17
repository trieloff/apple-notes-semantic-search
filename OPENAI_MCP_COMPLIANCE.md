# OpenAI ChatGPT Deep Research MCP Server Compliance Guide

This document outlines the specific requirements and changes needed to make an MCP (Model Context Protocol) server compatible with OpenAI's ChatGPT Deep Research feature.

## Background

OpenAI's ChatGPT Deep Research has specific requirements for MCP servers that go beyond the standard MCP specification. These requirements were discovered through trial and error, community forum discussions, and testing with the actual ChatGPT service.

## Key Requirements

### 1. Schema Format

**Critical**: Use camelCase for schema properties, not snake_case:

```json
{
  "name": "search",
  "inputSchema": {  // ✅ Correct - camelCase
    "type": "object",
    // ...
  },
  "outputSchema": {  // ✅ Correct - camelCase
    "type": "object",
    // ...
  }
}
```

**Not** this:
```json
{
  "input_schema": {},  // ❌ Wrong - snake_case
  "output_schema": {}  // ❌ Wrong - snake_case
}
```

### 2. Required Tools

OpenAI expects specific tool names and formats:

- **`search`** - Primary search functionality
- **`fetch`** - Retrieve specific items by ID (optional but recommended)

### 3. Output Schema Format

Search results must follow this exact structure:

```json
{
  "results": [
    {
      "id": "string",      // Required - unique identifier
      "title": "string",   // Required - display title
      "text": "string",    // Required - content/summary
      "url": "string|null" // Optional but needed for citations
    }
  ]
}
```

### 4. Additional MCP Methods

For full compatibility, implement these optional methods:

```json
// Return empty arrays for compatibility
"resources/list" → {"resources": []}
"prompts/list" → {"prompts": []}
```

### 5. Protocol Version

OpenAI uses protocol version `"2025-03-26"` but servers can respond with earlier versions like `"2024-11-05"`.

## Implementation Steps

### Step 1: Update Tool Definitions

```bash
# Change in handle_tools_list() function
tools=$(jq -cn '[
  {
    name: "search",
    description: "Searches for resources using semantic similarity",
    inputSchema: {  # camelCase!
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Search query to find related content."
        }
      },
      required: ["query"]
    },
    outputSchema: {  # camelCase!
      type: "object",
      properties: {
        results: {
          type: "array",
          items: {
            type: "object",
            properties: {
              id: { type: "string" },
              title: { type: "string" },
              text: { type: "string" },
              url: { type: ["string", "null"] }
            },
            required: ["id", "title", "text"]
          }
        }
      },
      required: ["results"]
    }
  }
]')
```

### Step 2: Transform Response Format

```bash
# In tool handlers, transform your data to match OpenAI format
transformed_results=$(echo "$search_results" | jq 'map({
  id: .id,
  title: .title,
  text: .content,  # Map your content field to "text"
  url: null        # Set to null for local content
})')

mcp_result=$(jq -cn --argjson results "$transformed_results" '{
  results: $results
}')
```

### Step 3: Add Compatibility Methods

```bash
case "$method" in
  # ... existing methods ...
  "resources/list")
    success_response "$id" '{"resources": []}'
    ;;
  "prompts/list")
    success_response "$id" '{"prompts": []}'
    ;;
esac
```

## Testing and Validation

### 1. Use mcp-inspector

```bash
npx @modelcontextprotocol/inspector your-server-command
```

Look for validation errors related to `inputSchema` vs `input_schema`.

### 2. Monitor Connection Logs

OpenAI will test these methods in sequence:
1. `initialize`
2. `tools/list`
3. `resources/list`
4. `prompts/list`

### 3. Client Identification

OpenAI connects with:
```json
{
  "clientInfo": {
    "name": "openai-mcp",
    "version": "1.0.0"
  }
}
```

## Common Issues and Solutions

### Issue: "inputSchema is required"
**Solution**: Change `input_schema` to `inputSchema` (camelCase)

### Issue: "Method not found: resources/list"
**Solution**: Add handler returning `{"resources": []}`

### Issue: Search returns wrong format
**Solution**: Ensure results array contains objects with `id`, `title`, `text`, `url` fields

### Issue: Tools not showing in ChatGPT
**Solution**: Verify `outputSchema` is properly defined for all tools

## Resources

- [OpenAI Community Discussion](https://community.openai.com/t/this-mcp-server-violates-our-guidelines/1279211)
- [MCP Server Setup Guide](https://community.openai.com/t/how-to-set-up-a-remote-mcp-server-and-connect-it-to-chatgpt-deep-research/1278375)
- [MCP Specification](https://spec.modelcontextprotocol.io/)

## Cross-Client Compatibility: ChatGPT vs Claude

A key challenge when building MCP servers is achieving compatibility across different AI clients that have varying expectations for response formats.

### The Problem

Different MCP clients expect different response formats:

- **ChatGPT Deep Research**: Expects `results` array with structured objects (`id`, `title`, `text`, `url`)
- **Claude**: Expects `content` array with text objects for LLM consumption (`type: "text"`, `text: "...")

### The Solution: Dual Format Response

To achieve maximum compatibility, return both formats in your tool responses:

```json
{
  "content": [
    {
      "type": "text", 
      "text": "Title: Example\nURL: x-coredata://...\n\nContent here..."
    }
  ],
  "results": [
    {
      "id": "x-coredata://...",
      "title": "Example",
      "text": "Content here...",
      "url": "x-coredata://..."
    }
  ]
}
```

### Implementation Notes

1. **Search Tool**: Return both `content` (for Claude) and `results` (for ChatGPT)
2. **Fetch Tool**: Return both formats for consistency
3. **URL Field**: Use core data IDs as URLs since they're already URL-like (`x-coredata://...`)
4. **Content Text**: Include URLs in the text so Claude knows what to pass to fetch

### Benefits

- **Universal compatibility**: Works with both ChatGPT and Claude
- **Standards compliance**: Follows both MCP spec and ChatGPT requirements
- **Future-proof**: Ready for other MCP clients with different expectations

This dual-format approach ensures your MCP server works seamlessly across all major AI platforms without requiring client-specific code branches.

## Success Indicators

When your server is compliant, you'll see in logs:
```
[supergateway] SSE → Child: {"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"openai-mcp","version":"1.0.0"}}}
[supergateway] Child → SSE: {"jsonrpc":"2.0","id":1,"result":{"tools":[...]}}
```

And ChatGPT will successfully list and use your tools in Deep Research mode.