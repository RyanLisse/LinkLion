import XCTest
@testable import LinkedInCLI

final class BrowserCookieExtractorTests: XCTestCase {

    // MARK: - Browser Enum Tests

    func testSupportedBrowserMapping() {
        // Test that each supported browser maps to correct SweetCookieKit browser
        XCTAssertNotNil(SupportedBrowser.safari.sweetCookieBrowser)
        XCTAssertNotNil(SupportedBrowser.chrome.sweetCookieBrowser)
        XCTAssertNotNil(SupportedBrowser.edge.sweetCookieBrowser)
        XCTAssertNotNil(SupportedBrowser.firefox.sweetCookieBrowser)
    }

    func testSupportedBrowserRawValues() {
        XCTAssertEqual(SupportedBrowser.safari.rawValue, "safari")
        XCTAssertEqual(SupportedBrowser.chrome.rawValue, "chrome")
        XCTAssertEqual(SupportedBrowser.edge.rawValue, "edge")
        XCTAssertEqual(SupportedBrowser.firefox.rawValue, "firefox")
    }

    func testSupportedBrowserFromString() {
        XCTAssertEqual(SupportedBrowser(rawValue: "safari"), .safari)
        XCTAssertEqual(SupportedBrowser(rawValue: "chrome"), .chrome)
        XCTAssertEqual(SupportedBrowser(rawValue: "edge"), .edge)
        XCTAssertEqual(SupportedBrowser(rawValue: "firefox"), .firefox)
        XCTAssertNil(SupportedBrowser(rawValue: "opera"))
        XCTAssertNil(SupportedBrowser(rawValue: "brave"))
    }

    func testSupportedBrowserAllCases() {
        let browsers = SupportedBrowser.allCases
        XCTAssertEqual(browsers.count, 4)
        XCTAssertTrue(browsers.contains(.safari))
        XCTAssertTrue(browsers.contains(.chrome))
        XCTAssertTrue(browsers.contains(.edge))
        XCTAssertTrue(browsers.contains(.firefox))
    }

    // MARK: - Error Tests

    func testBrowserCookieErrorDescriptions() {
        let noCookieError = BrowserCookieError.noCookieFound(browser: "Safari")
        XCTAssertTrue(noCookieError.errorDescription?.contains("Safari") ?? false)
        XCTAssertTrue(noCookieError.errorDescription?.contains("li_at") ?? false)

        let unsupportedError = BrowserCookieError.unsupportedBrowser("Opera")
        XCTAssertTrue(unsupportedError.errorDescription?.contains("Opera") ?? false)
        XCTAssertTrue(unsupportedError.errorDescription?.contains("not supported") ?? false)

        let permissionError = BrowserCookieError.permissionDenied(browser: "Safari", reason: "Full Disk Access required")
        XCTAssertTrue(permissionError.errorDescription?.contains("Safari") ?? false)
        XCTAssertTrue(permissionError.errorDescription?.contains("Full Disk Access") ?? false)

        let profileError = BrowserCookieError.profileNotFound(browser: "Chrome", profileIndex: 1)
        XCTAssertTrue(profileError.errorDescription?.contains("Chrome") ?? false)
        XCTAssertTrue(profileError.errorDescription?.contains("1") ?? false)

        let extractionError = BrowserCookieError.extractionFailed("Generic error")
        XCTAssertTrue(extractionError.errorDescription?.contains("Generic error") ?? false)
    }

    func testBrowserCookieErrorRecoverySuggestions() {
        let noCookieError = BrowserCookieError.noCookieFound(browser: "Safari")
        XCTAssertNotNil(noCookieError.recoverySuggestion)
        XCTAssertTrue(noCookieError.recoverySuggestion?.contains("logged into") ?? false)

        let permissionError = BrowserCookieError.permissionDenied(browser: "Safari", reason: "Full Disk Access")
        XCTAssertNotNil(permissionError.recoverySuggestion)
        XCTAssertTrue(permissionError.recoverySuggestion?.contains("System Settings") ?? false)
    }

    // MARK: - Extractor Tests

    func testExtractorListAvailableBrowsers() {
        let extractor = BrowserCookieExtractor()
        let browsers = extractor.listAvailableBrowsers()

        // Should return at least one browser on macOS
        XCTAssertFalse(browsers.isEmpty, "At least one browser should be available on macOS")

        // All returned browsers should be supported
        for browser in browsers {
            XCTAssertNotNil(SupportedBrowser(rawValue: browser.lowercased()))
        }
    }

    func testExtractorListProfiles() {
        let extractor = BrowserCookieExtractor()

        // Try to list profiles for available browsers
        for browserStr in extractor.listAvailableBrowsers() {
            guard let browser = SupportedBrowser(rawValue: browserStr.lowercased()) else {
                continue
            }

            let profiles = extractor.listProfiles(for: browser)
            // Should return at least one profile (default)
            XCTAssertFalse(profiles.isEmpty, "\(browser.rawValue) should have at least one profile")
        }
    }

    func testExtractorWithUnsupportedBrowser() async throws {
        let extractor = BrowserCookieExtractor()

        do {
            _ = try await extractor.extractLinkedInCookie(browserName: "opera")
            XCTFail("Should throw unsupportedBrowser error")
        } catch let error as BrowserCookieError {
            if case .unsupportedBrowser(let browser) = error {
                XCTAssertEqual(browser, "opera")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testExtractorWithInvalidProfileIndex() async throws {
        let extractor = BrowserCookieExtractor()
        let availableBrowsers = extractor.listAvailableBrowsers()

        guard let browserStr = availableBrowsers.first,
              let browser = SupportedBrowser(rawValue: browserStr.lowercased()) else {
            throw XCTSkip("No browsers available for testing")
        }

        do {
            _ = try await extractor.extractLinkedInCookie(from: browser, profileIndex: 999)
            XCTFail("Should throw profileNotFound error")
        } catch let error as BrowserCookieError {
            if case .profileNotFound(let browserName, let index) = error {
                XCTAssertEqual(browserName, browser.rawValue.capitalized)
                XCTAssertEqual(index, 999)
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - Integration Tests (Skip if no browsers available)

    func testExtractCookieIntegration() async throws {
        let extractor = BrowserCookieExtractor()
        let availableBrowsers = extractor.listAvailableBrowsers()

        guard let browserStr = availableBrowsers.first,
              let browser = SupportedBrowser(rawValue: browserStr.lowercased()) else {
            throw XCTSkip("No browsers available for testing")
        }

        // This will likely throw noCookieFound unless tester is logged into LinkedIn
        // We're just testing the extraction flow doesn't crash
        do {
            let cookie = try await extractor.extractLinkedInCookie(from: browser)
            XCTAssertFalse(cookie.isEmpty, "Cookie should not be empty if found")
            XCTAssertFalse(cookie.hasPrefix("li_at="), "Cookie should not have li_at= prefix")
        } catch let error as BrowserCookieError {
            // Expected - no LinkedIn cookie in test environment
            if case .noCookieFound = error {
                // This is fine - tester not logged in
            } else {
                throw error
            }
        }
    }
}
