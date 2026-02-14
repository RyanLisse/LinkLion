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
    private let peekaboo: PeekabooClient
    private let gemini: GeminiVision
    
    /// Enable Peekaboo fallback for failed scrapes
    private var _usePeekabooFallback: Bool = true
    
    public var usePeekabooFallback: Bool {
        _usePeekabooFallback
    }
    
    public func setUsePeekabooFallback(_ enabled: Bool) {
        _usePeekabooFallback = enabled
    }
    
    private static let baseURL = "https://www.linkedin.com"
    private static let apiURL = "https://www.linkedin.com/voyager/api"
    
    public init(browser: String = "Safari") {
        self.peekaboo = PeekabooClient(browser: browser)
        self.gemini = GeminiVision()
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
    /// Uses HTML scraping first, falls back to Peekaboo vision if enabled
    public func getProfile(username: String) async throws -> PersonProfile {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        let profileURL = "\(Self.baseURL)/in/\(username)/"
        logger.info("Fetching profile: \(username)")
        
        do {
            let html = try await fetchPage(url: profileURL, cookie: cookie)
            let profile = try ProfileParser.parsePersonProfile(html: html, username: username)
            
            // Check if we got meaningful data
            if !profile.name.isEmpty && profile.name != "LinkedIn" {
                return profile
            }
            
            // Data is incomplete, try Peekaboo if enabled
            if _usePeekabooFallback {
                logger.info("HTML parsing returned minimal data, trying Peekaboo vision...")
                return try await getProfileWithVision(username: username)
            }
            
            return profile
        } catch {
            // On error, try Peekaboo fallback
            if _usePeekabooFallback {
                logger.warning("HTML scraping failed: \(error). Trying Peekaboo fallback...")
                return try await getProfileWithVision(username: username)
            }
            throw error
        }
    }
    
    /// Get profile using Peekaboo browser automation and Gemini Vision
    public func getProfileWithVision(username: String) async throws -> PersonProfile {
        logger.info("Fetching profile with Peekaboo vision: \(username)")
        
        // Capture screenshot
        let capture = try await peekaboo.captureScreen()
        logger.info("Screenshot saved: \(capture.path)")
        
        // Analyze with Gemini Vision
        let analysis = try await gemini.analyzeProfile(imagePath: capture.path)
        logger.info("Gemini analysis complete")
        
        // Convert analysis to PersonProfile
        return PersonProfile(
            username: username,
            name: analysis.name ?? username,
            headline: analysis.headline,
            about: analysis.about,
            location: analysis.location,
            company: analysis.company,
            jobTitle: analysis.jobTitle,
            experiences: analysis.experiences.map { exp in
                Experience(
                    title: exp.title,
                    company: exp.company,
                    location: exp.location,
                    startDate: nil,
                    endDate: nil,
                    duration: exp.duration,
                    description: nil
                )
            },
            educations: analysis.educations.map { edu in
                Education(
                    institution: edu.institution,
                    degree: edu.degree,
                    startDate: nil,
                    endDate: edu.years
                )
            },
            skills: analysis.skills,
            connectionCount: analysis.connectionCount,
            followerCount: analysis.followerCount,
            openToWork: analysis.openToWork
        )
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
    
    
// MARK: - Connections & Messaging
    
    /// Send a connection invitation to a LinkedIn profile
    /// - Parameters:
    ///   - profileUrn: The URN of the profile (e.g., "urn:li:fsd_profile:ACoAA...")
    ///   - message: Optional custom message to include with the invitation
    public func sendInvite(profileUrn: String, message: String?) async throws {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        guard Self.isValidURN(profileUrn) else {
            throw LinkedInError.invalidURN(profileUrn)
        }
        
        logger.info("Sending invite to: \(profileUrn)")
        
        let url = Self.buildInviteURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("li_at=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.linkedin.normalized+json+2.1", forHTTPHeaderField: "Accept")
        request.setValue("2.0.0", forHTTPHeaderField: "X-RestLi-Protocol-Version")
        request.setValue("en_US", forHTTPHeaderField: "X-Li-Lang")
        
        let payload = InvitePayload(profileUrn: profileUrn, message: message)
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw LinkedInError.rateLimited
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LinkedInError.httpError(httpResponse.statusCode)
        }
        
        logger.info("Invite sent successfully")
    }
    
    /// Send a message to a LinkedIn profile
    /// - Parameters:
    ///   - profileUrn: The URN of the profile (e.g., "urn:li:fsd_profile:ACoAA...")
    ///   - message: The message content to send
    public func sendMessage(profileUrn: String, message: String) async throws {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        guard Self.isValidURN(profileUrn) else {
            throw LinkedInError.invalidURN(profileUrn)
        }
        
        logger.info("Sending message to: \(profileUrn)")
        
        let url = Self.buildMessageURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("li_at=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.linkedin.normalized+json+2.1", forHTTPHeaderField: "Accept")
        request.setValue("2.0.0", forHTTPHeaderField: "X-RestLi-Protocol-Version")
        request.setValue("en_US", forHTTPHeaderField: "X-Li-Lang")
        
        let payload = MessagePayload(profileUrn: profileUrn, message: message)
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw LinkedInError.rateLimited
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LinkedInError.httpError(httpResponse.statusCode)
        }
        
        logger.info("Message sent successfully")
    }
    
    /// Resolve a username to a placeholder URN format
    public func resolveURN(from username: String) async throws -> String {
        guard liAtCookie != nil else {
            throw LinkedInError.notAuthenticated
        }
        return Self.buildPlaceholderURN(from: username)
    }
    
    // MARK: - Static Helpers
    
    public static func buildInviteURL() -> URL {
        URL(string: "\(apiURL)/voyagerRelationshipsDashMemberRelationships?action=verifyQuotaAndCreateV2")!
    }
    
    public static func buildMessageURL() -> URL {
        URL(string: "\(apiURL)/messaging/conversations")!
    }
    
    public static func buildPlaceholderURN(from username: String) -> String {
        "urn:li:fsd_profile:\(username)"
    }
    
    public static func isValidURN(_ urn: String) -> Bool {
        urn.hasPrefix("urn:li:") && urn.contains("_profile:") || urn.contains("_miniProfile:")
    }
    
    
