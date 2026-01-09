import Foundation
import LinkedInKit
import Logging
import MCP

@main
struct LinkedInMCPMain {
    static func main() async throws {
        var logger = Logger(label: "linkedin.mcp")
        logger.logLevel = .info
        
        let server = Server(
            name: "linkedin",
            version: LinkedInKit.version,
            capabilities: .init(
                logging: .init(),
                tools: .init()
            )
        )
        
        let handler = LinkedInToolHandler(server: server, logger: logger)
        
        await server.withMethodHandler(ListTools.self) { _ in
            await handler.listTools()
        }
        
        await server.withMethodHandler(CallTool.self) { params in
            await handler.callTool(params)
        }
        
        logger.info("Starting LinkedIn MCP Server v\(LinkedInKit.version)")
        logger.info("Tools: linkedin_status, linkedin_configure, linkedin_get_profile, linkedin_get_company, linkedin_search_jobs, linkedin_get_job")
        
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        
        await server.waitUntilCompleted()
    }
}

// MARK: - MCP Logging

public struct LoggingMessageNotification: MCP.Notification {
    public static let name = "notifications/message"
    
    public struct Parameters: Hashable, Codable, Sendable {
        public let level: String
        public let logger: String?
        public let data: Value
        
        public init(level: String, logger: String? = nil, data: Value) {
            self.level = level
            self.logger = logger
            self.data = data
        }
    }
}

public enum LogLevel: String {
    case debug, info, notice, warning, error, critical
}

extension Server {
    func log(_ level: LogLevel, _ message: String, logger: String? = nil) async {
        do {
            let params = LoggingMessageNotification.Parameters(
                level: level.rawValue,
                logger: logger,
                data: .string(message)
            )
            let msg: Message<LoggingMessageNotification> = LoggingMessageNotification.message(params)
            try await self.notify(msg)
        } catch {
            // Silently fail - logging shouldn't crash the server
        }
    }
}

// MARK: - Tool Handler

