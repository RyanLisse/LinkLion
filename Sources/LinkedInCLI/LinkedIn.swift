import ArgumentParser
import Foundation
import LinkLion

@main
struct LinkedIn: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "linkedin",
        abstract: "LinkedIn CLI - Interact with LinkedIn from the command line",
        version: LinkLion.version,
        subcommands: [
            Auth.self,
            Profile.self,
            Company.self,
            Jobs.self,
            Job.self,
            Post.self,
            Inbox.self,
            Messages.self,
            Status.self,
        ],
        defaultSubcommand: Status.self
    )
}

// MARK: - Global Options

struct GlobalOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "Output in JSON format")
    var json: Bool = false
    
    @Option(name: .long, help: "Override cookie (instead of keychain)")
    var cookie: String?
}

// MARK: - Auth Command

struct Auth: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Authenticate with LinkedIn"
    )

    @Argument(help: "The li_at cookie value from your browser")
    var cookie: String?

    @Flag(name: .shortAndLong, help: "Clear stored authentication")
    var clear: Bool = false

    @Flag(name: .long, help: "Show stored cookie value")
    var show: Bool = false

    @Option(name: .long, help: "Extract cookie from browser (safari, chrome, edge, firefox)")
    var browser: String?

    @Option(name: .long, help: "Browser profile index (default: 0)")
    var profile: Int = 0

    @Flag(name: .long, help: "List available browsers and profiles")
    var listBrowsers: Bool = false

    func run() async throws {
        let store = CredentialStore()

        // Handle --clear flag
        if clear {
            try store.deleteCookie()
            print("✓ Authentication cleared")
            return
        }

        // Handle --show flag
        if show {
            if let cookie = try store.loadCookie() {
                print("Stored cookie (li_at):")
                print(cookie)
            } else {
                print("No cookie stored")
            }
            return
        }

        // Handle --list-browsers flag
        if listBrowsers {
            printAvailableBrowsers()
            return
        }

        // Handle --browser flag (automatic extraction)
        if let browserName = browser {
            try await authenticateFromBrowser(browserName: browserName, profileIndex: profile, store: store)
            return
        }

        // Handle direct cookie argument
        if let cookieValue = cookie {
            try await authenticateWithCookie(cookieValue, store: store)
            return
        }

        // Interactive mode - show instructions and prompt for input
        printAuthInstructions()

        print("\nPaste your li_at cookie value (or press Enter to cancel):")
        guard let input = readLine(), !input.isEmpty else {
            print("Authentication cancelled")
            return
        }

        try await authenticateWithCookie(input, store: store)
    }

    // MARK: - Helper Methods

    private func authenticateFromBrowser(
        browserName: String,
        profileIndex: Int,
        store: CredentialStore
    ) async throws {
        let extractor = BrowserCookieExtractor()

        print("🔍 Extracting LinkedIn cookie from \(browserName.capitalized)...")

        do {
            let cookieValue = try await extractor.extractLinkedInCookie(
                browserName: browserName,
                profileIndex: profileIndex
            )

            // Save to keychain
            try store.saveCookie(cookieValue)
            print("✓ Cookie extracted and saved to keychain")

            // Verify it works
            let client = await createClient(cookie: cookieValue)
            let status = try await client.verifyAuth()

            if status.valid {
                print("✓ Authentication verified successfully")
            } else {
                print("⚠ Warning: \(status.message)")
            }

        } catch let error as BrowserCookieError {
            // Browser extraction failed - provide helpful error and fallback
            print("✗ \(error.localizedDescription)")
            if let suggestion = error.recoverySuggestion {
                print("\n\(suggestion)")
            }

            // Fallback to manual entry
            print("\n📝 Falling back to manual authentication...")
            printAuthInstructions()

            print("\nPaste your li_at cookie value (or press Enter to cancel):")
            guard let input = readLine(), !input.isEmpty else {
                print("Authentication cancelled")
                return
            }

            try await authenticateWithCookie(input, store: store)

        } catch {
            print("✗ Unexpected error: \(error.localizedDescription)")
            throw error
        }
    }

    private func authenticateWithCookie(_ cookieValue: String, store: CredentialStore) async throws {
        // Save to keychain
        try store.saveCookie(cookieValue)
        print("✓ Cookie saved to keychain")

        // Verify it works
        let client = await createClient(cookie: cookieValue)
        let status = try await client.verifyAuth()

        if status.valid {
            print("✓ Authentication verified successfully")
        } else {
            print("⚠ Warning: \(status.message)")
        }
    }

    private func printAvailableBrowsers() {
        let extractor = BrowserCookieExtractor()
        let available = extractor.listAvailableBrowsers()

        if available.isEmpty {
            print("No supported browsers found.")
            print("Supported browsers: Safari, Chrome, Edge, Firefox")
            return
        }

        print("\n📱 Available Browsers:")
        print("=====================\n")

        for browserName in available {
            guard let browser = SupportedBrowser(rawValue: browserName.lowercased()) else {
                continue
            }

            let profiles = extractor.listProfiles(for: browser)
            print("• \(browserName)")

            if profiles.count > 1 {
                print("  Profiles:")
                for (index, profileName) in profiles.enumerated() {
                    print("    [\(index)] \(profileName)")
                }
            } else {
                print("  Profiles: 1 (Default)")
            }
            print("")
        }

        print("Usage:")
        print("  linkedin auth --browser safari")
        print("  linkedin auth --browser chrome --profile 1")
    }

    private func printAuthInstructions() {
        print("""

        LinkedIn Authentication
        ========================

        🚀 EASIEST: Automatic browser extraction (recommended)

          linkedin auth --browser safari
          linkedin auth --browser chrome
          linkedin auth --browser edge
          linkedin auth --browser firefox

          # See available browsers and profiles
          linkedin auth --list-browsers

        📝 MANUAL: Extract cookie manually

        If automatic extraction doesn't work, you can manually extract the 'li_at' cookie:

        1. Open LinkedIn in your browser and log in
        2. Open Developer Tools (F12 or Cmd+Option+I)
        3. Go to Application → Cookies → linkedin.com
        4. Find the 'li_at' cookie and copy its value
        5. Run: linkedin auth YOUR_COOKIE_VALUE

        Or from command line (advanced):

          # Chrome (macOS)
          sqlite3 ~/Library/Application\\ Support/Google/Chrome/Default/Cookies \\
            "SELECT value FROM cookies WHERE host_key='.linkedin.com' AND name='li_at';"

        Note: The cookie expires periodically (usually 1 year) but may be invalidated
        earlier if LinkedIn detects unusual activity.
        """)
    }
}

