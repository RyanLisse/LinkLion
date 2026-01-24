import Foundation
import Logging

/// Gemini Vision client for analyzing screenshots
public actor GeminiVision {
    private let apiKey: String
    private let logger = Logger(label: "LinkedInKit.GeminiVision")
    private let model = "gemini-2.0-flash"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    
    public init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    }
    
    /// Analyze a screenshot and extract LinkedIn profile data
    public func analyzeProfile(imagePath: String) async throws -> ProfileAnalysis {
        guard !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }
        
        // Resize image if too large (max 800px width for faster processing)
        let resizedPath = try await resizeImageIfNeeded(imagePath)
        
        // Read image and convert to base64
        let imageURL = URL(fileURLWithPath: resizedPath)
        let imageData = try Data(contentsOf: imageURL)
        let base64Image = imageData.base64EncodedString()
        
        logger.info("Image size: \(imageData.count / 1024)KB, base64: \(base64Image.count / 1024)KB")
        
        // Determine mime type
        let mimeType = imagePath.hasSuffix(".png") ? "image/png" : "image/jpeg"
        
        let prompt = """
        Analyze this LinkedIn profile screenshot and extract the following information as JSON:
        
        {
            "name": "Full name of the person",
            "headline": "Professional headline/title",
            "location": "City, Country",
            "about": "About/summary section (if visible)",
            "company": "Current company name",
            "jobTitle": "Current job title",
            "connectionCount": "Number of connections (e.g., '500+')",
            "followerCount": "Number of followers",
            "openToWork": true/false,
            "experiences": [
                {
                    "title": "Job title",
                    "company": "Company name",
                    "duration": "Duration (e.g., '2020 - Present')",
                    "location": "Location if shown"
                }
            ],
            "educations": [
                {
                    "institution": "School/University name",
                    "degree": "Degree name",
                    "years": "Years attended"
                }
            ],
            "skills": ["skill1", "skill2", "skill3"]
        }
        
        Only include fields that are clearly visible in the screenshot.
        Return ONLY the JSON object, no markdown or explanation.
        """
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": mimeType,
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 2048
            ]
        ]
        
        let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        logger.info("Analyzing screenshot with Gemini Vision...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(httpResponse.statusCode, errorBody)
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.parseError("Failed to parse Gemini response")
        }
        
        // Clean up the response (remove markdown code blocks if present)
        let cleanedText = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse the JSON response
        guard let profileData = cleanedText.data(using: .utf8),
              let profileJson = try JSONSerialization.jsonObject(with: profileData) as? [String: Any] else {
            throw GeminiError.parseError("Failed to parse profile JSON: \(cleanedText)")
        }
        
        return ProfileAnalysis(
            name: profileJson["name"] as? String,
            headline: profileJson["headline"] as? String,
            location: profileJson["location"] as? String,
            about: profileJson["about"] as? String,
            company: profileJson["company"] as? String,
            jobTitle: profileJson["jobTitle"] as? String,
            connectionCount: profileJson["connectionCount"] as? String,
            followerCount: profileJson["followerCount"] as? String,
            openToWork: profileJson["openToWork"] as? Bool ?? false,
            experiences: parseExperiences(profileJson["experiences"]),
            educations: parseEducations(profileJson["educations"]),
            skills: profileJson["skills"] as? [String] ?? []
        )
    }
    
    private func parseExperiences(_ data: Any?) -> [ExperienceAnalysis] {
        guard let experiences = data as? [[String: Any]] else { return [] }
        return experiences.compactMap { exp in
            ExperienceAnalysis(
                title: exp["title"] as? String ?? "",
                company: exp["company"] as? String ?? "",
                duration: exp["duration"] as? String,
                location: exp["location"] as? String
            )
        }
    }
    
    private func parseEducations(_ data: Any?) -> [EducationAnalysis] {
        guard let educations = data as? [[String: Any]] else { return [] }
        return educations.compactMap { edu in
            EducationAnalysis(
                institution: edu["institution"] as? String ?? "",
                degree: edu["degree"] as? String,
                years: edu["years"] as? String
            )
        }
    }
}

// MARK: - Models

public struct ProfileAnalysis: Sendable {
    public let name: String?
    public let headline: String?
    public let location: String?
    public let about: String?
    public let company: String?
    public let jobTitle: String?
    public let connectionCount: String?
    public let followerCount: String?
    public let openToWork: Bool
    public let experiences: [ExperienceAnalysis]
    public let educations: [EducationAnalysis]
    public let skills: [String]
}

public struct ExperienceAnalysis: Sendable {
    public let title: String
    public let company: String
    public let duration: String?
    public let location: String?
}

public struct EducationAnalysis: Sendable {
    public let institution: String
    public let degree: String?
    public let years: String?
}

// MARK: - Image Processing

extension GeminiVision {
    /// Resize image if larger than maxWidth pixels
    private func resizeImageIfNeeded(_ path: String, maxWidth: Int = 2000) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        
        let outputPath = "/tmp/linkedin_resized_\(UUID().uuidString).png"
        process.arguments = ["-Z", String(maxWidth), path, "--out", outputPath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            return outputPath
        } else {
            // If resize fails, return original
            return path
        }
    }
}

public enum GeminiError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(Int, String)
    case parseError(String)
    
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "GEMINI_API_KEY environment variable not set"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .apiError(let code, let message):
            return "Gemini API error (\(code)): \(message)"
        case .parseError(let message):
            return "Failed to parse response: \(message)"
        }
    }
}
