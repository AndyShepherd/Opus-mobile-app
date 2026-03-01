import Foundation

/// A time entry logged against a client or non-client activity.
/// Uses custom decoding because the backend may omit any field — defaults prevent crashes.
struct TimeEntry: Codable, Identifiable {
    let id: String
    let userId: String
    let forUserID: String
    let forUsername: String
    let date: String           // "YYYY-MM-DD"
    let units: Int
    let customerId: String
    let customerName: String
    let serviceCode: String
    let activityCode: String
    let billableRateCode: String
    let notes: String
    let createdAt: String
    let updatedAt: String

    /// True when this entry is logged against a client (not a non-client activity)
    var isClientWork: Bool { !customerId.isEmpty }

    /// Display label: client name for client work, activity code for non-client work
    var workLabel: String {
        isClientWork ? customerName : activityCode
    }

    /// Human-readable duration, e.g. "2 units (0 hrs 30 min)"
    var durationText: String {
        let totalMinutes = units * 15
        let hrs = totalMinutes / 60
        let mins = totalMinutes % 60
        return "\(units) units (\(hrs) hrs \(mins) min)"
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, forUserID, forUsername, date, units
        case customerId, customerName, serviceCode, activityCode
        case billableRateCode, notes, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? ""
        forUserID = try container.decodeIfPresent(String.self, forKey: .forUserID) ?? ""
        forUsername = try container.decodeIfPresent(String.self, forKey: .forUsername) ?? ""
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        units = try container.decodeIfPresent(Int.self, forKey: .units) ?? 0
        customerId = try container.decodeIfPresent(String.self, forKey: .customerId) ?? ""
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName) ?? ""
        serviceCode = try container.decodeIfPresent(String.self, forKey: .serviceCode) ?? ""
        activityCode = try container.decodeIfPresent(String.self, forKey: .activityCode) ?? ""
        billableRateCode = try container.decodeIfPresent(String.self, forKey: .billableRateCode) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

/// POST body for creating a new time entry. Backend auto-sets forUserID/forUsername from JWT.
struct TimeEntryPayload: Encodable {
    let date: String
    let units: Int
    let customerId: String
    let serviceCode: String
    let activityCode: String
    let notes: String
}

/// A non-client activity (e.g. "Admin", "Training") from GET /api/time/activities
struct NonClientActivity: Codable, Identifiable {
    let id: String
    let code: String
    let name: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, code, name, isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }
}

/// A service from the catalogue (e.g. "Accounts Production") from GET /api/services
struct ServiceDefinition: Codable, Identifiable {
    let id: String
    let code: String
    let name: String
    let category: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, code, name, category, isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }
}
