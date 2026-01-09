# 🤖 LinkLion MCP Integration

This document describes how to use LinkLion as an MCP (Model Context Protocol) server for AI assistants like Claude Desktop.

## Overview

The MCP server exposes all LinkLion functionality as tools that AI assistants can call directly, enabling natural language LinkedIn research and data extraction.

## Configuration

### Claude Desktop Setup

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "linklion": {
      "command": "/usr/local/bin/linklion-mcp",
      "args": [],
      "disabled": false
    }
  }
}
```

**Or with full path:**

```json
{
  "mcpServers": {
    "linklion": {
      "command": "/Volumes/Main SSD/Developer/LinkLion/.build/release/linklion-mcp",
      "args": [],
      "disabled": false
    }
  }
}
```

### Restart Claude Desktop

After updating the config, restart Claude Desktop to load the MCP server.

---

## Available Tools

### `linklion_status`

Check the current authentication status.

**Input:** `{}`

**Output:**
```json
{
  "success": true,
  "authenticated": true,
  "username": "johndoe"
}
```

**Example Prompt:**
> "Is LinkLion authenticated?"

---

### `linklion_configure`

Configure the LinkedIn authentication cookie.

**Input:**
```json
{
  "cookie": "AQEDAQ...",
  "username": "johndoe"  // optional
}
```

**Output:**
```json
{
  "success": true,
  "message": "Authentication configured successfully"
}
```

**Example Prompt:**
> "Configure LinkLion with my li_at cookie"

---

### `linklion_get_profile`

Fetch a person's LinkedIn profile.

**Input:**
```json
{
  "identifier": "satya-nadella",
  "source": "username"  // or "url"
}
```

**Output:**
```json
{
  "success": true,
  "profile": {
    "name": "Satya Nadella",
    "headline": "Chairman and Chief Executive Officer at Microsoft",
    "location": "United States",
    "about": "...",
    "experience": [
      {
        "title": "Chairman and Chief Executive Officer",
        "company": "Microsoft",
        "duration": "Feb 2014 - Present",
        "description": "..."
      }
    ],
    "education": [
      {
        "school": "University of Wisconsin–Milwaukee",
        "degree": "M.S. in Computer Science"
      }
    ],
    "skills": ["Leadership", "Cloud Computing", "Enterprise Software"],
    "connections": "500+"
  }
}
```

**Example Prompts:**
> "Get the LinkedIn profile for Satya Nadella"
> "Show me Elon Musk's profile"

---

### `linklion_get_company`

Fetch a company's LinkedIn profile.

**Input:**
```json
{
  "identifier": "microsoft",
  "source": "name"  // or "url"
}
```

**Output:**
```json
{
  "success": true,
  "company": {
    "name": "Microsoft",
    "industry": "Software Development",
    "size": "10001+ employees",
    "website": "https://www.microsoft.com",
    "description": "...",
    "specialities": [
      "Cloud Computing",
      "AI",
      "Productivity Software"
    ]
  }
}
```

**Example Prompts:**
> "What does Anthropic do according to LinkedIn?"
> "Get information about the Tesla company"

---

### `linklion_search_jobs`

Search for jobs on LinkedIn.

**Input:**
```json
{
  "query": "iOS Developer",
  "location": "San Francisco",
  "limit": 10
}
```

**Output:**
```json
{
  "success": true,
  "jobs": [
    {
      "id": "1234567890",
      "title": "Senior iOS Engineer",
      "company": "TechCorp Inc.",
      "location": "San Francisco, CA",
      "postedDate": "2024-01-15"
    }
  ]
}
```

**Example Prompts:**
> "Search for Swift Developer jobs in Remote"
> "Find Machine Learning Engineer positions in New York"

---

### `linklion_get_job`

Get detailed information about a specific job.

**Input:**
```json
{
  "identifier": "1234567890",
  "source": "id"  // or "url"
}
```

**Output:**
```json
{
  "success": true,
  "job": {
    "id": "1234567890",
    "title": "Senior iOS Engineer",
    "company": "TechCorp Inc.",
    "location": "San Francisco, CA",
    "type": "Full-time",
    "level": "Senior",
    "description": "We are looking for...",
    "requirements": [
      "5+ years iOS development",
      "Swift mastery",
      "Experience with CI/CD"
    ],
    "benefits": ["Health insurance", "401k", "Remote work"]
  }
}
```

**Example Prompts:**
> "Get details for job 1234567890"
> "What are the requirements for this iOS position?"

---

## Complete Example Session

```
User: "Research Microsoft leadership team on LinkedIn"

Claude → linklion_get_company:
  { "identifier": "microsoft", "source": "name" }

→ Returns company info

User: "Who is the CEO and what's their background?"

Claude → linklion_get_profile:
  { "identifier": "satya-nadella", "source": "username" }

→ Returns Satya's profile with experience and education
```

---

## Error Handling

The MCP server returns structured errors:

```json
{
  "success": false,
  "error": "not_authenticated",
  "message": "Please configure authentication first. Run: linklion auth YOUR_COOKIE"
}
```

### Common Errors

| Error Code | Message | Solution |
|------------|---------|----------|
| `not_authenticated` | Authentication required | Run `linklion auth` or use `linklion_configure` |
| `profile_not_found` | Profile not found | Check the username/URL |
| `company_not_found` | Company not found | Verify company name/URL |
| `job_not_found` | Job not found | Check the job ID/URL |
| `rate_limited` | Too many requests | Wait before trying again |
| `invalid_cookie` | Invalid cookie | Update with fresh `li_at` cookie |

---

## Security Notes

- The `li_at` cookie provides full access to your LinkedIn account
- Store it securely in macOS Keychain (handled automatically)
- Never share your `li_at` cookie with others
- The cookie expires periodically (typically ~1 year)

---

## Troubleshooting

### Server Won't Start

1. Check the executable path is correct
2. Ensure executable permissions: `chmod +x /usr/local/bin/linklion-mcp`
3. Verify Swift runtime is installed

### Authentication Failures

1. Get a fresh `li_at` cookie from your browser
2. Ensure cookie hasn't expired
3. Try reconfiguring: `linklion auth --clear && linklion auth NEW_COOKIE`

### Rate Limiting

LinkedIn may block frequent requests. Wait a few minutes before retrying.

### Missing Data

If profiles/jobs return incomplete data, LinkedIn may have updated their HTML structure. Report issues on GitHub.