actor LinkedInToolHandler {
    private var client: LinkedInClient?
    private let credentialStore: CredentialStore
    private let server: Server
    private let logger: Logger
    
    init(server: Server, logger: Logger) {
        self.server = server
        self.logger = logger
        self.credentialStore = CredentialStore()
    }
    
    func listTools() -> ListTools.Result {
        ListTools.Result(tools: Self.tools)
    }
    
    func callTool(_ params: CallTool.Parameters) async -> CallTool.Result {
        let toolName = params.name
        let args = params.arguments ?? [:]
        
        await server.log(.debug, "Calling tool: \(toolName)", logger: "linkedin")
        
        switch toolName {
        case "linkedin_status":
            return await handleStatus()
        case "linkedin_configure":
            return await handleConfigure(args)
        case "linkedin_get_profile":
            return await handleGetProfile(args)
        case "linkedin_get_company":
            return await handleGetCompany(args)
        case "linkedin_search_jobs":
            return await handleSearchJobs(args)
        case "linkedin_get_job":
            return await handleGetJob(args)
        default:
            return CallTool.Result(
                content: [.text("Unknown tool: \(toolName)")],
                isError: true
            )
        }
    }
    
    // MARK: - Client Management
    
    private func getClient() async throws -> LinkedInClient {
        if let client = self.client {
            return client
        }
        
        guard let cookie = try credentialStore.loadCookie() else {
            throw LinkedInMCPError.notAuthenticated(
                "Not authenticated. Use linkedin_configure to set the li_at cookie."
            )
        }
        
        let client = LinkedInClient()
        await client.configure(cookie: cookie)
        self.client = client
        
        await server.log(.info, "Client initialized with stored cookie", logger: "linkedin")
        return client
    }
    
    // MARK: - Tool Implementations
    
    private func handleStatus() async -> CallTool.Result {
        do {
            let client = try await getClient()
            let status = try await client.verifyAuth()
            await server.log(.info, "Auth status: \(status.valid ? "valid" : "invalid")", logger: "linkedin")
            return CallTool.Result(content: [.text(toJSON(status))])
        } catch {
            let status = AuthStatus(valid: false, message: error.localizedDescription)
            return CallTool.Result(content: [.text(toJSON(status))])
        }
    }
    
    private func handleConfigure(_ args: [String: Value]) async -> CallTool.Result {
        guard let cookie = args["cookie"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: cookie")],
                isError: true
            )
        }
        
        do {
            try credentialStore.saveCookie(cookie)
            
            let client = LinkedInClient()
            await client.configure(cookie: cookie)
            self.client = client
            
            let status = try await client.verifyAuth()
            
            await server.log(.info, "Cookie configured, auth: \(status.valid ? "valid" : "invalid")", logger: "linkedin")
            
            if status.valid {
                return CallTool.Result(content: [.text(
                    #"{"success": true, "message": "Cookie saved and verified successfully"}"#
                )])
            } else {
                return CallTool.Result(content: [.text(
                    #"{"success": true, "warning": "\#(status.message)", "message": "Cookie saved but verification failed - it may be expired"}"#
                )])
            }
        } catch {
            return CallTool.Result(
                content: [.text("Failed to save cookie: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func handleGetProfile(_ args: [String: Value]) async -> CallTool.Result {
        guard let usernameOrURL = args["username"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: username")],
                isError: true
            )
        }
        
        guard let username = extractUsername(from: usernameOrURL) else {
            return CallTool.Result(
                content: [.text("Invalid username or URL: \(usernameOrURL)")],
                isError: true
            )
        }
        
        do {
            let client = try await getClient()
            await server.log(.info, "Fetching profile: \(username)", logger: "linkedin")
            
            let profile = try await client.getProfile(username: username)
            
            await server.log(.notice, "Profile fetched: \(profile.name)", logger: "linkedin")
            return CallTool.Result(content: [.text(toJSON(profile))])
        } catch {
            await server.log(.error, "Failed to fetch profile: \(error.localizedDescription)", logger: "linkedin")
            return CallTool.Result(
                content: [.text("Failed to fetch profile: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func handleGetCompany(_ args: [String: Value]) async -> CallTool.Result {
        guard let nameOrURL = args["company"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: company")],
                isError: true
            )
        }
        
        guard let companyName = extractCompanyName(from: nameOrURL) else {
            return CallTool.Result(
                content: [.text("Invalid company name or URL: \(nameOrURL)")],
                isError: true
            )
        }
        
        do {
            let client = try await getClient()
            await server.log(.info, "Fetching company: \(companyName)", logger: "linkedin")
            
            let company = try await client.getCompany(name: companyName)
            
            await server.log(.notice, "Company fetched: \(company.name)", logger: "linkedin")
            return CallTool.Result(content: [.text(toJSON(company))])
        } catch {
            await server.log(.error, "Failed to fetch company: \(error.localizedDescription)", logger: "linkedin")
            return CallTool.Result(
                content: [.text("Failed to fetch company: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func handleSearchJobs(_ args: [String: Value]) async -> CallTool.Result {
        guard let query = args["query"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: query")],
                isError: true
            )
        }
        
        let location = args["location"]?.stringValue
        let limit = Int(args["limit"] ?? .int(25), strict: false) ?? 25
        
        do {
            let client = try await getClient()
            await server.log(.info, "Searching jobs: '\(query)' location=\(location ?? "any") limit=\(limit)", logger: "linkedin")
            
            let jobs = try await client.searchJobs(query: query, location: location, limit: limit)
            
            await server.log(.notice, "Found \(jobs.count) jobs", logger: "linkedin")
            return CallTool.Result(content: [.text(toJSON(jobs))])
        } catch {
            await server.log(.error, "Job search failed: \(error.localizedDescription)", logger: "linkedin")
            return CallTool.Result(
                content: [.text("Job search failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    private func handleGetJob(_ args: [String: Value]) async -> CallTool.Result {
        guard let jobIdOrURL = args["job_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: job_id")],
                isError: true
            )
        }
        
        guard let jobId = extractJobId(from: jobIdOrURL) else {
            return CallTool.Result(
                content: [.text("Invalid job ID or URL: \(jobIdOrURL)")],
                isError: true
            )
        }
        
        do {
            let client = try await getClient()
            await server.log(.info, "Fetching job: \(jobId)", logger: "linkedin")
            
            let job = try await client.getJob(id: jobId)
            
            await server.log(.notice, "Job fetched: \(job.title) at \(job.company)", logger: "linkedin")
            return CallTool.Result(content: [.text(toJSON(job))])
        } catch {
            await server.log(.error, "Failed to fetch job: \(error.localizedDescription)", logger: "linkedin")
            return CallTool.Result(
                content: [.text("Failed to fetch job: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    // MARK: - Helpers
    
    private func toJSON<T: Codable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

// MARK: - Tool Definitions

extension LinkedInToolHandler {
    static var tools: [Tool] {
        [
            Tool(
                name: "linkedin_status",
                description: "Check LinkedIn authentication status. Returns whether the current session is valid.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([:])
                ]),
                annotations: .init(
                    title: "Check Auth Status",
                    readOnlyHint: true,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: false
                )
            ),
            Tool(
                name: "linkedin_configure",
                description: """
                    Configure LinkedIn authentication with a li_at cookie. 
                    
                    To get the cookie:
                    1. Open LinkedIn in your browser and log in
                    2. Open Developer Tools (F12 or Cmd+Option+I)
                    3. Go to Application → Cookies → linkedin.com
                    4. Find the 'li_at' cookie and copy its value
                    
                    The cookie is stored securely in the macOS Keychain.
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "cookie": .object([
                            "type": "string",
                            "description": "The li_at cookie value from LinkedIn"
                        ])
                    ]),
                    "required": .array(["cookie"])
                ]),
                annotations: .init(
                    title: "Configure Authentication",
                    readOnlyHint: false,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: false
                )
            ),
            Tool(
                name: "linkedin_get_profile",
                description: """
                    Get a person's LinkedIn profile. Returns structured data including:
                    - Name, headline, location
                    - About/summary section
                    - Work experience history
                    - Education background
                    - Skills
                    - Open to work status
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "username": .object([
                            "type": "string",
                            "description": "LinkedIn username (e.g., 'johndoe') or full profile URL (https://linkedin.com/in/johndoe)"
                        ])
                    ]),
                    "required": .array(["username"])
                ]),
                annotations: .init(
                    title: "Get Person Profile",
                    readOnlyHint: true,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: true
                )
            ),
            Tool(
                name: "linkedin_get_company",
                description: """
                    Get a company's LinkedIn profile. Returns structured data including:
                    - Company name and tagline
                    - About/description section
                    - Industry and company size
                    - Headquarters location
                    - Website URL
                    - Specialties/focus areas
                    - Employee and follower counts
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "company": .object([
                            "type": "string",
                            "description": "Company name/slug (e.g., 'microsoft', 'anthropic') or full company URL"
                        ])
                    ]),
                    "required": .array(["company"])
                ]),
                annotations: .init(
                    title: "Get Company Profile",
                    readOnlyHint: true,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: true
                )
            ),
            Tool(
                name: "linkedin_search_jobs",
                description: """
                    Search for jobs on LinkedIn. Returns a list of job postings matching the search criteria.
                    
                    Each result includes:
                    - Job ID and URL
                    - Title and company
                    - Location
                    - Posted date
                    - Salary (if shown)
                    - Easy Apply availability
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "query": .object([
                            "type": "string",
                            "description": "Search query - job title, skills, keywords, etc."
                        ]),
                        "location": .object([
                            "type": "string",
                            "description": "Location filter - city, state, country, or 'Remote'"
                        ]),
                        "limit": .object([
                            "type": "integer",
                            "description": "Maximum number of results to return (default: 25, max: 100)"
                        ])
                    ]),
                    "required": .array(["query"])
                ]),
                annotations: .init(
                    title: "Search Jobs",
                    readOnlyHint: true,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: true
                )
            ),
            Tool(
                name: "linkedin_get_job",
                description: """
                    Get detailed information about a specific job posting. Returns:
                    - Full job title and company
                    - Complete job description
                    - Workplace type (Remote/On-site/Hybrid)
                    - Employment type (Full-time/Part-time/Contract)
                    - Experience level required
                    - Salary information (if available)
                    - Required skills
                    - Application count
                    - Easy Apply availability
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "job_id": .object([
                            "type": "string",
                            "description": "LinkedIn job ID (numeric) or full job URL (https://linkedin.com/jobs/view/1234567890)"
                        ])
                    ]),
                    "required": .array(["job_id"])
                ]),
                annotations: .init(
                    title: "Get Job Details",
                    readOnlyHint: true,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: true
                )
            ),
        ]
    }
}

// MARK: - Value Extensions

extension Value {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

func Int(_ value: Value, strict: Bool) -> Int? {
    switch value {
    case .int(let i): return i
    case .string(let s) where !strict: return Int(s)
    default: return nil
    }
}

// MARK: - Errors

enum LinkedInMCPError: Error, LocalizedError {
    case internalError(String)
    case methodNotFound(String)
    case invalidParams(String)
    case notAuthenticated(String)
    
    var errorDescription: String? {
        switch self {
        case .internalError(let msg): return "Internal error: \(msg)"
        case .methodNotFound(let msg): return "Method not found: \(msg)"
        case .invalidParams(let msg): return "Invalid parameters: \(msg)"
        case .notAuthenticated(let msg): return "Not authenticated: \(msg)"
        }
    }
}
