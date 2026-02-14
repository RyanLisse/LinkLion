import Foundation
import SweetCookieKit

// MARK: - Supported Browser Enum

/// Browsers supported for automatic cookie extraction
public enum SupportedBrowser: String, CaseIterable, Sendable {
    case safari = "safari"
    case chrome = "chrome"
    case edge = "edge"
    case firefox = "firefox"

    /// Map to SweetCookieKit's Browser enum
    var sweetCookieBrowser: Browser {
        switch self {
        case .safari:
            return .safari
        case .chrome:
            return .chrome
        case .edge:
            return .edge
        case .firefox:
            return .firefox
        }
    }

    /// Human-readable browser name
    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Browser Cookie Errors

/// Errors that can occur during browser cookie extraction
public enum BrowserCookieError: Error, LocalizedError, Sendable {
    case noCookieFound(browser: String)
    case unsupportedBrowser(String)
    case permissionDenied(browser: String, reason: String)
    case profileNotFound(browser: String, profileIndex: Int)
    case extractionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noCookieFound(let browser):
            return "No LinkedIn cookie (li_at) found in \(browser)"
        case .unsupportedBrowser(let browser):
            return "Browser '\(browser)' is not supported for automatic cookie extraction"
        case .permissionDenied(let browser, let reason):
            return "Permission denied while accessing \(browser) cookies: \(reason)"
        case .profileNotFound(let browser, let index):
            return "\(browser) profile at index \(index) not found"
        case .extractionFailed(let reason):
            return "Cookie extraction failed: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noCookieFound:
            return "Make sure you're logged into LinkedIn in your browser, then try again."
        case .unsupportedBrowser(let browser):
            let supported = SupportedBrowser.allCases.map { $0.rawValue }.joined(separator: ", ")
            return "Please use one of these browsers: \(supported). Current browser: \(browser)"
        case .permissionDenied(let browser, let reason):
            if reason.contains("Full Disk Access") {
                return "Grant Full Disk Access to Terminal:\n1. Open System Settings → Privacy & Security → Full Disk Access\n2. Enable Terminal or your terminal app\n3. Restart terminal and try again"
            } else if reason.contains("Keychain") || browser.lowercased().contains("chrome") {
                return "Allow Keychain access when prompted. This is needed to decrypt \(browser) cookies."
            }
            return "Check macOS privacy settings and grant necessary permissions."
        case .profileNotFound(let browser, _):
            return "Use --list-browsers to see available \(browser) profiles and their indices."
        case .extractionFailed:
            return "Try manual authentication with: linkedin auth YOUR_COOKIE_VALUE"
        }
    }
}

// MARK: - Browser Cookie Extractor

/// Handles extraction of LinkedIn cookies from various browsers
public struct BrowserCookieExtractor: Sendable {
    private let client: BrowserCookieClient

    public init() {
        self.client = BrowserCookieClient()
    }

    // MARK: - Public API

    /// Extract LinkedIn cookie from a specific browser
    /// - Parameters:
    ///   - browser: The browser to extract from
    ///   - profileIndex: Browser profile index (default: 0 for main profile)
    /// - Returns: The li_at cookie value (without "li_at=" prefix)
    /// - Throws: BrowserCookieError if extraction fails
    public func extractLinkedInCookie(
        from browser: SupportedBrowser,
        profileIndex: Int = 0
    ) async throws -> String {
        // Get stores for this browser
        let stores = client.stores(for: browser.sweetCookieBrowser)

        // Validate profile index
        guard profileIndex < stores.count else {
            throw BrowserCookieError.profileNotFound(
                browser: browser.displayName,
                profileIndex: profileIndex
            )
        }

        do {
            // Query for LinkedIn cookies
            let query = BrowserCookieQuery(
                domains: [".linkedin.com", "linkedin.com"],
                domainMatch: .suffix,
                includeExpired: false
            )

            let storeRecords = try client.records(
                matching: query,
                in: browser.sweetCookieBrowser
            )

            // Filter by profile index if multiple stores
            let targetStore = stores[profileIndex]
            guard let records = storeRecords.first(where: { $0.store.profile.id == targetStore.profile.id }) else {
                throw BrowserCookieError.noCookieFound(browser: browser.displayName)
            }

            // Find li_at cookie
            guard let liAtCookie = records.records.first(where: { $0.name == "li_at" }) else {
                throw BrowserCookieError.noCookieFound(browser: browser.displayName)
            }

            // Return clean cookie value (no prefix)
            let cookieValue = liAtCookie.value
            return cookieValue.hasPrefix("li_at=") ? String(cookieValue.dropFirst(6)) : cookieValue

        } catch let error as BrowserCookieError {
            throw error
        } catch {
            // Handle SweetCookieKit errors
            let errorMessage = error.localizedDescription

            // Detect permission errors
            if errorMessage.contains("Full Disk Access") ||
               errorMessage.contains("Operation not permitted") {
                throw BrowserCookieError.permissionDenied(
                    browser: browser.displayName,
                    reason: "Full Disk Access required"
                )
            } else if errorMessage.contains("Keychain") ||
                      errorMessage.contains("password") ||
                      errorMessage.contains("authorization") {
                throw BrowserCookieError.permissionDenied(
                    browser: browser.displayName,
                    reason: "Keychain access denied"
                )
            } else if errorMessage.contains("not found") ||
                      errorMessage.contains("does not exist") {
                throw BrowserCookieError.noCookieFound(browser: browser.displayName)
            }

            throw BrowserCookieError.extractionFailed(errorMessage)
        }
    }

    /// Extract LinkedIn cookie from a browser specified by name string
    /// - Parameters:
    ///   - browserName: Browser name as string (e.g., "safari", "chrome")
    ///   - profileIndex: Browser profile index (default: 0)
    /// - Returns: The li_at cookie value
    /// - Throws: BrowserCookieError if browser unsupported or extraction fails
    public func extractLinkedInCookie(
        browserName: String,
        profileIndex: Int = 0
    ) async throws -> String {
        guard let browser = SupportedBrowser(rawValue: browserName.lowercased()) else {
            throw BrowserCookieError.unsupportedBrowser(browserName)
        }
        return try await extractLinkedInCookie(from: browser, profileIndex: profileIndex)
    }

    // MARK: - Browser Discovery

    /// List available browsers on the system
    /// - Returns: Array of browser names (capitalized)
    public func listAvailableBrowsers() -> [String] {
        var available: [String] = []

        for browser in SupportedBrowser.allCases {
            let stores = client.stores(for: browser.sweetCookieBrowser)
            if !stores.isEmpty {
                available.append(browser.displayName)
            }
        }

        return available
    }

    /// List available profiles for a specific browser
    /// - Parameter browser: The browser to check
    /// - Returns: Array of profile names
    public func listProfiles(for browser: SupportedBrowser) -> [String] {
        let stores = client.stores(for: browser.sweetCookieBrowser)
        return stores.map { $0.profile.name }
    }
}
