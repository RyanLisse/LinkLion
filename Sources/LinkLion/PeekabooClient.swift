import Foundation
import Logging

/// Client for browser automation via Peekaboo CLI
/// Used as fallback when API scraping fails or for richer data extraction
public actor PeekabooClient {
    private let logger = Logger(label: "LinkedInKit.Peekaboo")
    private let peekabooPath: String
    private let browser: String
    
    public init(peekabooPath: String = "/opt/homebrew/bin/peekaboo", browser: String = "Safari") {
        self.peekabooPath = peekabooPath
        self.browser = browser
    }
    
    // MARK: - Screenshot & Vision
    
    /// Capture screenshot of current screen (or browser window)
    public func captureScreen(saveTo path: String? = nil) async throws -> ScreenCapture {
        let outputPath = path ?? "/tmp/linkedin_capture_\(UUID().uuidString).png"
        
        // Try app-specific capture first, fall back to screen capture
        var result = try await runPeekaboo([
            "image",
            "--app", browser,
            "--path", outputPath
        ])
        
        // If app capture fails, try screen capture
        if result.exitCode != 0 {
            logger.info("App capture failed, trying screen capture...")
            result = try await runPeekaboo([
                "image",
                "--mode", "screen",
                "--path", outputPath
            ])
        }
        
        guard result.exitCode == 0 else {
            throw PeekabooError.captureFailed(result.stderr)
        }
        
        return ScreenCapture(path: outputPath, timestamp: Date())
    }
    
    /// Capture with element detection (returns snapshot ID for clicking)
    public func see(app: String? = nil) async throws -> VisionResult {
        var args = ["see", "--app", app ?? browser, "--json-output"]
        
        let result = try await runPeekaboo(args)
        
        guard result.exitCode == 0 else {
            throw PeekabooError.captureFailed(result.stderr)
        }
        
        // Parse JSON output
        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultData = json["data"] as? [String: Any] else {
            throw PeekabooError.parseError("Failed to parse vision result")
        }
        
        let snapshotId = resultData["snapshot_id"] as? String ?? ""
        let elements = (resultData["elements"] as? [[String: Any]])?.compactMap { elem -> VisionElement? in
            guard let id = elem["id"] as? String,
                  let label = elem["label"] as? String else { return nil }
            return VisionElement(
                id: id,
                label: label,
                role: elem["role"] as? String,
                bounds: elem["bounds"] as? [String: Double]
            )
        } ?? []
        
        return VisionResult(snapshotId: snapshotId, elements: elements)
    }
    
    // MARK: - Interactions
    
    /// Click on an element by ID or label
    public func click(on target: String, snapshotId: String? = nil) async throws {
        var args = ["click", "--on", target]
        if let snapshot = snapshotId {
            args += ["--snapshot", snapshot]
        }
        
        let result = try await runPeekaboo(args)
        
        guard result.exitCode == 0 else {
            throw PeekabooError.actionFailed("click", result.stderr)
        }
        
        // Wait for page to settle
        try await Task.sleep(for: .milliseconds(500))
    }
    
    /// Scroll in a direction
    public func scroll(direction: ScrollDirection, ticks: Int = 3) async throws {
        let result = try await runPeekaboo([
            "scroll",
            "--direction", direction.rawValue,
            "--ticks", String(ticks)
        ])
        
        guard result.exitCode == 0 else {
            throw PeekabooError.actionFailed("scroll", result.stderr)
        }
        
        try await Task.sleep(for: .milliseconds(300))
    }
    
    /// Type text
    public func type(text: String) async throws {
        let result = try await runPeekaboo([
            "type",
            text
        ])
        
        guard result.exitCode == 0 else {
            throw PeekabooError.actionFailed("type", result.stderr)
        }
    }
    
    /// Press a key or hotkey
    public func hotkey(_ keys: String) async throws {
        let result = try await runPeekaboo([
            "hotkey", keys
        ])
        
        guard result.exitCode == 0 else {
            throw PeekabooError.actionFailed("hotkey", result.stderr)
        }
    }
    
    // MARK: - LinkedIn Specific
    
    /// Navigate to a LinkedIn profile
    public func navigateToProfile(username: String) async throws {
        let url = "https://www.linkedin.com/in/\(username)/"
        
        // Use hotkey to open URL (Cmd+L to focus address bar, then type URL)
        try await hotkey("cmd,l")
        try await Task.sleep(for: .milliseconds(200))
        try await type(text: url)
        try await hotkey("return")
        
        // Wait for page load
        try await Task.sleep(for: .seconds(2))
    }
    
    /// Scrape profile using vision
    /// Assumes Safari is already open on the LinkedIn profile
    public func scrapeProfile(username: String) async throws -> ScrapedProfile {
        logger.info("Scraping profile via Peekaboo: \(username)")
        
        // Just capture current screen - assume user has profile open
        let capture1 = try await captureScreen()
        
        return ScrapedProfile(
            username: username,
            screenshots: [capture1.path],
            capturedAt: Date()
        )
    }
    
    /// Extract text from LinkedIn page using vision AI
    /// Returns placeholder - AI analysis should be done by caller with screenshot
    public func extractWithVision(prompt: String) async throws -> String {
        // For now, return a placeholder JSON
        // Real implementation would use an AI vision API
        return """
        {
            "name": "Profile captured via Peekaboo",
            "headline": "See screenshot for details",
            "note": "AI vision analysis not yet implemented - screenshot saved"
        }
        """
    }
    
    // MARK: - Private Helpers
    
    private func runPeekaboo(_ args: [String]) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: peekabooPath)
        process.arguments = args
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        logger.debug("Running: peekaboo \(args.joined(separator: " "))")
        
        try process.run()
        process.waitUntilExit()
        
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        
        return ProcessResult(
            exitCode: Int(process.terminationStatus),
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}

// MARK: - Models

public struct ScreenCapture: Sendable {
    public let path: String
    public let timestamp: Date
}

public struct VisionResult: Sendable {
    public let snapshotId: String
    public let elements: [VisionElement]
}

public struct VisionElement: Sendable {
    public let id: String
    public let label: String
    public let role: String?
    public let bounds: [String: Double]?
}

public struct ScrapedProfile: Sendable {
    public let username: String
    public let screenshots: [String]
    public let capturedAt: Date
}

public struct ProcessResult: Sendable {
    public let exitCode: Int
    public let stdout: String
    public let stderr: String
}

public enum ScrollDirection: String, Sendable {
    case up, down, left, right
}

public enum PeekabooError: Error, LocalizedError {
    case captureFailed(String)
    case actionFailed(String, String)
    case parseError(String)
    case permissionDenied
    
    public var errorDescription: String? {
        switch self {
        case .captureFailed(let msg): return "Screenshot failed: \(msg)"
        case .actionFailed(let action, let msg): return "\(action) failed: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .permissionDenied: return "Screen Recording permission required"
        }
    }
}
