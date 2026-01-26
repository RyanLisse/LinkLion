# LinkedIn Voyager API Reference & Reverse Engineering Guide

This document contains all necessary information to reimplement the LinkedIn Client from scratch using the internal "Voyager" API.

## 1. Prerequisites & Authentication

The Voyager API does **not** use OAuth. It uses standard browser session cookies.

### 1.1 Getting Credentials

1. Log in to [linkedin.com](https://www.linkedin.com) in your browser.
2. Open Developer Tools (F12) -> Application -> Cookies.
3. Copy the values of:
    * `li_at`: The main authentication token.
    * `JSESSIONID`: The session identifier (needed for CSRF).

### 1.2 Request Headers

Every request **MUST** include these headers:

```http
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36
Csrf-Token: <JSESSIONID_VALUE_WITHOUT_QUOTES>
X-RestLi-Protocol-Version: 2.0.0
X-Li-Lang: en_US
Accept: application/vnd.linkedin.normalized+json+2.1
Cookie: li_at=<YOUR_LI_AT>; JSESSIONID="<YOUR_JSESSIONID>";
```

> **Note**: The `Csrf-Token` header matches the `JSESSIONID` cookie but **must not** have surrounding quotes.

## 2. API Endpoints (Voyager)

**Base URL**: `https://www.linkedin.com/voyager/api`

### 2.1 Identity (WhoAmI & Profiles)

| Action | HTTP | Path | Details |
| :--- | :--- | :--- | :--- |
| **WhoAmI** | `GET` | `/me` | Redirects/returns basic info. Use `/identity/profiles/me/profileView` for full details. |
| **Full Profile** | `GET` | `/identity/profiles/{public_id}/profileView` | Returns `profile` (main), `positionView` (experience), `educationView`, `skillView`. |
| **Network Info** | `GET` | `/identity/profiles/{public_id}/networkinfo` | counts connections (`distance`, `followersCount`). |

**Parsing Profile JSON**:
The `profileView` response is split into "views".
* `data.profile.miniProfile`: Contains `publicIdentifier` (public ID) and `entityUrn`.
* `data.positionView.elements`: Array of jobs.
* `data.educationView.elements`: Array of schools.

### 2.2 Organization (Companies)

**Endpoint**: `/organization/companies`
**Query Parameters**:
* `q=universalName`: Search by handle.
* `universalName={handle}`: The company handle (e.g., `airbnb`).
* `decorationId=...`: (Optional) Specifies field expansion.

**Response**:
Wrapped in `elements:[ { ... } ]`. Key fields: `name`, `description`, `industry`, `followerCount`, `logo`.

### 2.3 Search (Complex)

Search uses specific "Cluster" endpoints or GraphQL.

#### People Search (`/search/blended`)

- **Query**: `q=blended`, `filters=List(resultType->PEOPLE)`, `keywords={term}`.
* **Parsing**: The response is a "CollectionResponse". Iterating `elements` -> `elements` -> `type:SEARCH_RESULT` is required.

#### Job Search (`/voyagerJobsDashJobCards`)

This endpoint uses a complex "query string" parameter that mimics a serialized object.

**Structure**:

```text
(
  origin:JOB_SEARCH_PAGE_QUERY_EXPANSION,
  keywords:{KEYWORDS},
  selectedFilters:(
     timePostedRange:List(r86400)
  ),
  spellCorrectionEnabled:true
)
```

**Tip**: You must URL-encode this entire string structure as the `query` parameter.

### 2.4 Connections & Invitations

#### Send Invitation (`POST`)

**Endpoint**: `/voyagerRelationshipsDashMemberRelationships`
**Action parameter**: `?action=verifyQuotaAndCreateV2`
**Payload**:

```json
{
  "invitee": {
    "inviteeUnion": {
      "memberProfile": "urn:li:fsd_profile:ACoAA..."
    }
  },
  "customMessage": "Hello!"
}
```

> **Critical**: You must use the full URN (`urn:li:fsd_profile:...`). This URN is found in the `miniProfile.entityUrn` of a user's profile or search result, often requiring transformation from `fs_miniProfile` to `fsd_profile`.

### 2.5 Messaging

#### Send Message (`POST`)

**Endpoint**: `/messaging/conversations` (New conversation) or `/messaging/conversations/{urn}/events` (Reply).
**Payload (New)**:

```json
{
  "keyVersion": "LEGACY_INBOX",
  "conversationCreate": {
    "eventCreate": {
      "value": {
        "com.linkedin.voyager.messaging.create.MessageCreate": {
          "attributedBody": { "text": "Message content" }
        }
      },
       "originToken": "<UUID>"
    },
    "recipients": ["urn:li:fsd_profile:..."],
    "subtype": "MEMBER_TO_MEMBER"
  }
}
```

## 3. Implementation checklist (From Scratch)

1. [ ] **Cookie Store**: Implement a secure way to load `li_at` and `JSESSIONID` (e.g., from Env Vars).
2. [ ] **Network Client**: Create a wrapper around `URLSession` (Swift) or `requests` (Python) that auto-injects the `Csrf-Token` header.
3. [ ] **URN Handling**: Implement a helper to parse/extract IDs from Strings (e.g., `urn:li:fs_miniProfile:123` -> `123`).
4. [ ] **Models**: Create loose decoding models (using `Optional`) because LinkedIn API schemas change often.
5. [ ] **Throttling**: The Voyager API has strict rate limits. Implement random sleep delays (2-5s) between requests to avoid 429/Suspension.

## 4. Reverse Engineering Tools

To find new endpoints:

1. Open Chrome DevTools -> Network Tab.
2. Filter by `XHR` or `Fetch`.
3. Perform the action on LinkedIn (e.g., "Like" a post).
4. Copy the Request URL and Payload.
5. **Important**: Look for the `q` parameter in GET requests or the `action` parameter in POST requests; these determine the handler.
