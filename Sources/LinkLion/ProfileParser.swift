import Foundation
import SwiftSoup

/// Parser for LinkedIn profile pages
enum ProfileParser {
    
    /// Parse a person's profile from HTML
    static func parsePersonProfile(html: String, username: String) throws -> PersonProfile {
        let doc = try SwiftSoup.parse(html)
        
        // Try to extract data from JSON-LD first (most reliable)
        if let jsonLD = try extractJSONLD(from: doc, type: "Person") {
            return try parsePersonFromJSONLD(jsonLD, username: username, doc: doc)
        }
        
        // Fallback to HTML parsing
        return try parsePersonFromHTML(doc, username: username)
    }
    
    /// Parse a company profile from HTML
    static func parseCompanyProfile(html: String, companyName: String) throws -> CompanyProfile {
        let doc = try SwiftSoup.parse(html)
        
        // Try to extract data from JSON-LD first
        if let jsonLD = try extractJSONLD(from: doc, type: "Organization") {
            return try parseCompanyFromJSONLD(jsonLD, companyName: companyName, doc: doc)
        }
        
        // Fallback to HTML parsing
        return try parseCompanyFromHTML(doc, companyName: companyName)
    }
    
    // MARK: - JSON-LD Extraction
    
    private static func extractJSONLD(from doc: Document, type: String) throws -> [String: Any]? {
        let scripts = try doc.select("script[type=application/ld+json]")
        
        for script in scripts {
            let content = try script.html()
            guard let data = content.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            
            if let jsonType = json["@type"] as? String, jsonType == type {
                return json
            }
            
            // Handle @graph format
            if let graph = json["@graph"] as? [[String: Any]] {
                for item in graph {
                    if let itemType = item["@type"] as? String, itemType == type {
                        return item
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Person Parsing
    
    private static func parsePersonFromJSONLD(_ json: [String: Any], username: String, doc: Document) throws -> PersonProfile {
        let name = json["name"] as? String ?? ""
        let description = json["description"] as? String
        var jobTitle: String? = nil
        var company: String? = nil
        
        if let worksFor = json["worksFor"] as? [String: Any] {
            company = worksFor["name"] as? String
        }
        
        if let jobTitleValue = json["jobTitle"] as? String {
            jobTitle = jobTitleValue
        } else if let jobTitles = json["jobTitle"] as? [String], let first = jobTitles.first {
            jobTitle = first
        }
        
        let address = json["address"] as? [String: Any]
        let location = address?["addressLocality"] as? String
        
        let profileImage = json["image"] as? [String: Any]
        let profileImageURL = profileImage?["contentUrl"] as? String
        
        // Extract additional data from HTML
        let experiences = try parseExperiences(from: doc)
        let educations = try parseEducations(from: doc)
        let skills = try parseSkills(from: doc)
        let openToWork = try checkOpenToWork(from: doc)
        let headline = try parseHeadline(from: doc)
        let about = try parseAbout(from: doc)
        let connectionCount = try parseConnectionCount(from: doc)
        let followerCount = try parseFollowerCount(from: doc)
        
        return PersonProfile(
            username: username,
            name: name,
            headline: headline ?? description,
            about: about,
            location: location,
            company: company,
            jobTitle: jobTitle,
            experiences: experiences,
            educations: educations,
            skills: skills,
            profileImageURL: profileImageURL,
            connectionCount: connectionCount,
            followerCount: followerCount,
            openToWork: openToWork
        )
    }
    
    private static func parsePersonFromHTML(_ doc: Document, username: String) throws -> PersonProfile {
        // Name from h1 or title
        let name: String
        if let h1 = try doc.select("h1").first() {
            name = try h1.text()
        } else if let title = try doc.select("title").first() {
            let titleText = try title.text()
            name = titleText.components(separatedBy: " | ").first ?? username
        } else {
            name = username
        }
        
        let headline = try parseHeadline(from: doc)
        let about = try parseAbout(from: doc)
        let location = try doc.select(".text-body-small.inline.t-black--light.break-words").first()?.text()
        let experiences = try parseExperiences(from: doc)
        let educations = try parseEducations(from: doc)
        let skills = try parseSkills(from: doc)
        let openToWork = try checkOpenToWork(from: doc)
        let connectionCount = try parseConnectionCount(from: doc)
        let followerCount = try parseFollowerCount(from: doc)
        
        // Try to get current job info from headline
        var company: String? = nil
        var jobTitle: String? = nil
        
        if let headlineText = headline {
            let parts = headlineText.components(separatedBy: " at ")
            if parts.count >= 2 {
                jobTitle = parts[0].trimmingCharacters(in: .whitespaces)
                company = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        
        if company == nil, let firstExp = experiences.first {
            company = firstExp.company
            jobTitle = firstExp.title
        }
        
        return PersonProfile(
            username: username,
            name: name,
            headline: headline,
            about: about,
            location: location,
            company: company,
            jobTitle: jobTitle,
            experiences: experiences,
            educations: educations,
            skills: skills,
            connectionCount: connectionCount,
            followerCount: followerCount,
            openToWork: openToWork
        )
    }
    
    private static func parseHeadline(from doc: Document) throws -> String? {
        // Try various selectors for headline
        let selectors = [
            ".text-body-medium.break-words",
            "[data-generated-suggestion-target]",
            ".pv-text-details__left-panel .text-body-medium",
        ]
        
        for selector in selectors {
            if let element = try doc.select(selector).first() {
                let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }
        
        return nil
    }
    
    private static func parseAbout(from doc: Document) throws -> String? {
        let selectors = [
            "#about ~ .display-flex .inline-show-more-text",
            ".pv-about__summary-text",
            "[data-generated-suggestion-target='urn:li:fsu_profileActionDelegate']",
        ]
        
        for selector in selectors {
            if let element = try doc.select(selector).first() {
                let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && text.count > 10 {
                    return text
                }
            }
        }
        
        return nil
    }
    
    private static func parseExperiences(from doc: Document) throws -> [Experience] {
        var experiences: [Experience] = []
        
        // Try to find experience section
        let experienceSection = try doc.select("#experience").first() 
            ?? doc.select("[id*=experience]").first()
        
        guard let section = experienceSection else { return experiences }
        
        // Find experience items
        let items = try section.parent()?.select("li.artdeco-list__item") ?? Elements()
        
        for item in items.prefix(10) { // Limit to avoid too many
            let title = try item.select(".t-bold span[aria-hidden=true]").first()?.text() ?? ""
            let companyElement = try item.select(".t-normal span[aria-hidden=true]").first()
            let company = try companyElement?.text() ?? ""
            
            if !title.isEmpty && !company.isEmpty {
                let dateRange = try item.select(".t-black--light span[aria-hidden=true]").first()?.text()
                var startDate: String? = nil
                var endDate: String? = nil
                var duration: String? = nil
                
                if let range = dateRange {
                    let parts = range.components(separatedBy: " - ")
                    if parts.count >= 2 {
                        startDate = parts[0].trimmingCharacters(in: .whitespaces)
                        let endParts = parts[1].components(separatedBy: " · ")
                        endDate = endParts[0].trimmingCharacters(in: .whitespaces)
                        if endParts.count > 1 {
                            duration = endParts[1].trimmingCharacters(in: .whitespaces)
                        }
                    }
                }
                
                let location = try item.select(".t-black--light.t-normal span[aria-hidden=true]").last()?.text()
                let description = try item.select(".inline-show-more-text").first()?.text()
                
                experiences.append(Experience(
                    title: title,
                    company: company,
                    location: location,
                    startDate: startDate,
                    endDate: endDate,
                    duration: duration,
                    description: description
                ))
            }
        }
        
        return experiences
    }
    
    private static func parseEducations(from doc: Document) throws -> [Education] {
        var educations: [Education] = []
        
        let educationSection = try doc.select("#education").first() 
            ?? doc.select("[id*=education]").first()
        
        guard let section = educationSection else { return educations }
        
        let items = try section.parent()?.select("li.artdeco-list__item") ?? Elements()
        
        for item in items.prefix(5) {
            let institution = try item.select(".t-bold span[aria-hidden=true]").first()?.text() ?? ""
            let degree = try item.select(".t-normal span[aria-hidden=true]").first()?.text()
            
            if !institution.isEmpty {
                let dateRange = try item.select(".t-black--light span[aria-hidden=true]").first()?.text()
                var startDate: String? = nil
                var endDate: String? = nil
                
                if let range = dateRange {
                    let parts = range.components(separatedBy: " - ")
                    if parts.count >= 2 {
                        startDate = parts[0].trimmingCharacters(in: .whitespaces)
                        endDate = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
                
                educations.append(Education(
                    institution: institution,
                    degree: degree,
                    startDate: startDate,
                    endDate: endDate
                ))
            }
        }
        
        return educations
    }
    
    private static func parseSkills(from doc: Document) throws -> [String] {
        var skills: [String] = []
        
        let skillsSection = try doc.select("#skills").first()
            ?? doc.select("[id*=skills]").first()
        
        guard let section = skillsSection else { return skills }
        
        let items = try section.parent()?.select("li") ?? Elements()
        
        for item in items.prefix(20) {
            if let skillName = try item.select(".t-bold span[aria-hidden=true]").first()?.text(),
               !skillName.isEmpty {
                skills.append(skillName)
            }
        }
        
        return skills
    }
    
    private static func checkOpenToWork(from doc: Document) throws -> Bool {
        let openToWorkIndicators = try doc.select(".pv-open-to-carousel-card, [class*=open-to-work], #open-to-work")
        return !openToWorkIndicators.isEmpty()
    }
    
    private static func parseConnectionCount(from doc: Document) throws -> String? {
        let connectionElement = try doc.select(".t-bold:contains(connections)").first()
        return try connectionElement?.text()
    }
    
    private static func parseFollowerCount(from doc: Document) throws -> String? {
        let followerElement = try doc.select(".t-bold:contains(followers)").first()
        return try followerElement?.text()
    }
    
    // MARK: - Company Parsing
    
    private static func parseCompanyFromJSONLD(_ json: [String: Any], companyName: String, doc: Document) throws -> CompanyProfile {
        let name = json["name"] as? String ?? companyName
        let description = json["description"] as? String
        let url = json["url"] as? String
        
        let address = json["address"] as? [String: Any]
        let headquarters = address?["addressLocality"] as? String
        
        let logo = json["logo"] as? [String: Any]
        let logoURL = logo?["contentUrl"] as? String ?? json["logo"] as? String
        
        // Extract additional info from HTML
        let (industry, companySize, founded, specialties) = try parseCompanyDetails(from: doc)
        let employeeCount = try parseEmployeeCount(from: doc)
        let followerCount = try parseCompanyFollowerCount(from: doc)
        let tagline = try parseCompanyTagline(from: doc)
        
        return CompanyProfile(
            name: name,
            slug: companyName,
            tagline: tagline,
            about: description,
            website: url,
            industry: industry,
            companySize: companySize,
            headquarters: headquarters,
            founded: founded,
            specialties: specialties,
            employeeCount: employeeCount,
            followerCount: followerCount,
            logoURL: logoURL
        )
    }
    
    private static func parseCompanyFromHTML(_ doc: Document, companyName: String) throws -> CompanyProfile {
        let name = try doc.select("h1").first()?.text() ?? companyName
        let tagline = try parseCompanyTagline(from: doc)
        let about = try doc.select(".break-words .inline-show-more-text").first()?.text()
        
        let (industry, companySize, founded, specialties) = try parseCompanyDetails(from: doc)
        let employeeCount = try parseEmployeeCount(from: doc)
        let followerCount = try parseCompanyFollowerCount(from: doc)
        
        let websiteLink = try doc.select("a[data-control-name=page_details_module_website_external_link]").first()
        let website = try websiteLink?.attr("href")
        
        return CompanyProfile(
            name: name,
            slug: companyName,
            tagline: tagline,
            about: about,
            website: website,
            industry: industry,
            companySize: companySize,
            founded: founded,
            specialties: specialties,
            employeeCount: employeeCount,
            followerCount: followerCount
        )
    }
    
    private static func parseCompanyTagline(from doc: Document) throws -> String? {
        let taglineElement = try doc.select(".org-top-card-summary__tagline").first()
            ?? doc.select(".text-body-medium.break-words").first()
        return try taglineElement?.text()
    }
    
    private static func parseCompanyDetails(from doc: Document) throws -> (industry: String?, companySize: String?, founded: String?, specialties: [String]) {
        var industry: String? = nil
        var companySize: String? = nil
        var founded: String? = nil
        var specialties: [String] = []
        
        // Parse from about section
        let detailItems = try doc.select(".org-page-details__definition-term")
        
        for item in detailItems {
            let label = try item.text().lowercased()
            let value = try item.nextElementSibling()?.text()
            
            if label.contains("industry") {
                industry = value
            } else if label.contains("company size") || label.contains("employees") {
                companySize = value
            } else if label.contains("founded") {
                founded = value
            } else if label.contains("specialties") {
                if let specialtiesText = value {
                    specialties = specialtiesText
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                }
            }
        }
        
        return (industry, companySize, founded, specialties)
    }
    
    private static func parseEmployeeCount(from doc: Document) throws -> String? {
        let employeeElement = try doc.select("a[href*=employees]:contains(employees)").first()
            ?? doc.select(".org-top-card-summary-info-list__info-item:contains(employees)").first()
        return try employeeElement?.text()
    }
    
    private static func parseCompanyFollowerCount(from doc: Document) throws -> String? {
        let followerElement = try doc.select(".org-top-card-summary-info-list__info-item:contains(followers)").first()
        return try followerElement?.text()
    }
}
