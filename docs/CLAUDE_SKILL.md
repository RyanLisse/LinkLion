# LinkLion Claude Code Skill

This document provides a skill definition for integrating LinkLion with Claude Code's PAI (Personal AI Infrastructure) system.

## Skill Installation

To use LinkLion as a Claude Code skill, create this file:

**Location:** `~/.claude/skills/LinkLion/SKILL.md`

**Content:** See full skill definition below.

## Skill Definition

```markdown
---
name: LinkLion
description: LinkedIn scraping CLI with browser-based authentication. USE WHEN user wants to scrape LinkedIn profiles, companies, jobs, or needs LinkedIn data extraction. Supports automatic cookie extraction from Safari/Chrome/Edge/Firefox.
---

# LinkLion - LinkedIn Scraping CLI

LinkedIn data extraction with automatic browser authentication and vision-based scraping fallback.

## When to Use This Skill

Use LinkLion when the user needs to:
- Get LinkedIn profile information (experience, education, skills)
- Extract company data (industry, size, specialties)
- Search for jobs with location filtering
- Scrape LinkedIn data for research or analysis
- Authenticate with LinkedIn via automatic browser cookie extraction

## Available Commands

### Authentication
\`\`\`bash
# Automatic browser extraction (easiest)
linkedin auth --browser safari
linkedin auth --browser chrome
linkedin auth --list-browsers

# Manual authentication
linkedin auth YOUR_LI_AT_COOKIE

# Check status
linkedin status
\`\`\`

### Profile Scraping
\`\`\`bash
linkedin profile johndoe
linkedin profile "https://linkedin.com/in/johndoe"
linkedin profile username --json
linkedin profile username --vision
\`\`\`

### Company Intelligence
\`\`\`bash
linkedin company microsoft
linkedin company "https://linkedin.com/company/openai"
\`\`\`

### Job Search
\`\`\`bash
linkedin jobs "Swift Developer" --location "Remote" --limit 25
linkedin job 1234567890 --json
\`\`\`

## Authentication Flow

1. **Automatic extraction** (recommended):
   - Safari: May prompt for Full Disk Access
   - Chrome/Edge: May prompt for Keychain access
   - Firefox: No additional permissions

2. **Manual extraction** (fallback):
   - DevTools → Application → Cookies → linkedin.com
   - Copy `li_at` cookie value

## Examples

\`\`\`bash
# Authenticate once
linkedin auth --browser safari

# Get profile
linkedin profile satyanadella

# Search jobs
linkedin jobs "Swift Developer" --location "Remote"

# Get company info
linkedin company anthropic --json
\`\`\`
```

## Usage with Claude

Once installed, you can ask Claude to:

- "Use LinkLion to get Satya Nadella's LinkedIn profile"
- "Search for Swift Developer jobs in Remote locations using LinkLion"
- "Extract Anthropic's company information from LinkedIn"
- "Authenticate LinkLion with Safari browser cookies"

Claude will automatically:
1. Detect the request involves LinkedIn data
2. Invoke the LinkLion skill
3. Run the appropriate CLI commands
4. Parse and present the results

## Automatic Browser Authentication

LinkLion uses SweetCookieKit to automatically extract LinkedIn cookies from:

- **Safari** - May prompt for Full Disk Access (one-time)
- **Chrome/Edge** - May prompt for Keychain access (one-time)
- **Firefox** - No additional permissions needed

First-time setup:
```bash
linkedin auth --browser safari
```

Subsequent uses work automatically with stored credentials.

## Vision-Based Scraping

When HTML parsing fails (anti-bot detection), LinkLion automatically falls back to:

1. **Peekaboo** - Browser automation via agent-browser
2. **Gemini Vision** - Screenshot analysis for data extraction

Force vision mode:
```bash
linkedin profile username --vision
linkedin inbox --browser-mode
```

## Installation

```bash
cd ~/Tools/LinkLion
swift build -c release
cp .build/release/linkedin /usr/local/bin/
cp .build/release/linkedin-mcp /usr/local/bin/
```

## MCP Server Integration

LinkLion also provides an MCP server for Claude Desktop:

**Config:** `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "linklion": {
      "command": "/usr/local/bin/linkedin-mcp",
      "args": [],
      "disabled": false
    }
  }
}
```

## Architecture

- **LinkedInClient** - Main API client with cookie auth
- **PeekabooClient** - Browser automation fallback
- **GeminiVision** - Vision-based parsing
- **BrowserCookieExtractor** - SweetCookieKit integration
- **CredentialStore** - Keychain storage

## Error Handling

**Authentication:**
- "Not authenticated" → `linkedin auth --browser safari`
- "Permission denied" → Grant system permissions
- "No cookie found" → Log into LinkedIn first

**Scraping:**
- HTML fails → Auto-fallback to vision
- Rate limiting → Built-in delays
- Anti-bot → Use `--vision` flag

## Related

- Repository: https://github.com/RyanLisse/LinkLion
- License: MIT
- Swift: 6.0+
- Platform: macOS 14+