// MARK: - Status Command

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check authentication status"
    )
    
    @OptionGroup var options: GlobalOptions
    
    func run() async throws {
        let store = CredentialStore()
        let cookie = try options.cookie ?? store.loadCookie()
        
        guard let cookie = cookie else {
            if options.json {
                print(#"{"authenticated": false, "message": "No cookie configured"}"#)
            } else {
                print("✗ Not authenticated")
                print("  Run 'linkedin auth' to configure")
            }
            return
        }
        
        let client = await createClient(cookie: cookie)
        let status = try await client.verifyAuth()
        
        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(status)
            print(String(data: data, encoding: .utf8)!)
        } else {
            if status.valid {
                print("✓ Authenticated")
            } else {
                print("✗ \(status.message)")
            }
        }
    }
}

// MARK: - Profile Command

struct Profile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get a person's LinkedIn profile"
    )
    
    @Argument(help: "LinkedIn username or profile URL")
    var user: String
    
    @Flag(name: .long, help: "Use Peekaboo vision for scraping (requires Screen Recording permission)")
    var vision: Bool = false
    
    @Flag(name: .long, help: "Disable Peekaboo fallback on failed scrapes")
    var noFallback: Bool = false
    
    @OptionGroup var options: GlobalOptions
    
    func run() async throws {
        let client = try await getAuthenticatedClient(options: options)
        
        guard let username = extractUsername(from: user) else {
            throw ValidationError("Invalid username or URL: \(user)")
        }
        
        // Configure fallback behavior
        await client.setUsePeekabooFallback(!noFallback)
        
        let profile: PersonProfile
        
        if vision {
            // Force vision-based scraping
            print("📸 Using Peekaboo vision to scrape profile...")
            profile = try await client.getProfileWithVision(username: username)
        } else {
            profile = try await client.getProfile(username: username)
        }
        
        if options.json {
            printJSON(profile)
        } else {
            printProfile(profile)
        }
    }
    
    private func printProfile(_ profile: PersonProfile) {
        print("\n👤 \(profile.name)")
        
        if let headline = profile.headline {
            print("   \(headline)")
        }
        
        if let location = profile.location {
            print("   📍 \(location)")
        }
        
        if profile.openToWork {
            print("   🟢 Open to work")
        }
        
        if let connectionCount = profile.connectionCount {
            print("   🔗 \(connectionCount)")
        }
        
        if let about = profile.about {
            print("\n📝 About:")
            print("   \(about.prefix(500))...")
        }
        
        if !profile.experiences.isEmpty {
            print("\n💼 Experience:")
            for exp in profile.experiences.prefix(5) {
                print("   • \(exp.title) at \(exp.company)")
                if let duration = exp.duration {
                    print("     \(duration)")
                }
            }
        }
        
        if !profile.educations.isEmpty {
            print("\n🎓 Education:")
            for edu in profile.educations.prefix(3) {
                var line = "   • \(edu.institution)"
                if let degree = edu.degree {
                    line += " - \(degree)"
                }
                print(line)
            }
        }
        
        if !profile.skills.isEmpty {
            print("\n🛠 Skills:")
            print("   \(profile.skills.prefix(10).joined(separator: ", "))")
        }
        
        print("\n   🔗 https://linkedin.com/in/\(profile.username)/")
        print("")
    }
}

