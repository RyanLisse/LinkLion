import Foundation
import SwiftSoup

/// Parser for LinkedIn job pages
enum JobParser {
    
    private static let baseURL = "https://www.linkedin.com"
    
    /// Parse job search results from HTML
    static func parseJobSearch(html: String, limit: Int = 25) throws -> [JobListing] {
        let doc = try SwiftSoup.parse(html)
        var jobs: [JobListing] = []
        
        // Job cards in search results
        let jobCards = try doc.select("div.job-search-card, li.jobs-search-results__list-item, div.base-card")
        
        for card in jobCards.prefix(limit) {
            if let job = try parseJobCard(card) {
                jobs.append(job)
            }
        }
        
        // Also try data attributes for job IDs
        if jobs.isEmpty {
            let dataCards = try doc.select("[data-entity-urn*=jobPosting]")
            for card in dataCards.prefix(limit) {
                if let job = try parseJobCardFromDataAttribute(card) {
                    jobs.append(job)
                }
            }
        }
        
        return jobs
    }
    
    /// Parse job details from HTML
    static func parseJobDetails(html: String, jobId: String) throws -> JobDetails {
        let doc = try SwiftSoup.parse(html)
        
        // Try JSON-LD first
        if let jsonLD = try extractJobJSONLD(from: doc) {
            return try parseJobFromJSONLD(jsonLD, jobId: jobId, doc: doc)
        }
        
        // Fallback to HTML parsing
        return try parseJobFromHTML(doc, jobId: jobId)
    }
    
    // MARK: - Private Helpers
    
    private static func parseJobCard(_ card: Element) throws -> JobListing? {
        // Extract job ID from link or data attribute
        var jobId: String? = nil
        
        if let link = try card.select("a[href*=/jobs/view/]").first() {
            let href = try link.attr("href")
            if let idMatch = href.range(of: #"/jobs/view/(\d+)"#, options: .regularExpression) {
                let extracted = href[idMatch]
                jobId = String(extracted.dropFirst(11).prefix(while: { $0.isNumber }))
            }
        }
        
        // Also check data-job-id attribute
        if jobId == nil {
            jobId = try? card.attr("data-job-id")
            if jobId?.isEmpty == true { jobId = nil }
        }
        
        // Extract from URN
        if jobId == nil {
            let urn = try? card.attr("data-entity-urn")
            if let urn = urn, let range = urn.range(of: #"\d+$"#, options: .regularExpression) {
                jobId = String(urn[range])
            }
        }
        
        guard let id = jobId, !id.isEmpty else { return nil }
        
        // Title
        let title = try card.select(".base-search-card__title, .job-search-card__title, h3, h4")
            .first()?.text() ?? ""
        
        guard !title.isEmpty else { return nil }
        
        // Company
        let company = try card.select(".base-search-card__subtitle, .job-search-card__company-name, h4 a")
            .first()?.text() ?? ""
        
        // Company URL
        let companyLink = try card.select("a[href*=/company/]").first()
        let companyURL = try companyLink.map { try $0.attr("href") }
        
        // Location
        let location = try card.select(".job-search-card__location, .base-search-card__metadata span")
            .first()?.text()
        
        // Posted date
        let postedDate = try card.select("time, .job-search-card__listdate")
            .first()?.text()
        
        // Salary (if shown)
        let salary = try card.select(".job-search-card__salary-info, .base-search-card__salary")
            .first()?.text()
        
        // Easy Apply indicator
        let isEasyApply = try !card.select(".job-search-card__easy-apply-button, [data-is-easy-apply-job]").isEmpty()
        
        return JobListing(
            id: id,
            title: title,
            company: company,
            companyURL: companyURL,
            location: location,
            postedDate: postedDate,
            salary: salary,
            isEasyApply: isEasyApply,
            jobURL: "\(baseURL)/jobs/view/\(id)/"
        )
    }
    
