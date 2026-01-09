import XCTest
@testable import LinkedInKit

final class LinkedInKitTests: XCTestCase {
    
    func testExtractUsername() {
        // Full URLs
        XCTAssertEqual(extractUsername(from: "https://www.linkedin.com/in/johndoe/"), "johndoe")
        XCTAssertEqual(extractUsername(from: "https://linkedin.com/in/johndoe"), "johndoe")
        XCTAssertEqual(extractUsername(from: "http://www.linkedin.com/in/john-doe-123"), "john-doe-123")
        
        // Just username
        XCTAssertEqual(extractUsername(from: "johndoe"), "johndoe")
        XCTAssertEqual(extractUsername(from: "john-doe-123"), "john-doe-123")
        
        // Invalid
        XCTAssertNil(extractUsername(from: "https://linkedin.com/company/microsoft"))
    }
    
    func testExtractCompanyName() {
        // Full URLs
        XCTAssertEqual(extractCompanyName(from: "https://www.linkedin.com/company/microsoft/"), "microsoft")
        XCTAssertEqual(extractCompanyName(from: "https://linkedin.com/company/open-ai"), "open-ai")
        
        // Just company name
        XCTAssertEqual(extractCompanyName(from: "microsoft"), "microsoft")
        XCTAssertEqual(extractCompanyName(from: "open-ai"), "open-ai")
    }
    
    func testExtractJobId() {
        // Full URLs
        XCTAssertEqual(extractJobId(from: "https://www.linkedin.com/jobs/view/1234567890/"), "1234567890")
        XCTAssertEqual(extractJobId(from: "https://linkedin.com/jobs/view/9876543210"), "9876543210")
        
        // Just ID
        XCTAssertEqual(extractJobId(from: "1234567890"), "1234567890")
        
        // Invalid
        XCTAssertNil(extractJobId(from: "not-a-number"))
    }
    
    func testCredentialStore() throws {
        let store = CredentialStore()
        let testCookie = "test-cookie-value-\(UUID().uuidString)"
        
        // Clean up first
        try? store.deleteCookie()
        
        // Initially no cookie
        XCTAssertFalse(store.hasCookie())
        
        // Save cookie
        try store.saveCookie(testCookie)
        XCTAssertTrue(store.hasCookie())
        
        // Load cookie
        let loaded = try store.loadCookie()
        XCTAssertEqual(loaded, testCookie)
        
        // Test li_at= prefix handling
        try store.saveCookie("li_at=\(testCookie)")
        let loadedWithPrefix = try store.loadCookie()
        XCTAssertEqual(loadedWithPrefix, testCookie)
        
        // Delete
        try store.deleteCookie()
        XCTAssertFalse(store.hasCookie())
    }
    
    func testClientInit() async {
        let client = LinkedInClient()
        let isAuth = await client.isAuthenticated
        XCTAssertFalse(isAuth)
        
        await client.configure(cookie: "test-cookie")
        let isAuthAfter = await client.isAuthenticated
        XCTAssertTrue(isAuthAfter)
    }
    
    func testExperienceEncoding() throws {
        let experience = Experience(
            title: "Software Engineer",
            company: "Tech Corp",
            location: "San Francisco, CA",
            startDate: "Jan 2020",
            endDate: "Present",
            duration: "4 years"
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(experience)
        let json = String(data: data, encoding: .utf8)!
        
        XCTAssertTrue(json.contains("Software Engineer"))
        XCTAssertTrue(json.contains("Tech Corp"))
    }
    
    func testPersonProfileEncoding() throws {
        let profile = PersonProfile(
            username: "johndoe",
            name: "John Doe",
            headline: "Software Engineer at Tech Corp",
            location: "San Francisco Bay Area",
            company: "Tech Corp",
            jobTitle: "Software Engineer",
            experiences: [
                Experience(title: "Engineer", company: "Tech Corp")
            ],
            educations: [
                Education(institution: "MIT", degree: "BS Computer Science")
            ],
            skills: ["Swift", "Python", "Rust"],
            openToWork: true
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        let json = String(data: data, encoding: .utf8)!
        
        XCTAssertTrue(json.contains("John Doe"))
        XCTAssertTrue(json.contains("johndoe"))
        XCTAssertTrue(json.contains("Swift"))
        XCTAssertTrue(json.contains("openToWork"))
    }
    
    func testJobListingEncoding() throws {
        let job = JobListing(
            id: "1234567890",
            title: "Senior Swift Developer",
            company: "Apple",
            location: "Cupertino, CA",
            postedDate: "1 week ago",
            salary: "$150,000 - $200,000",
            isEasyApply: true,
            jobURL: "https://linkedin.com/jobs/view/1234567890/"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(job)
        let json = String(data: data, encoding: .utf8)!
        
        XCTAssertTrue(json.contains("1234567890"))
        XCTAssertTrue(json.contains("Apple"))
        XCTAssertTrue(json.contains("Cupertino"))
    }
    
    func testCompanyProfileEncoding() throws {
        let company = CompanyProfile(
            name: "Anthropic",
            slug: "anthropic",
            tagline: "AI safety research company",
            about: "We build safe, beneficial AI",
            website: "https://anthropic.com",
            industry: "Artificial Intelligence",
            companySize: "201-500 employees",
            headquarters: "San Francisco, CA",
            founded: "2021",
            specialties: ["AI Safety", "Machine Learning", "Research"],
            employeeCount: "300+",
            followerCount: "50,000"
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(company)
        let json = String(data: data, encoding: .utf8)!
        
        XCTAssertTrue(json.contains("Anthropic"))
        XCTAssertTrue(json.contains("anthropic"))
        XCTAssertTrue(json.contains("AI Safety"))
    }
}