// MARK: - Company Command

struct Company: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get a company's LinkedIn profile"
    )
    
    @Argument(help: "Company name or LinkedIn company URL")
    var company: String
    
    @OptionGroup var options: GlobalOptions
    
    func run() async throws {
        let client = try await getAuthenticatedClient(options: options)
        
        guard let companyName = extractCompanyName(from: company) else {
            throw ValidationError("Invalid company name or URL: \(company)")
        }
        
        let profile = try await client.getCompany(name: companyName)
        
        if options.json {
            printJSON(profile)
        } else {
            printCompanyProfile(profile)
        }
    }
    
    private func printCompanyProfile(_ company: CompanyProfile) {
        print("\n🏢 \(company.name)")
        
        if let tagline = company.tagline {
            print("   \(tagline)")
        }
        
        if let industry = company.industry {
            print("   🏭 \(industry)")
        }
        
        if let headquarters = company.headquarters {
            print("   📍 \(headquarters)")
        }
        
        if let employeeCount = company.employeeCount {
            print("   👥 \(employeeCount)")
        }
        
        if let website = company.website {
            print("   🌐 \(website)")
        }
        
        if let about = company.about {
            print("\n📝 About:")
            print("   \(about.prefix(500))...")
        }
        
        if !company.specialties.isEmpty {
            print("\n🎯 Specialties:")
            print("   \(company.specialties.joined(separator: ", "))")
        }
        
        print("\n   🔗 https://linkedin.com/company/\(company.slug)/")
        print("")
    }
}

// MARK: - Jobs Command

