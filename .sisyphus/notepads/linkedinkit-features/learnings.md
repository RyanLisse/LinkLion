# Learnings & Conventions

## [2026-01-26T06:18:43Z] Session Start
- Plan: LinkedInKit Feature Expansion & Browser Comparison
- Session: ses_40712721affe4PUkwPwvyuCrBM

## [2026-01-26T06:21:00Z] Codebase Architecture Discovery

### API Request Patterns (LinkedInClient.swift)
- **Pattern**: `guard let cookie` → `fetchPage(url:cookie:)` → parse HTML
- **Auth**: Cookie stored in `liAtCookie`, passed as `Cookie: li_at={value}` header
- **Error Handling**: Throws `LinkedInError` enum (notAuthenticated, invalidURL, httpError, etc.)
- **Fallback**: Peekaboo vision fallback enabled by default via `_usePeekabooFallback` flag

### URN Handling
- **Current State**: NO URN extraction implemented yet
- **Reference**: `docs/api_reference.md` mentions URNs (lines 46, 101, 108, 129, 139)
- **Format**: `urn:li:fsd_profile:ACoAA...` or `urn:li:fs_miniProfile:123`
- **Need**: Helper to extract URN from profile HTML or API response

### CLI Command Structure
- **Framework**: ArgumentParser with `AsyncParsableCommand`
- **Pattern**: `@Argument` (positional), `@Flag` (boolean), `@Option` (named), `@OptionGroup` (reusable)
- **Global Options**: `--json` flag and `--cookie` override
- **Validation**: Uses `ValidationError` from ArgumentParser
- **Helper Functions**: `extractUsername()`, `extractCompanyName()`, `extractJobId()` in LinkedInKit.swift

### MCP Tool Structure
- **Handler**: Actor-based `LinkedInToolHandler` with lazy client initialization
- **Pattern**: `CallTool.Parameters` → extract args → validate → execute → return `CallTool.Result`
- **JSON**: Pretty-printed with sorted keys, ISO8601 dates
- **Logging**: Custom notification-based logging with 6 levels (debug, info, notice, warning, error, critical)
- **Error Response**: `CallTool.Result(content: [.text("error")], isError: true)`

### Process Execution Pattern (PeekabooClient.swift)
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/path/to/binary")
process.arguments = ["arg1", "arg2"]
let stdoutPipe = Pipe()
let stderrPipe = Pipe()
process.standardOutput = stdoutPipe
process.standardError = stderrPipe
try process.run()
process.waitUntilExit()
```

### agent-browser Installation
- **Method**: `npm install -g agent-browser` (recommended)
- **Post-install**: `agent-browser install` (downloads Chromium ~160MB)
- **Linux**: `agent-browser install --with-deps` (system dependencies)
- **Verification**: `agent-browser --version` or `which agent-browser`
- **Architecture**: Rust CLI + Node.js daemon + Playwright backend

## [2026-01-26T07:26:00Z] sendInvite/sendMessage Implementation

### API Endpoints Implemented
- **Send Invite**: `POST /voyagerRelationshipsDashMemberRelationships?action=verifyQuotaAndCreateV2`
- **Send Message**: `POST /messaging/conversations`

### Payload Structures
- `InvitePayload`: `{invitee: {inviteeUnion: {memberProfile: "urn:..."}}, customMessage: "..."}`
- `MessagePayload`: `{keyVersion: "LEGACY_INBOX", conversationCreate: {eventCreate: {...}, recipients: [...], subtype: "MEMBER_TO_MEMBER"}}`

### Static Helpers Added
- `LinkedInClient.buildInviteURL()` - Returns invite endpoint URL
- `LinkedInClient.buildMessageURL()` - Returns message endpoint URL
- `LinkedInClient.buildPlaceholderURN(from:)` - Creates placeholder URN from username
- `LinkedInClient.isValidURN(_:)` - Validates URN format

### Test Patterns
- Payload encoding tests verify JSON structure matches API spec
- URL construction tests verify endpoint paths
- Auth tests verify `notAuthenticated` error when no cookie
- Tests import `@testable import LinkLion` (not LinkedInKit)

### Package.swift
- Test target was missing, added: `.testTarget(name: "LinkedInKitTests", dependencies: ["LinkLion"])`