    private static func parseJobCardFromDataAttribute(_ card: Element) throws -> JobListing? {
        let urn = try card.attr("data-entity-urn")
        guard let range = urn.range(of: #"\d+$"#, options: .regularExpression) else { return nil }
        let id = String(urn[range])
        
        let title = try card.select("[data-control-name=jobPosting_title], h3, .job-card-list__title").first()?.text() ?? ""
        let company = try card.select(".job-card-container__company-name, .base-search-card__subtitle").first()?.text() ?? ""
        let location = try card.select(".job-card-container__metadata-item, .base-search-card__metadata").first()?.text()
        
        guard !title.isEmpty else { return nil }
        
        return JobListing(
            id: id,
            title: title,
            company: company,
            location: location,
            jobURL: "\(baseURL)/jobs/view/\(id)/"
        )
    }
    
    private static func extractJobJSONLD(from doc: Document) throws -> [String: Any]? {
        let scripts = try doc.select("script[type=application/ld+json]")
        
        for script in scripts {
            let content = try script.html()
            guard let data = content.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            
            if let type = json["@type"] as? String, type == "JobPosting" {
                return json
            }
            
            // Handle @graph format
            if let graph = json["@graph"] as? [[String: Any]] {
                for item in graph {
                    if let itemType = item["@type"] as? String, itemType == "JobPosting" {
                        return item
                    }
                }
            }
        }
        
        return nil
    }
    
    private static func parseJobFromJSONLD(_ json: [String: Any], jobId: String, doc: Document) throws -> JobDetails {
        let title = json["title"] as? String ?? ""
        
        var company = ""
        var companyURL: String? = nil
        if let hiringOrg = json["hiringOrganization"] as? [String: Any] {
            company = hiringOrg["name"] as? String ?? ""
            companyURL = hiringOrg["sameAs"] as? String
        }
        
        var location: String? = nil
        if let jobLocation = json["jobLocation"] as? [String: Any],
           let address = jobLocation["address"] as? [String: Any] {
            let parts = [
                address["addressLocality"] as? String,
                address["addressRegion"] as? String,
                address["addressCountry"] as? String
            ].compactMap { $0 }
            location = parts.joined(separator: ", ")
        }
        
        let description = json["description"] as? String
        
        var employmentType: String? = nil
        if let type = json["employmentType"] as? String {
            employmentType = type
        } else if let types = json["employmentType"] as? [String] {
            employmentType = types.joined(separator: ", ")
        }
        
        let datePosted = json["datePosted"] as? String
        
        var salary: String? = nil
        if let baseSalary = json["baseSalary"] as? [String: Any],
           let value = baseSalary["value"] as? [String: Any] {
            let minValue = value["minValue"] as? Int ?? 0
            let maxValue = value["maxValue"] as? Int ?? 0
            let currency = baseSalary["currency"] as? String ?? "USD"
            if maxValue > 0 {
                salary = "\(currency) \(minValue) - \(maxValue)"
            }
        }
        
        // Extract additional details from HTML
        let workplaceType = try parseWorkplaceType(from: doc)
        let experienceLevel = try parseExperienceLevel(from: doc)
        let applicantCount = try parseApplicantCount(from: doc)
        let skills = try parseJobSkills(from: doc)
        let isEasyApply = try !doc.select(".jobs-apply-button--top-card, [data-is-easy-apply]").isEmpty()
        
        return JobDetails(
            id: jobId,
            title: title,
            company: company,
            companyURL: companyURL,
            location: location,
            workplaceType: workplaceType,
            employmentType: employmentType,
            experienceLevel: experienceLevel,
            postedDate: datePosted,
            applicantCount: applicantCount,
            salary: salary,
            description: cleanDescription(description),
            skills: skills,
            isEasyApply: isEasyApply,
            jobURL: "\(baseURL)/jobs/view/\(jobId)/"
        )
    }
    
    private static func parseJobFromHTML(_ doc: Document, jobId: String) throws -> JobDetails {
        // Title
        let title = try doc.select("h1.topcard__title, h1.t-24, .job-details-jobs-unified-top-card__job-title")
            .first()?.text() ?? ""
        
        // Company
        let companyElement = try doc.select("a.topcard__org-name-link, a[href*=/company/]").first()
        let company = try companyElement?.text() ?? ""
        let companyURL = try companyElement?.attr("href")
        
        // Location
        let location = try doc.select(".topcard__flavor--bullet, .job-details-jobs-unified-top-card__primary-description-without-tagline span")
            .first()?.text()
        
        // Description
        let descriptionElement = try doc.select(".description__text, .jobs-description__content, .jobs-box__html-content")
            .first()
        let description = try descriptionElement?.text()
        
        // Posted date
        let postedDate = try doc.select(".posted-time-ago__text, time").first()?.text()
        
        // Other details
        let workplaceType = try parseWorkplaceType(from: doc)
        let employmentType = try parseEmploymentType(from: doc)
        let experienceLevel = try parseExperienceLevel(from: doc)
        let applicantCount = try parseApplicantCount(from: doc)
        let salary = try parseSalary(from: doc)
        let skills = try parseJobSkills(from: doc)
        let isEasyApply = try !doc.select(".jobs-apply-button, [data-is-easy-apply]").isEmpty()
        
        return JobDetails(
            id: jobId,
            title: title,
            company: company,
            companyURL: companyURL,
            location: location,
            workplaceType: workplaceType,
            employmentType: employmentType,
            experienceLevel: experienceLevel,
            postedDate: postedDate,
            applicantCount: applicantCount,
            salary: salary,
            description: description,
            skills: skills,
            isEasyApply: isEasyApply,
            jobURL: "\(baseURL)/jobs/view/\(jobId)/"
        )
    }
    
    private static func parseWorkplaceType(from doc: Document) throws -> String? {
        let workplaceElement = try doc.select(".job-details-jobs-unified-top-card__workplace-type, span:contains(Remote), span:contains(On-site), span:contains(Hybrid)")
            .first()
        return try workplaceElement?.text()
    }
    
    private static func parseEmploymentType(from doc: Document) throws -> String? {
        let typeElement = try doc.select("li.job-criteria__item:contains(Employment type) span.job-criteria__text")
            .first()
        return try typeElement?.text()
    }
    
    private static func parseExperienceLevel(from doc: Document) throws -> String? {
        let levelElement = try doc.select("li.job-criteria__item:contains(Seniority level) span.job-criteria__text")
            .first()
        return try levelElement?.text()
    }
    
    private static func parseApplicantCount(from doc: Document) throws -> String? {
        let applicantElement = try doc.select(".jobs-unified-top-card__applicant-count, .num-applicants__caption")
            .first()
        return try applicantElement?.text()
    }
    
    private static func parseSalary(from doc: Document) throws -> String? {
        let salaryElement = try doc.select(".job-details-jobs-unified-top-card__job-insight--highlight, .compensation__salary")
            .first()
        return try salaryElement?.text()
    }
    
    private static func parseJobSkills(from doc: Document) throws -> [String] {
        var skills: [String] = []
        
        let skillElements = try doc.select(".job-details-skill-match-status-list__skill, .jobs-ppc-criteria__skill")
        
        for element in skillElements.prefix(15) {
            let skill = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !skill.isEmpty {
                skills.append(skill)
            }
        }
        
        return skills
    }
    
    private static func cleanDescription(_ text: String?) -> String? {
        guard let text = text else { return nil }
        
        // Unescape HTML entities
        var cleaned = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        
        // Remove excessive whitespace
        cleaned = cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return cleaned.isEmpty ? nil : cleaned
    }
}