struct Jobs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search for jobs"
    )
    
    @Argument(help: "Search query (job title, skills, etc.)")
    var query: String
    
    @Option(name: .shortAndLong, help: "Location filter")
    var location: String?
    
    @Option(name: .shortAndLong, help: "Maximum number of results")
    var limit: Int = 25
    
    @OptionGroup var options: GlobalOptions
    
    func run() async throws {
        let client = try await getAuthenticatedClient(options: options)
        
        let jobs = try await client.searchJobs(query: query, location: location, limit: limit)
        
        if options.json {
            printJSON(jobs)
        } else {
            printJobList(jobs)
        }
    }
    
    private func printJobList(_ jobs: [JobListing]) {
        print("\n📋 Found \(jobs.count) jobs for '\(query)'")
        
        if let location = location {
            print("   📍 Location: \(location)")
        }
        
        print("")
        
        for job in jobs {
            let line = "• \(job.title)"
            print(line)
            print("  🏢 \(job.company)")
            
            if let location = job.location {
                print("  📍 \(location)")
            }
            
            if let salary = job.salary {
                print("  💰 \(salary)")
            }
            
            if job.isEasyApply {
                print("  ⚡ Easy Apply")
            }
            
            print("  🔗 \(job.jobURL)")
            print("")
        }
    }
}

// MARK: - Job Command

struct Job: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get details for a specific job"
    )
    
    @Argument(help: "Job ID or LinkedIn job URL")
    var jobId: String
    
    @OptionGroup var options: GlobalOptions
    
    func run() async throws {
        let client = try await getAuthenticatedClient(options: options)
        
        guard let id = extractJobId(from: jobId) else {
            throw ValidationError("Invalid job ID or URL: \(jobId)")
        }
        
        let job = try await client.getJob(id: id)
        
        if options.json {
            printJSON(job)
        } else {
            printJobDetails(job)
        }
    }
    
    private func printJobDetails(_ job: JobDetails) {
        print("\n💼 \(job.title)")
        print("   🏢 \(job.company)")
        
        if let location = job.location {
            print("   📍 \(location)")
        }
        
        if let workplaceType = job.workplaceType {
            print("   🏠 \(workplaceType)")
        }
        
        if let employmentType = job.employmentType {
            print("   ⏰ \(employmentType)")
        }
        
        if let experienceLevel = job.experienceLevel {
            print("   📊 \(experienceLevel)")
        }
        
        if let salary = job.salary {
            print("   💰 \(salary)")
        }
        
        if let applicantCount = job.applicantCount {
            print("   👥 \(applicantCount)")
        }
        
        if job.isEasyApply {
            print("   ⚡ Easy Apply available")
        }
        
        if let description = job.description {
            print("\n📝 Description:")
            // Print first 1000 chars of description
            let truncated = description.prefix(1000)
            for line in truncated.components(separatedBy: "\n").prefix(20) {
                print("   \(line)")
            }
            if description.count > 1000 {
                print("   ...")
            }
        }
        
        if !job.skills.isEmpty {
            print("\n🛠 Required Skills:")
            print("   \(job.skills.joined(separator: ", "))")
        }
        
        print("\n   🔗 \(job.jobURL)")
        print("")
    }
}

// MARK: - Post Command

struct Post: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a LinkedIn post"
    )

    @Argument(help: "Post text content")
    var text: String

    @Option(name: .long, help: "Visibility: public or connections (default: public)")
    var visibility: String = "public"

    @Option(name: .long, help: "URL to share as article")
    var url: String?

    @Option(name: .long, help: "Article title (used with --url)")
    var urlTitle: String?

    @Option(name: .long, help: "Article description (used with --url)")
    var urlDescription: String?

    @Option(name: .long, help: "Path to image file to attach")
    var image: String?

    @Flag(name: .long, help: "Dry run — show what would be posted without posting")
    var dryRun: Bool = false

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let vis: PostVisibility = visibility.lowercased() == "connections" ? .connections : .public

        if dryRun {
            print("🔍 Dry run — would post:")
            print("   Text: \(text)")
            print("   Visibility: \(vis.rawValue)")
            if let url = url { print("   URL: \(url)") }
            if let urlTitle = urlTitle { print("   Title: \(urlTitle)") }
            if let image = image { print("   Image: \(image)") }
            return
        }

        let client = try await getAuthenticatedClient(options: options)
        let result: PostResult

        if let imagePath = image {
            let imageURL = URL(fileURLWithPath: imagePath)
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                throw ValidationError("Image file not found: \(imagePath)")
            }
            let imageData = try Data(contentsOf: imageURL)
            let filename = imageURL.lastPathComponent
            print("📸 Uploading image (\(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)))...")
            result = try await client.createImagePost(
                text: text, imageData: imageData, filename: filename, visibility: vis
            )
        } else if let articleURL = url {
            result = try await client.createArticlePost(
                text: text, url: articleURL, title: urlTitle, description: urlDescription, visibility: vis
            )
        } else {
            result = try await client.createTextPost(text: text, visibility: vis)
        }

        if options.json {
            printJSON(result)
        } else if result.success {
            print("✓ \(result.message)")
            if let urn = result.postURN { print("  URN: \(urn)") }
        } else {
            print("✗ \(result.message)")
        }
    }
}

