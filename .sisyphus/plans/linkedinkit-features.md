# LinkedInKit Feature Expansion & Browser Comparison Plan

## Context

### Original Request
- Check `docs/api_reference.md`
- Add missing features to MCP and CLI (Messaging, Invitations)
- Test `agent-browser` vs `peekaboo`

### Interview Summary
**Key Discussions**:
- **Scope**: Implement both Messaging and Connection Invites.
- **Architecture**: Create `AgentBrowserClient.swift` (wrapper) and `linklion compare-browsers` command.
- **Setup**: Include installation steps for `agent-browser`.

**Metis/Self Review Findings**:
- **Safety**: Messaging/Invites need safety prompts to prevent accidental spam.
- **Usability**: CLI should accept Profile URLs and resolve to URNs automatically.
- **Constraint**: "Compare" command limited to Profile Scraping for simplicity.

---

## Work Objectives

### Core Objective
Implement Messaging and Invitation features in CLI/MCP, and add a comparative testing suite for browser automation tools.

### Concrete Deliverables
- `Sources/LinkLion/AgentBrowserClient.swift`: Wrapper for `agent-browser`
- `Sources/LinkLion/LinkedInClient.swift`: Updated with `sendMessage`, `sendInvite`, and browser switching
- `Sources/LinkedInCLI`: New commands `Message`, `Connect`, `Compare`
- `Sources/LinkedInMCP`: New tools `linkedin_send_message`, `linkedin_send_invite`
- `Tests/LinkedInKitTests`: Unit tests for new logic

### Definition of Done
- [ ] `linklion connect <url>` sends an invite (verified manual)
- [ ] `linklion message <url> <text>` sends a message (verified manual)
- [ ] `linklion compare-browsers <url>` runs both tools and outputs stats
- [ ] `agent-browser` installation documented/scripted

### Must Have
- Safety prompts for write actions (Connect/Message)
- Automatic URL -> URN resolution
- JSON output for MCP tools

### Must NOT Have
- Mass messaging/spam features (single target only)
- Complex benchmarking (keep comparison simple)

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES (XCTest)
- **Framework**: XCTest
- **Strategy**: 
    - **TDD** for URL construction, parsing logic, and URN extraction.
    - **Manual** for actual API calls (network) and CLI interactions.

### TDD Workflow
1. Write failing test in `Tests/LinkedInKitTests/LinkedInClientTests.swift` for new request builders.
2. Implement methods in `LinkedInClient.swift`.
3. Verify pass.

### Manual Verification
- **API**: Run `linklion connect` against a test account (or self).
- **CLI**: Run `linklion compare-browsers` and check stdout.
- **MCP**: Use Inspector or Claude to call `linkedin_send_message`.

---

## Task Flow

```
1. Install/Setup agent-browser
2. TDD & Implement API Features (Client)
3. Implement CLI Commands (Connect, Message)
4. Implement MCP Tools
5. Implement AgentBrowserClient
6. Implement Compare Command
```

## Parallelization

| Group | Tasks | Reason |
|-------|-------|--------|
| A | 3, 4 | CLI and MCP depend on Client (Task 2), but are independent of each other |
| B | 5 | Independent of API features |

---

## TODOs

- [x] 1. Install and Verify `agent-browser`
  **What to do**:
  - Determine correct install method (npm package name or source build from `vercel-labs/agent-browser`).
  - Install tool globally or locally.
  - Create a setup script `scripts/setup_agent_browser.sh`.
  - Verify installation with `agent-browser --version` (or equivalent).
  
  **Acceptance Criteria**:
  - [x] `agent-browser` binary is available in PATH or known location.

- [x] 2. TDD: Implement Invitation & Messaging Logic in `LinkedInClient`
  **What to do**:
  - Update `Tests/LinkedInKitTests/LinkedInClientTests.swift`:
    - Test `sendInvite` request construction (URL, payload).
    - Test `sendMessage` request construction.
  - Update `Sources/LinkLion/LinkedInClient.swift`:
    - Add `sendInvite(profileUrn:message:)`.
    - Add `sendMessage(profileUrn:message:)`.
    - Helper: `resolveURN(from: String)` (fetches profile to get URN if input is URL).
  
  **References**:
  - `docs/api_reference.md`: Endpoints and payloads.
  - `Sources/LinkLion/LinkedInClient.swift:102`: `getProfile` (use for URN resolution).
  
  **Acceptance Criteria**:
  - [x] Tests pass.
  - [x] `resolveURN` correctly extracts URN from `getProfile` result.

- [ ] 3. Implement CLI Commands: `Connect` and `Message`
  **What to do**:
  - Create `Sources/LinkedInCLI/Connect.swift`.
  - Create `Sources/LinkedInCLI/Message.swift`.
  - Register in `Sources/LinkedInCLI/LinkedIn.swift`.
  - **Safety**: Add confirmation prompt "Are you sure you want to send...? (y/n)".
  
  **References**:
  - `Sources/LinkedInCLI/Profile.swift`: Structure reference.
  
  **Acceptance Criteria**:
  - [ ] `linklion connect --help` shows usage.
  - [ ] `linklion message --help` shows usage.
  - [ ] Interactive prompt works.

- [ ] 4. Implement MCP Tools: `send_invite`, `send_message`
  **What to do**:
  - Update `Sources/LinkedInMCP/LinkedInMCP.swift`:
    - Add `linkedin_send_invite` tool definition.
    - Add `linkedin_send_message` tool definition.
    - Implement handlers.
  
  **References**:
  - `Sources/LinkedInMCP/LinkedInMCP.swift:335`: Existing tools.
  
  **Acceptance Criteria**:
  - [ ] Tools listed in `linkedin-mcp` output.

- [ ] 5. Implement `AgentBrowserClient`
  **What to do**:
  - Create `Sources/LinkLion/AgentBrowserClient.swift`.
  - Implement `captureScreen`, `scrapeProfile` (similar to `PeekabooClient`).
  - Use `Process` to call `agent-browser` CLI.
  
  **References**:
  - `Sources/LinkLion/PeekabooClient.swift`: Copy structure/interface.
  
  **Acceptance Criteria**:
  - [ ] Code compiles.
  - [ ] Can invoke `agent-browser` from Swift.

- [ ] 6. Implement `Compare` Command
  **What to do**:
  - Create `Sources/LinkedInCLI/Compare.swift`.
  - Logic:
    - Take `url`.
    - Start timer. Run `PeekabooClient.scrape`. Stop timer.
    - Start timer. Run `AgentBrowserClient.scrape`. Stop timer.
    - Print table comparing: Time, Success/Fail, Output Size.
  - Register in `Sources/LinkedInCLI/LinkedIn.swift`.
  
  **Acceptance Criteria**:
  - [ ] `linklion compare --help` works.
  - [ ] Runs both tools and shows stats.

- [ ] 7. Update Documentation
  **What to do**:
  - Update `README.md`: Add new commands and comparison info.
  - Update `docs/api_reference.md`: Mark features as Implemented.
  
  **Acceptance Criteria**:
  - [ ] README matches code features.

---

## Success Criteria

### Verification Commands
```bash
# Feature Verification
linklion connect "https://linkedin.com/in/testuser" --message "Hi"
linklion message "https://linkedin.com/in/testuser" "Hello there"

# Comparison Verification
linklion compare "https://linkedin.com/in/testuser"
```

### Final Checklist
- [ ] Messaging/Invites work (verified manually)
- [ ] Safety prompts in place
- [ ] AgentBrowser integration works
- [ ] Comparison command outputs valid stats
