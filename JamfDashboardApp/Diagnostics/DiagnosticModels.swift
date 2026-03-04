import Foundation

/// DiagnosticSeverity declaration.
enum DiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case error
}

/// DiagnosticEvent declaration.
struct DiagnosticEvent: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let source: String
    let category: String
    let severity: DiagnosticSeverity
    let message: String
    let metadata: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case source
        case category
        case severity
        case message
        case metadata
    }

    nonisolated init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: String,
        category: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.category = category
        self.severity = severity
        self.message = message
        self.metadata = metadata
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        source = try container.decode(String.self, forKey: .source)
        category = try container.decode(String.self, forKey: .category)
        severity = try container.decode(DiagnosticSeverity.self, forKey: .severity)
        message = try container.decode(String.self, forKey: .message)
        metadata = try container.decode([String: String].self, forKey: .metadata)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(source, forKey: .source)
        try container.encode(category, forKey: .category)
        try container.encode(severity, forKey: .severity)
        try container.encode(message, forKey: .message)
        try container.encode(metadata, forKey: .metadata)
    }
}

//endofline
