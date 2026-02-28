import Foundation

/// ComputerSearchProfile declaration.
struct ComputerSearchProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var fieldKeys: [String]
    var createdAt: Date

    /// Initializes the instance.
    init(
        id: UUID = UUID(),
        name: String,
        fieldKeys: [String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.fieldKeys = fieldKeys.sorted()
        self.createdAt = createdAt
    }
}

//endofline
