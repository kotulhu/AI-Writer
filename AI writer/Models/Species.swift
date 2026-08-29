import Foundation

enum Species: String, Codable, CaseIterable, Identifiable {
    case human
    case animal
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .human: "Человек"
        case .animal: "Животное"
        case .other: "Другое"
        }
    }

    var icon: String {
        switch self {
        case .human: "figure.stand"
        case .animal: "pawprint"
        case .other: "sparkles"
        }
    }
}