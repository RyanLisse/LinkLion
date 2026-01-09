// LinkedInKit - Swift library for LinkedIn scraping
//
// Provides programmatic access to LinkedIn data including:
// - Person profiles
// - Company profiles
// - Job search and details

@_exported import Foundation

/// LinkedInKit version
public let version = "1.0.0"

/// Create a configured LinkedIn client
/// - Parameter cookie: Optional li_at cookie (can be configured later)
/// - Returns: A configured LinkedInClient
public func createClient(cookie: String? = nil) async -> LinkedInClient {
    let client = LinkedInClient()
    if let cookie = cookie {
        await client.configure(cookie: cookie)
    }
    return client
}

/// Helper to extract username from LinkedIn profile URL
public func extractUsername(from url: String) -> String? {
    // Handle various LinkedIn URL formats
    let patterns = [
        #"linkedin\.com/in/([a-zA-Z0-9\-_]+)"#,
        #"^([a-zA-Z0-9\-_]+)$"#, // Just the username
    ]
    
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(url.startIndex..., in: url)
            if let match = regex.firstMatch(in: url, options: [], range: range),
               let captureRange = Range(match.range(at: 1), in: url) {
                return String(url[captureRange])
            }
        }
    }
    
    return nil
}

/// Helper to extract company name from LinkedIn company URL
public func extractCompanyName(from url: String) -> String? {
    let patterns = [
        #"linkedin\.com/company/([a-zA-Z0-9\-_]+)"#,
        #"^([a-zA-Z0-9\-_]+)$"#, // Just the company name
    ]
    
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(url.startIndex..., in: url)
            if let match = regex.firstMatch(in: url, options: [], range: range),
               let captureRange = Range(match.range(at: 1), in: url) {
                return String(url[captureRange])
            }
        }
    }
    
    return nil
}

/// Helper to extract job ID from LinkedIn job URL
public func extractJobId(from url: String) -> String? {
    let patterns = [
        #"linkedin\.com/jobs/view/(\d+)"#,
        #"^(\d+)$"#, // Just the job ID
    ]
    
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(url.startIndex..., in: url)
            if let match = regex.firstMatch(in: url, options: [], range: range),
               let captureRange = Range(match.range(at: 1), in: url) {
                return String(url[captureRange])
            }
        }
    }
    
    return nil
}
