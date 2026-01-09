import Foundation

// MARK: - Person Profile

public struct PersonProfile: Codable, Sendable {
    public let username: String
    public let name: String
    public let headline: String?
    public let about: String?
    public let location: String?
    public let company: String?
    public let jobTitle: String?
    public let experiences: [Experience]
    public let educations: [Education]
    public let skills: [String]
    public let profileImageURL: String?
    public let backgroundImageURL: String?
    public let connectionCount: String?
    public let followerCount: String?
    public let openToWork: Bool
    
    public init(
        username: String,
        name: String,
        headline: String? = nil,
        about: String? = nil,
        location: String? = nil,
        company: String? = nil,
        jobTitle: String? = nil,
        experiences: [Experience] = [],
        educations: [Education] = [],
        skills: [String] = [],
        profileImageURL: String? = nil,
        backgroundImageURL: String? = nil,
        connectionCount: String? = nil,
        followerCount: String? = nil,
        openToWork: Bool = false
    ) {
        self.username = username
        self.name = name
        self.headline = headline
        self.about = about
        self.location = location
        self.company = company
        self.jobTitle = jobTitle
        self.experiences = experiences
        self.educations = educations
        self.skills = skills
        self.profileImageURL = profileImageURL
        self.backgroundImageURL = backgroundImageURL
        self.connectionCount = connectionCount
        self.followerCount = followerCount
        self.openToWork = openToWork
    }
}

public struct Experience: Codable, Sendable {
    public let title: String
    public let company: String
    public let companyURL: String?
    public let location: String?
    public let startDate: String?
    public let endDate: String?
    public let duration: String?
    public let description: String?
    
    public init(
        title: String,
        company: String,
        companyURL: String? = nil,
        location: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        duration: String? = nil,
        description: String? = nil
    ) {
        self.title = title
        self.company = company
        self.companyURL = companyURL
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.description = description
    }
}

public struct Education: Codable, Sendable {
    public let institution: String
    public let degree: String?
    public let fieldOfStudy: String?
    public let startDate: String?
    public let endDate: String?
    public let description: String?
    
    public init(
        institution: String,
        degree: String? = nil,
        fieldOfStudy: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        description: String? = nil
    ) {
        self.institution = institution
        self.degree = degree
        self.fieldOfStudy = fieldOfStudy
        self.startDate = startDate
        self.endDate = endDate
        self.description = description
    }
}

// MARK: - Company Profile

public struct CompanyProfile: Codable, Sendable {
    public let name: String
    public let slug: String
    public let tagline: String?
    public let about: String?
    public let website: String?
    public let industry: String?
    public let companySize: String?
    public let headquarters: String?
    public let founded: String?
    public let specialties: [String]
    public let employeeCount: String?
    public let followerCount: String?
    public let logoURL: String?
    public let coverImageURL: String?
    
    public init(
        name: String,
        slug: String,
        tagline: String? = nil,
        about: String? = nil,
        website: String? = nil,
        industry: String? = nil,
        companySize: String? = nil,
        headquarters: String? = nil,
        founded: String? = nil,
        specialties: [String] = [],
        employeeCount: String? = nil,
        followerCount: String? = nil,
        logoURL: String? = nil,
        coverImageURL: String? = nil
    ) {
        self.name = name
        self.slug = slug
        self.tagline = tagline
        self.about = about
        self.website = website
        self.industry = industry
        self.companySize = companySize
        self.headquarters = headquarters
        self.founded = founded
        self.specialties = specialties
        self.employeeCount = employeeCount
        self.followerCount = followerCount
        self.logoURL = logoURL
        self.coverImageURL = coverImageURL
    }
}

// MARK: - Jobs

public struct JobListing: Codable, Sendable {
    public let id: String
    public let title: String
    public let company: String
    public let companyURL: String?
    public let location: String?
    public let postedDate: String?
    public let salary: String?
    public let isEasyApply: Bool
    public let jobURL: String
    
    public init(
        id: String,
        title: String,
        company: String,
        companyURL: String? = nil,
        location: String? = nil,
        postedDate: String? = nil,
        salary: String? = nil,
        isEasyApply: Bool = false,
        jobURL: String
    ) {
        self.id = id
        self.title = title
        self.company = company
        self.companyURL = companyURL
        self.location = location
        self.postedDate = postedDate
        self.salary = salary
        self.isEasyApply = isEasyApply
        self.jobURL = jobURL
    }
}

public struct JobDetails: Codable, Sendable {
    public let id: String
    public let title: String
    public let company: String
    public let companyURL: String?
    public let location: String?
    public let workplaceType: String? // Remote, On-site, Hybrid
    public let employmentType: String? // Full-time, Part-time, Contract
    public let experienceLevel: String?
    public let postedDate: String?
    public let applicantCount: String?
    public let salary: String?
    public let description: String?
    public let skills: [String]
    public let isEasyApply: Bool
    public let jobURL: String
    
    public init(
        id: String,
        title: String,
        company: String,
        companyURL: String? = nil,
        location: String? = nil,
        workplaceType: String? = nil,
        employmentType: String? = nil,
        experienceLevel: String? = nil,
        postedDate: String? = nil,
        applicantCount: String? = nil,
        salary: String? = nil,
        description: String? = nil,
        skills: [String] = [],
        isEasyApply: Bool = false,
        jobURL: String
    ) {
        self.id = id
        self.title = title
        self.company = company
        self.companyURL = companyURL
        self.location = location
        self.workplaceType = workplaceType
        self.employmentType = employmentType
        self.experienceLevel = experienceLevel
        self.postedDate = postedDate
        self.applicantCount = applicantCount
        self.salary = salary
        self.description = description
        self.skills = skills
        self.isEasyApply = isEasyApply
        self.jobURL = jobURL
    }
}
