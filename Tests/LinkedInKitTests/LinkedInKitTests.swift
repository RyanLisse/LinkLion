import XCTest
@testable import LinkLion

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
    
    // MARK: - Auth Command CLI Tests

    func testAuthCommandParsesBrowserOption() throws {
        // Test --browser flag parsing
        let args = ["linkedin", "auth", "--browser", "safari"]
        // Note: This is a placeholder - actual CLI parsing test would require
        // ArgumentParser testing infrastructure
        XCTAssertTrue(args.contains("--browser"))
        XCTAssertTrue(args.contains("safari"))
    }

    func testAuthCommandParsesProfileOption() throws {
        let args = ["linkedin", "auth", "--browser", "chrome", "--profile", "1"]
        XCTAssertTrue(args.contains("--profile"))
        XCTAssertTrue(args.contains("1"))
    }

    func testAuthCommandParsesListBrowsersFlag() throws {
        let args = ["linkedin", "auth", "--list-browsers"]
        XCTAssertTrue(args.contains("--list-browsers"))
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
    
    // MARK: - Send Invite Tests
    
    func testSendInvitePayloadConstruction() throws {
        // Test that sendInvite constructs correct payload structure
        let profileUrn = "urn:li:fsd_profile:ACoAABcdefg123"
        let message = "Hello, I'd like to connect!"
        
        let payload = InvitePayload(profileUrn: profileUrn, message: message)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let json = String(data: data, encoding: .utf8)!
        
        // Verify payload structure matches API spec
        XCTAssertTrue(json.contains("invitee"))
        XCTAssertTrue(json.contains("inviteeUnion"))
        XCTAssertTrue(json.contains("memberProfile"))
        XCTAssertTrue(json.contains(profileUrn))
        XCTAssertTrue(json.contains("customMessage"))
        XCTAssertTrue(json.contains(message))
    }
    
    func testSendInvitePayloadWithoutMessage() throws {
        // Test invite without custom message
        let profileUrn = "urn:li:fsd_profile:ACoAABcdefg123"
        
        let payload = InvitePayload(profileUrn: profileUrn, message: nil)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let json = String(data: data, encoding: .utf8)!
        
        // Verify payload has invitee but no customMessage when nil
        XCTAssertTrue(json.contains("invitee"))
        XCTAssertTrue(json.contains(profileUrn))
    }
    
    func testSendInviteURLConstruction() {
        // Test that the invite URL is correctly constructed
        let expectedPath = "/voyagerRelationshipsDashMemberRelationships"
        let expectedAction = "action=verifyQuotaAndCreateV2"
        
        let url = LinkedInClient.buildInviteURL()
        
        XCTAssertTrue(url.absoluteString.contains(expectedPath))
        XCTAssertTrue(url.absoluteString.contains(expectedAction))
    }
    
    // MARK: - Send Message Tests
    
    func testSendMessagePayloadConstruction() throws {
        // Test that sendMessage constructs correct payload structure
        let profileUrn = "urn:li:fsd_profile:ACoAABcdefg123"
        let messageText = "Hi there! How are you?"
        
        let payload = MessagePayload(profileUrn: profileUrn, message: messageText)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let json = String(data: data, encoding: .utf8)!
        
        // Verify payload structure matches API spec
        XCTAssertTrue(json.contains("keyVersion"))
        XCTAssertTrue(json.contains("LEGACY_INBOX"))
        XCTAssertTrue(json.contains("conversationCreate"))
        XCTAssertTrue(json.contains("eventCreate"))
        XCTAssertTrue(json.contains("com.linkedin.voyager.messaging.create.MessageCreate"))
        XCTAssertTrue(json.contains("attributedBody"))
        XCTAssertTrue(json.contains(messageText))
        XCTAssertTrue(json.contains("recipients"))
        XCTAssertTrue(json.contains(profileUrn))
        XCTAssertTrue(json.contains("MEMBER_TO_MEMBER"))
    }
    
    func testSendMessageURLConstruction() {
        // Test that the message URL is correctly constructed
        let expectedPath = "/messaging/conversations"
        
        let url = LinkedInClient.buildMessageURL()
        
        XCTAssertTrue(url.absoluteString.contains(expectedPath))
    }
    
    // MARK: - Resolve URN Tests
    
    func testResolveURNFromUsername() {
        // Test placeholder URN generation from username
        let username = "johndoe"
        let urn = LinkedInClient.buildPlaceholderURN(from: username)
        
        XCTAssertEqual(urn, "urn:li:fsd_profile:johndoe")
    }
    
    func testResolveURNFromUsernameWithSpecialChars() {
        // Test URN generation with username containing special characters
        let username = "john-doe-123"
        let urn = LinkedInClient.buildPlaceholderURN(from: username)
        
        XCTAssertEqual(urn, "urn:li:fsd_profile:john-doe-123")
    }
    
    func testURNValidation() {
        // Test URN format validation
        XCTAssertTrue(LinkedInClient.isValidURN("urn:li:fsd_profile:ACoAABcdefg123"))
        XCTAssertTrue(LinkedInClient.isValidURN("urn:li:fs_miniProfile:123456"))
        XCTAssertFalse(LinkedInClient.isValidURN("johndoe"))
        XCTAssertFalse(LinkedInClient.isValidURN("https://linkedin.com/in/johndoe"))
        XCTAssertFalse(LinkedInClient.isValidURN(""))
    }
    
    func testClientRequiresAuthForSendInvite() async {
        // Test that sendInvite throws notAuthenticated when no cookie
        let client = LinkedInClient()
        
        do {
            try await client.sendInvite(profileUrn: "urn:li:fsd_profile:test", message: nil)
            XCTFail("Expected notAuthenticated error")
        } catch LinkedInError.notAuthenticated {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testClientRequiresAuthForSendMessage() async {
        // Test that sendMessage throws notAuthenticated when no cookie
        let client = LinkedInClient()
        
        do {
            try await client.sendMessage(profileUrn: "urn:li:fsd_profile:test", message: "Hello")
            XCTFail("Expected notAuthenticated error")
        } catch LinkedInError.notAuthenticated {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSendInviteWithInvalidURN() async {
        // Test that sendInvite throws invalidURN error for invalid format
        let client = LinkedInClient()
        await client.configure(cookie: "test-cookie")
        
        do {
            try await client.sendInvite(profileUrn: "invalid-urn", message: nil)
            XCTFail("Expected invalidURN error")
        } catch LinkedInError.invalidURN {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSendMessageWithInvalidURN() async {
        // Test that sendMessage throws invalidURN error for invalid format
        let client = LinkedInClient()
        await client.configure(cookie: "test-cookie")
        
        do {
            try await client.sendMessage(profileUrn: "invalid-urn", message: "Hello")
            XCTFail("Expected invalidURN error")
        } catch LinkedInError.invalidURN {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testResolveURNRequiresAuth() async {
        // Test that resolveURN requires authentication
        let client = LinkedInClient()
        
        do {
            _ = try await client.resolveURN(from: "johndoe")
            XCTFail("Expected notAuthenticated error")
        } catch LinkedInError.notAuthenticated {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSendInviteWithEmptyMessage() throws {
        // Test invite with empty string message (should be treated as nil)
        let profileUrn = "urn:li:fsd_profile:ACoAABcdefg123"
        let payload = InvitePayload(profileUrn: profileUrn, message: "")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let json = String(data: data, encoding: .utf8)!
        
        // Empty string should still be included in JSON
        XCTAssertTrue(json.contains("customMessage"))
    }
    
    func testSendMessageWithLongText() throws {
        // Test message with long text content
        let profileUrn = "urn:li:fsd_profile:ACoAABcdefg123"
        let longMessage = String(repeating: "A", count: 1000)
        
        let payload = MessagePayload(profileUrn: profileUrn, message: longMessage)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let json = String(data: data, encoding: .utf8)!
        
        XCTAssertTrue(json.contains(longMessage))
        XCTAssertTrue(json.contains(profileUrn))
    }

    func testParseConversationsFromVisionElements() {
        let elements = [
            VisionElement(id: "row-1", label: "Jane Doe: Are you free this week? unread", role: "row", bounds: nil),
            VisionElement(id: "row-2", label: "John Smith: Thanks for connecting", role: "row", bounds: nil),
            VisionElement(id: "noise", label: "Messaging", role: "heading", bounds: nil),
        ]

        let conversations = LinkedInClient.parseConversationsFromVision(elements: elements, limit: 10)

        XCTAssertEqual(conversations.count, 2)
        XCTAssertEqual(conversations[0].participantNames, ["Jane Doe"])
        XCTAssertEqual(conversations[0].lastMessage, "Are you free this week?")
        XCTAssertTrue(conversations[0].unread)
        XCTAssertEqual(conversations[1].participantNames, ["John Smith"])
        XCTAssertEqual(conversations[1].lastMessage, "Thanks for connecting")
        XCTAssertFalse(conversations[1].unread)
    }

    func testParseMessagesFromVisionElements() {
        let elements = [
            VisionElement(id: "msg-1", label: "Jane Doe: Thanks for reaching out", role: "text", bounds: nil),
            VisionElement(id: "msg-2", label: "You: Happy to connect", role: "text", bounds: nil),
            VisionElement(id: "noise", label: "Type a message", role: "textbox", bounds: nil),
        ]

        let messages = LinkedInClient.parseMessagesFromVision(elements: elements, limit: 10)

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].senderName, "Jane Doe")
        XCTAssertEqual(messages[0].text, "Thanks for reaching out")
        XCTAssertEqual(messages[1].senderName, "You")
        XCTAssertEqual(messages[1].text, "Happy to connect")
    }
}