// MARK: - CSRF Token

    /// Fetch CSRF token by extracting JSESSIONID from LinkedIn cookies
    private func getCSRFToken() async throws -> String {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }

        let url = URL(string: "\(Self.baseURL)/feed/")!
        var request = URLRequest(url: url)
        request.setValue("li_at=\(cookie)", forHTTPHeaderField: "Cookie")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }

        // Extract JSESSIONID from Set-Cookie headers
        if let headers = httpResponse.allHeaderFields as? [String: String],
           let url = httpResponse.url {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            for c in cookies where c.name == "JSESSIONID" {
                let value = c.value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return "ajax:\(value)"
            }
        }

        // Fallback: try to find it in response headers directly
        if let setCookies = httpResponse.value(forHTTPHeaderField: "Set-Cookie") {
            if let range = setCookies.range(of: "JSESSIONID=\"") {
                let start = range.upperBound
                if let end = setCookies[start...].range(of: "\"")?.lowerBound {
                    let jsessionid = String(setCookies[start..<end])
                    return "ajax:\(jsessionid)"
                }
            }
        }

        throw LinkedInError.parseError("Could not extract CSRF token")
    }

    /// Build an authenticated Voyager API request
    private func voyagerRequest(path: String, method: String = "GET", body: Data? = nil) async throws -> URLRequest {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }

        let csrf = try await getCSRFToken()
        let url = URL(string: "\(Self.apiURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("li_at=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue(csrf, forHTTPHeaderField: "csrf-token")
        request.setValue("2.0.0", forHTTPHeaderField: "X-Restli-Protocol-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return request
    }

    // MARK: - Get Current User URN

    /// Get the authenticated user's profile URN (needed for posting)
    public func getMyProfileURN() async throws -> String {
        let request = try await voyagerRequest(path: "/identity/profiles/me")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LinkedInError.invalidResponse
        }

        // Parse the miniProfile or profile ID from response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Try multiple paths to find the profile ID
            if let miniProfile = json["miniProfile"] as? [String: Any],
               let entityUrn = miniProfile["entityUrn"] as? String {
                return entityUrn
            }
            if let entityUrn = json["entityUrn"] as? String {
                return entityUrn
            }
            if let plainId = json["plainId"] as? Int {
                return "urn:li:fsd_profile:\(plainId)"
            }
        }

        throw LinkedInError.parseError("Could not determine profile URN")
    }

    // MARK: - Post Creation

    /// Create a text-only LinkedIn post
    public func createTextPost(text: String, visibility: PostVisibility = .public) async throws -> PostResult {
        let connectionsOnly = visibility == .connections

        let payload: [String: Any] = [
            "visibleToConnectionsOnly": connectionsOnly,
            "externalAudienceProviders": [] as [Any],
            "commentaryV2": [
                "text": text,
                "attributes": [] as [Any]
            ] as [String: Any],
            "origin": "FEED",
            "allowedCommentersScope": "ALL",
            "postState": "PUBLISHED"
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try await voyagerRequest(
            path: "/contentCreation/normShares",
            method: "POST",
            body: body
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }

        if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
            // Try to extract post URN from response or headers
            var postURN: String?
            if let restliId = httpResponse.value(forHTTPHeaderField: "X-RestLi-Id") {
                postURN = restliId
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                postURN = json["urn"] as? String ?? json["id"] as? String
            }
            return PostResult(success: true, postURN: postURN, message: "Post created successfully")
        }

        // Parse error
        let errorMsg: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String {
            errorMsg = msg
        } else {
            errorMsg = "HTTP \(httpResponse.statusCode)"
        }
        return PostResult(success: false, message: errorMsg)
    }

    /// Create an article/URL share post
    public func createArticlePost(
        text: String,
        url articleURL: String,
        title: String? = nil,
        description: String? = nil,
        visibility: PostVisibility = .public
    ) async throws -> PostResult {
        let connectionsOnly = visibility == .connections

        var mediaObj: [String: Any] = [
            "status": "READY",
            "originalUrl": articleURL
        ]
        if let title = title {
            mediaObj["title"] = ["text": title]
        }
        if let description = description {
            mediaObj["description"] = ["text": description]
        }

        let payload: [String: Any] = [
            "visibleToConnectionsOnly": connectionsOnly,
            "externalAudienceProviders": [] as [Any],
            "commentaryV2": [
                "text": text,
                "attributes": [] as [Any]
            ] as [String: Any],
            "origin": "FEED",
            "allowedCommentersScope": "ALL",
            "postState": "PUBLISHED",
            "media": [
                [
                    "category": "ARTICLE",
                    "data": mediaObj
                ] as [String: Any]
            ] as [Any]
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try await voyagerRequest(
            path: "/contentCreation/normShares",
            method: "POST",
            body: body
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }

        if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
            var postURN: String?
            if let restliId = httpResponse.value(forHTTPHeaderField: "X-RestLi-Id") {
                postURN = restliId
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                postURN = json["urn"] as? String ?? json["id"] as? String
            }
            return PostResult(success: true, postURN: postURN, message: "Article post created successfully")
        }

        let errorMsg: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String {
            errorMsg = msg
        } else {
            errorMsg = "HTTP \(httpResponse.statusCode)"
        }
        return PostResult(success: false, message: errorMsg)
    }

    // MARK: - Media Upload

    /// Upload an image and return the media URN for use in posts
    public func uploadImage(data imageData: Data, filename: String = "image.jpg") async throws -> MediaUploadResult {
        // Step 1: Register the upload
        let registerPayload: [String: Any] = [
            "mediaUploadType": "IMAGE_SHARING",
            "fileSize": imageData.count,
            "filename": filename
        ]

        let registerBody = try JSONSerialization.data(withJSONObject: registerPayload)
        let registerRequest = try await voyagerRequest(
            path: "/voyagerMediaUploadMetadata?action=upload",
            method: "POST",
            body: registerBody
        )

        let (registerData, registerResponse) = try await session.data(for: registerRequest)

        guard let registerHttp = registerResponse as? HTTPURLResponse,
              registerHttp.statusCode == 200 || registerHttp.statusCode == 201 else {
            let code = (registerResponse as? HTTPURLResponse)?.statusCode ?? 0
            throw LinkedInError.httpError(code)
        }

        guard let registerJson = try? JSONSerialization.jsonObject(with: registerData) as? [String: Any],
              let valueObj = registerJson["value"] as? [String: Any] ?? registerJson["data"] as? [String: Any] else {
            throw LinkedInError.parseError("Could not parse upload registration response")
        }

        // Extract upload URL and media URN from various response shapes
        let uploadURL: String
        let mediaURN: String

        if let singleUpload = valueObj["singleUploadUrl"] as? String {
            uploadURL = singleUpload
        } else if let uploadMech = valueObj["uploadMechanism"] as? [String: Any] {
            if let httpUpload = uploadMech["com.linkedin.digitalmedia.uploading.MediaUploadHttpRequest"] as? [String: Any],
               let url = httpUpload["uploadUrl"] as? String {
                uploadURL = url
            } else {
                throw LinkedInError.parseError("No upload URL in response")
            }
        } else {
            throw LinkedInError.parseError("No upload URL in response")
        }

        if let urn = valueObj["urn"] as? String {
            mediaURN = urn
        } else if let asset = valueObj["asset"] as? String {
            mediaURN = asset
        } else if let mediaId = valueObj["mediaId"] as? String {
            mediaURN = mediaId
        } else {
            throw LinkedInError.parseError("No media URN in response")
        }

        // Step 2: Upload the binary
        guard let uploadURLObj = URL(string: uploadURL) else {
            throw LinkedInError.invalidURL(uploadURL)
        }

        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }

        let csrf = try await getCSRFToken()
        var uploadRequest = URLRequest(url: uploadURLObj)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("li_at=\(cookie)", forHTTPHeaderField: "Cookie")
        uploadRequest.setValue(csrf, forHTTPHeaderField: "csrf-token")
        uploadRequest.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = imageData

        let (_, uploadResponse) = try await session.data(for: uploadRequest)

        guard let uploadHttp = uploadResponse as? HTTPURLResponse,
              (200...299).contains(uploadHttp.statusCode) else {
            let code = (uploadResponse as? HTTPURLResponse)?.statusCode ?? 0
            throw LinkedInError.httpError(code)
        }

        logger.info("Image uploaded successfully: \(mediaURN)")
        return MediaUploadResult(mediaURN: mediaURN, uploadURL: uploadURL)
    }

    /// Create a post with an uploaded image
    public func createImagePost(
        text: String,
        imageData: Data,
        filename: String = "image.jpg",
        visibility: PostVisibility = .public
    ) async throws -> PostResult {
        // Upload image first
        let upload = try await uploadImage(data: imageData, filename: filename)

        let connectionsOnly = visibility == .connections

        let payload: [String: Any] = [
            "visibleToConnectionsOnly": connectionsOnly,
            "externalAudienceProviders": [] as [Any],
            "commentaryV2": [
                "text": text,
                "attributes": [] as [Any]
            ] as [String: Any],
            "origin": "FEED",
            "allowedCommentersScope": "ALL",
            "postState": "PUBLISHED",
            "media": [
                [
                    "category": "IMAGE",
                    "data": [
                        "status": "READY",
                        "media": upload.mediaURN
                    ] as [String: Any]
                ] as [String: Any]
            ] as [Any]
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try await voyagerRequest(
            path: "/contentCreation/normShares",
            method: "POST",
            body: body
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }

        if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
            var postURN: String?
            if let restliId = httpResponse.value(forHTTPHeaderField: "X-RestLi-Id") {
                postURN = restliId
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                postURN = json["urn"] as? String ?? json["id"] as? String
            }
            return PostResult(success: true, postURN: postURN, message: "Image post created successfully")
        }

        let errorMsg: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String {
            errorMsg = msg
        } else {
            errorMsg = "HTTP \(httpResponse.statusCode)"
        }
        return PostResult(success: false, message: errorMsg)
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


public enum LinkedInError: Error, LocalizedError, Sendable {
    case notAuthenticated
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)
    case securityChallenge
    case parseError(String)
    case rateLimited
    case profileNotFound
    case invalidURN(String)
    
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
        case .invalidURN(let urn):
            return "Invalid URN format: \(urn)"
        }
    }
}


