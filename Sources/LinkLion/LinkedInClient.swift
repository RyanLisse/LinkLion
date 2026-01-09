import Foundation
import Logging
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Main client for interacting with LinkedIn
public actor LinkedInClient {
    private let session: URLSession
    private var liAtCookie: String?
    private let logger = Logger(label: "LinkedInKit")
    
    private static let baseURL = "https://www.linkedin.com"
    private static let apiURL = "https://www.linkedin.com/voyager/api"
    
    public init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Accept-Encoding": "gzip, deflate, br",
            "DNT": "1",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
            "Sec-Fetch-User": "?1",
        ]
        self.session = URLSession(configuration: config)
    }
    
    /// Configure the client with a li_at cookie
    public func configure(cookie: String) {
        // Accept either just the value or "li_at=value" format
        if cookie.hasPrefix("li_at=") {
            self.liAtCookie = String(cookie.dropFirst(6))
        } else {
            self.liAtCookie = cookie
        }
        logger.info("LinkedIn client configured with cookie")
    }
    
    /// Check if the client is authenticated
    public var isAuthenticated: Bool {
        liAtCookie != nil
    }
    
    /// Get the current cookie value
    public var cookie: String? {
        liAtCookie
    }
    
    /// Verify the current authentication is valid
    public func verifyAuth() async throws -> AuthStatus {
        guard let cookie = liAtCookie else {
            return AuthStatus(valid: false, message: "No cookie configured")
        }
        
        // Try to fetch the feed to verify auth
        let url = URL(string: "\(Self.baseURL)/feed/")!
        var request = URLRequest(url: url)
        request.setValue("li_at=\(cookie)", forHTTPHeaderField: "Cookie")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return AuthStatus(valid: false, message: "Invalid response")
        }
        
        // If we get redirected to login, auth is invalid
        if httpResponse.url?.path.contains("login") == true || 
           httpResponse.url?.path.contains("checkpoint") == true {
            return AuthStatus(valid: false, message: "Cookie expired or invalid")
        }
        
        if httpResponse.statusCode == 200 {
            return AuthStatus(valid: true, message: "Authenticated")
        }
        
        return AuthStatus(valid: false, message: "HTTP \(httpResponse.statusCode)")
    }
    
    // MARK: - Profile Scraping
    
    /// Get a person's LinkedIn profile
    public func getProfile(username: String) async throws -> PersonProfile {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        let profileURL = "\(Self.baseURL)/in/\(username)/"
        logger.info("Fetching profile: \(username)")
        
        let html = try await fetchPage(url: profileURL, cookie: cookie)
        return try ProfileParser.parsePersonProfile(html: html, username: username)
    }
    
    /// Get a company's LinkedIn profile
    public func getCompany(name: String) async throws -> CompanyProfile {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        let companyURL = "\(Self.baseURL)/company/\(name)/"
        logger.info("Fetching company: \(name)")
        
        let html = try await fetchPage(url: companyURL, cookie: cookie)
        return try ProfileParser.parseCompanyProfile(html: html, companyName: name)
    }
    
    // MARK: - Job Search
    
    /// Search for jobs
    public func searchJobs(query: String, location: String? = nil, limit: Int = 25) async throws -> [JobListing] {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        var urlComponents = URLComponents(string: "\(Self.baseURL)/jobs/search/")!
        var queryItems = [
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "refresh", value: "true"),
        ]
        
        if let location = location {
            queryItems.append(URLQueryItem(name: "location", value: location))
        }
        
        urlComponents.queryItems = queryItems
        
        logger.info("Searching jobs: \(query)")
        
        let html = try await fetchPage(url: urlComponents.url!.absoluteString, cookie: cookie)
        return try JobParser.parseJobSearch(html: html, limit: limit)
    }
    
    /// Get details for a specific job
    public func getJob(id: String) async throws -> JobDetails {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        let jobURL = "\(Self.baseURL)/jobs/view/\(id)/"
        logger.info("Fetching job: \(id)")
        
        let html = try await fetchPage(url: jobURL, cookie: cookie)
        return try JobParser.parseJobDetails(html: html, jobId: id)
    }
    
    // MARK: - Private Helpers
    
    private func fetchPage(url: String, cookie: String) async throws -> String {
        guard let url = URL(string: url) else {
            throw LinkedInError.invalidURL(url)
        }
        
        var request = URLRequest(url: url)
        request.setValue("li_at=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }
        
        // Check for auth issues
        if httpResponse.url?.path.contains("login") == true {
            throw LinkedInError.notAuthenticated
        }
        
        if httpResponse.url?.path.contains("checkpoint") == true {
            throw LinkedInError.securityChallenge
        }
        
        guard httpResponse.statusCode == 200 else {
            throw LinkedInError.httpError(httpResponse.statusCode)
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw LinkedInError.invalidResponse
        }
        
        return html
    }
}

// MARK: - Types

public struct AuthStatus: Codable, Sendable {
    public let valid: Bool
    public let message: String
    
    public init(valid: Bool, message: String) {
        self.valid = valid
        self.message = message
    }
}

public enum LinkedInError: Error, LocalizedError, Sendable {
    case notAuthenticated
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)
    case securityChallenge
    case parseError(String)
    case rateLimited
    case profileNotFound
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please configure with a valid li_at cookie."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Invalid response from LinkedIn"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .securityChallenge:
            return "LinkedIn requires a security challenge. Please complete it in a browser."
        case .parseError(let msg):
            return "Failed to parse response: \(msg)"
        case .rateLimited:
            return "Rate limited by LinkedIn. Please wait before retrying."
        case .profileNotFound:
            return "Profile not found"
        }
    }
}
