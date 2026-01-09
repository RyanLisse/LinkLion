import ArgumentParser
import Foundation
import LinkedInKit

@main
struct LinkedIn: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "linkedin",
        abstract: "LinkedIn CLI - Interact with LinkedIn from the command line",
        version: LinkedInKit.version,
        subcommands: [
            Auth.self,
            Profile.self,
            Company.self,
            Jobs.self,
            Job.self,
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
    
    func run() async throws {
        let store = CredentialStore()
        
        if clear {
            try store.deleteCookie()
            print("✓ Authentication cleared")
            return
        }
        
        if show {
            if let cookie = try store.loadCookie() {
                print("Stored cookie (li_at):")
                print(cookie)
            } else {
                print("No cookie stored")
            }
            return
        }
        
        guard let cookieValue = cookie else {
            // Interactive mode - show instructions
            printAuthInstructions()
            
            print("\nPaste your li_at cookie value (or press Enter to cancel):")
            guard let input = readLine(), !input.isEmpty else {
                print("Authentication cancelled")
                return
            }
            
            try store.saveCookie(input)
            print("✓ Cookie saved to keychain")
            
            // Verify it works
            let client = await createClient(cookie: input)
            let status = try await client.verifyAuth()
            
            if status.valid {
                print("✓ Authentication verified successfully")
            } else {
                print("⚠ Warning: \(status.message)")
            }
            return
        }
        
        try store.saveCookie(cookieValue)
        print("✓ Cookie saved to keychain")
        
        // Verify
        let client = await createClient(cookie: cookieValue)
        let status = try await client.verifyAuth()
        
        if status.valid {
            print("✓ Authentication verified")
        } else {
            print("⚠ Warning: \(status.message)")
        }
    }
    
    private func printAuthInstructions() {
        print("""
        
        LinkedIn Authentication
        ========================
        
        To authenticate, you need the 'li_at' cookie from your browser:
        
        1. Open LinkedIn in your browser and log in
        2. Open Developer Tools (F12 or Cmd+Option+I)
        3. Go to Application → Cookies → linkedin.com
        4. Find the 'li_at' cookie and copy its value
        
        Or from the command line:
        
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
    
    @OptionGroup var options: GlobalOptions
    
    func run() async throws {
        let client = try await getAuthenticatedClient(options: options)
        
        guard let username = extractUsername(from: user) else {
            throw ValidationError("Invalid username or URL: \(user)")
        }
        
        let profile = try await client.getProfile(username: username)
        
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
