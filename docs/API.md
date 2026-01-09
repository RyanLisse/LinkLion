# 🔌 LinkLion API Reference

This document provides the complete API reference for the LinkLion library.

## Table of Contents

1. [Main Types](#main-types)
2. [Creating a Client](#creating-a-client)
3. [Authentication](#authentication)
4. [Profile Operations](#profile-operations)
5. [Company Operations](#company-operations)
6. [Job Operations](#job-operations)

---

## Main Types

### `LinkedInClient`

The main client for all LinkedIn operations.

```swift
public actor LinkedInClient {
    /// Creates a new client instance
    public init()
    
    /// Configures the client with an authentication cookie
    public func configure(cookie: String) async
    
    /// Verifies the current authentication status
    public func verifyAuth() async throws -> AuthStatus
    
    /// Gets a person's profile
    public func getProfile(username: String) async throws -> Profile
    
    /// Gets a person's profile from URL
    public func getProfile(url: String) async throws -> Profile
    
    /// Gets a company profile
    public func getCompany(name: String) async throws -> Company
    
    /// Gets a company profile from URL
    public func getCompany(url: String) async throws -> Company
    
    /// Searches for jobs
    public func searchJobs(query: String, location: String?, limit: Int) async throws -> [Job]
    
    /// Gets job details by ID
    public func getJob(id: String) async throws -> JobDetail
    
    /// Gets job details from URL
    public func getJob(url: String) async throws -> JobDetail
}
```

### `AuthStatus`

Authentication verification result.

```swift
public struct AuthStatus {
    /// Whether the user is currently authenticated
    public var valid: Bool
    
    /// Username of authenticated user (if available)
    public var username: String?
    
    /// When the auth was last verified
    public var verifiedAt: Date
}
```

---

## Creating a Client

### Basic Setup

```swift
import LinkLion

// Create the client
let client = await LinkedInClient()

// Configure with your li_at cookie
await client.configure(cookie: "your-li_at-cookie-here")

// Verify authentication
let status = try await client.verifyAuth()
print("Authenticated: \(status.valid)")
```

### Using with Keychain

The library integrates with macOS Keychain for secure credential storage:

```swift
import LinkLion

let client = await LinkedInClient()

// Check if we have stored credentials
let status = try await client.verifyAuth()
if status.valid {
    print("Already authenticated as: \(status.username ?? "unknown")")
} else {
    print("Please configure authentication")
}
```

---

## Authentication

### Configure with Cookie

```swift
// Set the li_at cookie for authentication
await client.configure(cookie: "AQEDAQ...")

// Verify it worked
let status = try await client.verifyAuth()
assert(status.valid)
```

### Verify Authentication Status

```swift
let status = try await client.verifyAuth()

print("Valid: \(status.valid)")
print("Username: \(status.username ?? "N/A")")
print("Verified: \(status.verifiedAt)")
```

---

## Profile Operations

### Get Profile by Username

```swift
let profile = try await client.getProfile(username: "satya-nadella")

print("Name: \(profile.name)")
print("Headline: \(profile.headline ?? "N/A")")
print("Location: \(profile.location ?? "N/A")")

if let about = profile.about {
    print("About: \(about)")
}

print("Experience:")
for exp in profile.experience {
    print("  - \(exp.title) at \(exp.company)")
    print("    \(exp.startDate) - \(exp.endDate ?? "Present")")
}

print("Education:")
for edu in profile.education {
    print("  - \(edu.degree) in \(edu.field) at \(edu.school)")
}

print("Skills: \(profile.skills.map { $0.name }.joined(separator: ", "))")
print("Connections: \(profile.connections ?? 0)")
```

### Get Profile from URL

```swift
let profile = try await client.getProfile(
    url: "https://linkedin.com/in/williamhgates"
)
```

---

## Company Operations

### Get Company by Name

```swift
let company = try await client.getCompany(name: "microsoft")

print("Company: \(company.name)")
print("Industry: \(company.industry ?? "N/A")")
print("Size: \(company.size ?? "N/A")")
print("Website: \(company.website?.absoluteString ?? "N/A")")

if let desc = company.description {
    print("\nDescription:\n\(desc)")
}

print("\nSpecialties:")
for specialty in company.specialities {
    print("  • \(specialty)")
}
```

### Get Company from URL

```swift
let company = try await client.getCompany(
    url: "https://linkedin.com/company/anthropic"
)
```

---

## Job Operations

### Search Jobs

```swift
let jobs = try await client.searchJobs(
    query: "Swift Developer",
    location: "San Francisco",
    limit: 20
)

for job in jobs {
    print("【\(job.id)】\(job.title)")
    print("   \(job.company) • \(job.location)")
    print("   Posted: \(job.postedDate?.description ?? "Unknown")")
}
```

### Get Job Details

```swift
let details = try await client.getJob(id: "1234567890")

print("【\(details.title)】")
print("Company: \(details.company)")
print("Location: \(details.location)")
print("Type: \(details.type ?? "N/A")")
print("Level: \(details.level ?? "N/A")")

if let desc = details.description {
    print("\n📋 Description:\n\(desc)")
}

if !details.requirements.isEmpty {
    print("\n✅ Requirements:")
    for req in details.requirements {
        print("  • \(req)")
    }
}

if !details.benefits.isEmpty {
    print("\n🎁 Benefits:")
    for benefit in details.benefits {
        print("  • \(benefit)")
    }
}
```

---

## Error Handling

```swift
do {
    let profile = try await client.getProfile(username: "nonexistent-user")
} catch LinkedInError.notAuthenticated {
    print("Please configure authentication first")
} catch LinkedInError.profileNotFound(let username) {
    print("Profile not found: \(username)")
} catch LinkedInError.rateLimited {
    print("Too many requests. Please wait.")
} catch LinkedInError.invalidResponse {
    print("Invalid response from LinkedIn")
} catch {
    print("Unexpected error: \(error)")
}
```

---

## Model Properties

### Profile

| Property | Type | Description |
|----------|------|-------------|
| `name` | `String` | Full name |
| `headline` | `String?` | Profile headline/tagline |
| `location` | `String?` | Geographic location |
| `about` | `String?` | About section text |
| `experience` | `[Experience]` | Work experience entries |
| `education` | `[Education]` | Education history |
| `skills` | `[Skill]` | Listed skills |
| `connections` | `Int?` | Connection count |

### Company

| Property | Type | Description |
|----------|------|-------------|
| `name` | `String` | Company name |
| `industry` | `String?` | Industry classification |
| `size` | `String?` | Company size range |
| `description` | `String?` | Company description |
| `specialities` | `[String]` | List of specialties |
| `website` | `URL?` | Company website |

### Job

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | LinkedIn job ID |
| `title` | `String` | Job title |
| `company` | `String` | Company name |
| `location` | `String` | Job location |
| `postedDate` | `Date?` | When job was posted |

### JobDetail

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Job ID |
| `title` | `String` | Job title |
| `company` | `String` | Company name |
| `location` | `String` | Job location |
| `type` | `String?` | Full-time, contract, etc. |
| `level` | `String?` | Seniority level |
| `description` | `String?` | Full job description |
| `requirements` | `[String]` | Job requirements |
| `benefits` | `[String]` | Listed benefits |