// MARK: - Inbox Command

struct Inbox: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List LinkedIn inbox conversations"
    )

    @Option(name: .shortAndLong, help: "Maximum conversations to show")
    var limit: Int = 20

    @Flag(name: .long, help: "Show only unread conversations")
    var unreadOnly: Bool = false
    
    @Flag(name: .long, help: "Force browser mode for messaging (Peekaboo/Safari), bypass Voyager API")
    var browserMode: Bool = false

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let client = try await getMessagingClient(options: options, browserMode: browserMode)
        var conversations = try await client.listConversations(limit: limit)

        if unreadOnly {
            conversations = conversations.filter { $0.unread }
        }

        if options.json {
            printJSON(conversations)
        } else {
            let unreadCount = conversations.filter { $0.unread }.count
            print("\n📬 Inbox — \(conversations.count) conversations (\(unreadCount) unread)\n")

            for conv in conversations {
                let marker = conv.unread ? "🔵" : "  "
                let names = conv.participantNames.joined(separator: ", ")
                let preview = conv.lastMessage.map { String($0.prefix(80)) } ?? "(no messages)"
                let time = conv.lastMessageAt ?? ""

                print("\(marker) \(names.isEmpty ? "Unknown" : names)")
                print("   \(preview)")
                if !time.isEmpty { print("   🕐 \(time)") }
                print("   ID: \(conv.id)")
                print("")
            }
        }
    }
}

// MARK: - Messages Command

struct Messages: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read messages from a conversation"
    )

    @Argument(help: "Conversation ID")
    var conversationId: String

    @Option(name: .shortAndLong, help: "Maximum messages to show")
    var limit: Int = 20
    
    @Flag(name: .long, help: "Force browser mode for messaging (Peekaboo/Safari), bypass Voyager API")
    var browserMode: Bool = false

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let client = try await getMessagingClient(options: options, browserMode: browserMode)
        let messages = try await client.getMessages(conversationId: conversationId, limit: limit)

        if options.json {
            printJSON(messages)
        } else {
            print("\n💬 \(messages.count) messages\n")

            for msg in messages.reversed() {
                let time = msg.timestamp ?? ""
                print("[\(time)] \(msg.senderName):")
                print("  \(msg.text)")
                print("")
            }
        }
    }
}

// MARK: - Helpers

func getAuthenticatedClient(options: GlobalOptions) async throws -> LinkedInClient {
    let store = CredentialStore()
    let cookie = try options.cookie ?? store.loadCookie()
    
    guard let cookie = cookie else {
        throw ValidationError("Not authenticated. Run 'linkedin auth' to configure.")
    }
    
    let client = await createClient(cookie: cookie)
    return client
}

func getMessagingClient(options: GlobalOptions, browserMode: Bool) async throws -> LinkedInClient {
    if browserMode {
        let store = CredentialStore()
        let cookie = try options.cookie ?? store.loadCookie()
        let client = await createClient(cookie: cookie)
        await client.setPreferPeekabooMessaging(true)
        return client
    }
    return try await getAuthenticatedClient(options: options)
}

func printJSON<T: Codable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    
    do {
        let data = try encoder.encode(value)
        if let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    } catch {
        fputs("Error encoding JSON: \(error)\n", stderr)
    }
}