// MARK: - Invite Payload

public struct InvitePayload: Codable, Sendable {
    public let invitee: Invitee
    public let customMessage: String?
    
    public init(profileUrn: String, message: String?) {
        self.invitee = Invitee(inviteeUnion: InviteeUnion(memberProfile: profileUrn))
        self.customMessage = message
    }
    
    public struct Invitee: Codable, Sendable {
        public let inviteeUnion: InviteeUnion
    }
    
    public struct InviteeUnion: Codable, Sendable {
        public let memberProfile: String
    }
}

// MARK: - Message Payload

public struct MessagePayload: Codable, Sendable {
    public let keyVersion: String
    public let conversationCreate: ConversationCreate
    
    public init(profileUrn: String, message: String) {
        self.keyVersion = "LEGACY_INBOX"
        self.conversationCreate = ConversationCreate(
            eventCreate: EventCreate(
                value: EventValue(
                    messageCreate: MessageCreate(
                        attributedBody: AttributedBody(text: message)
                    )
                )
            ),
            recipients: [profileUrn],
            subtype: "MEMBER_TO_MEMBER"
        )
    }
    
    public struct ConversationCreate: Codable, Sendable {
        public let eventCreate: EventCreate
        public let recipients: [String]
        public let subtype: String
    }
    
    public struct EventCreate: Codable, Sendable {
        public let value: EventValue
    }
    
    public struct EventValue: Codable, Sendable {
        public let messageCreate: MessageCreate
        
        enum CodingKeys: String, CodingKey {
            case messageCreate = "com.linkedin.voyager.messaging.create.MessageCreate"
        }
    }
    
    public struct MessageCreate: Codable, Sendable {
        public let attributedBody: AttributedBody
    }
    
    public struct AttributedBody: Codable, Sendable {
        public let text: String
    }
}

