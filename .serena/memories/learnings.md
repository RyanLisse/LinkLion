# agent-browser Setup Learnings

## Installation Summary
- **Tool**: agent-browser v0.7.6
- **Installation method**: `npm install -g agent-browser`
- **Post-install step**: `agent-browser install` (downloads Chromium ~160MB)
- **Installation location**: `/Users/shelton/.npm-packages/bin/agent-browser`
- **Verification**: `agent-browser --version` returns version number

## Setup Script
- **Location**: `scripts/setup_agent_browser.sh`
- **Permissions**: Executable (755)
- **Features**:
  - Checks if already installed
  - Installs if missing
  - Runs `agent-browser install` for Chromium
  - Verifies with `--version`
  - Handles both fresh install and verification

## Key Notes
- No sudo required for global npm install
- Chromium download is essential (downloads via Playwright)
- Script tested successfully - handles already-installed case gracefully
- Playwright warning is informational, not blocking

## Verification Commands
```bash
which agent-browser
agent-browser --version
./scripts/setup_agent_browser.sh
```

All commands work successfully.
