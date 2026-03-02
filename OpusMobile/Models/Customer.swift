import Foundation

/// A service assigned to a client (e.g. "accounts_production", "vat_service").
struct ServiceAssignment: Codable, Hashable {
    let serviceCode: String

    enum CodingKeys: String, CodingKey {
        case serviceCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serviceCode = try container.decodeIfPresent(String.self, forKey: .serviceCode) ?? ""
    }
}

/// A named contact within a company client (e.g. director, accountant).
/// Uses custom decoding because the backend may omit any field — defaults prevent crashes.
struct Contact: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    let email: String
    let phone: String
    let mobile: String
    let isPrimary: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, role, email, phone, mobile, isPrimary
    }

    // Custom decoder: every field is optional in the API response, so we default missing values
    // to empty strings (or a generated UUID for id) to avoid nil-handling throughout the UI.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        mobile = try container.decodeIfPresent(String.self, forKey: .mobile) ?? ""
        isPrimary = try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
    }
}

/// A client record. `clientKind` is "person" or "company", determining display logic throughout the app.
/// Hashable conformance is needed for NavigationLink(value:) in the client list.
struct Customer: Codable, Identifiable, Hashable {
    let id: String
    let clientId: String      // User-facing code like "ABC001"
    let name: String           // Personal name (always present)
    let company: String        // Company name (empty for individuals)
    let email: String
    let phone: String
    let clientKind: String     // "person" or "company" — drives UI branching
    let type: String           // e.g. "Limited Company", "Sole Trader", "Partnership"
    let active: Bool
    let contacts: [Contact]    // Company contacts — empty for individuals
    let services: [ServiceAssignment]  // Assigned services from the service catalogue

    /// Display name: individuals show their personal name, companies show their company name
    /// (falling back to personal name if company is somehow empty).
    var displayName: String {
        if clientKind == "person" {
            return name
        }
        return company.isEmpty ? name : company
    }

    enum CodingKeys: String, CodingKey {
        case id, clientId, name, company, email, phone, clientKind, type, active, contacts, services
    }

    // Custom decoder for the same reason as Contact — the backend's MongoDB documents
    // may lack fields, so we default everything except `id` (which is always present).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        clientId = try container.decodeIfPresent(String.self, forKey: .clientId) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        company = try container.decodeIfPresent(String.self, forKey: .company) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        clientKind = try container.decodeIfPresent(String.self, forKey: .clientKind) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        contacts = try container.decodeIfPresent([Contact].self, forKey: .contacts) ?? []
        services = try container.decodeIfPresent([ServiceAssignment].self, forKey: .services) ?? []
    }
}

/// Generic wrapper for paginated API responses.
/// The backend returns `{ items, total, page, limit }` when pagination params are provided.
struct PaginatedResponse<T: Decodable>: Decodable {
    let items: [T]
    let total: Int
    let page: Int
    let limit: Int
}
