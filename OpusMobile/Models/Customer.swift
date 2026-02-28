import Foundation

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

struct Customer: Codable, Identifiable, Hashable {
    let id: String
    let clientId: String
    let name: String
    let company: String
    let email: String
    let phone: String
    let clientKind: String
    let type: String
    let active: Bool
    let contacts: [Contact]

    /// The correct display name: company name for companies, personal name for individuals.
    var displayName: String {
        if clientKind == "person" {
            return name
        }
        return company.isEmpty ? name : company
    }

    enum CodingKeys: String, CodingKey {
        case id, clientId, name, company, email, phone, clientKind, type, active, contacts
    }

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
    }
}
