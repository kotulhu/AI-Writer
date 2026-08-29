import Foundation
import SwiftData

@Model
final class Character {
    var id: UUID
    var name: String = ""
    var species: Species = Species.human
    var isMale: Bool = true
    var age: String?
    var height: String?
    var weight: String?
    var hairColor: String?
    var hairLength: String?
    var appearanceDescription: String?
    var clothingPreference: String?
    var createdAt: Date
    var updatedAt: Date

    var manuscript: Manuscript?

    init(
        id: UUID = UUID(),
        manuscript: Manuscript? = nil,
        name: String = "",
        species: Species = .human,
        isMale: Bool = true,
        age: String? = nil,
        height: String? = nil,
        weight: String? = nil,
        hairColor: String? = nil,
        hairLength: String? = nil,
        appearanceDescription: String? = nil,
        clothingPreference: String? = nil,
        now: Date = .now
    ) {
        self.id = id
        self.manuscript = manuscript
        self.name = name
        self.species = species
        self.isMale = isMale
        self.age = age
        self.height = height
        self.weight = weight
        self.hairColor = hairColor
        self.hairLength = hairLength
        self.appearanceDescription = appearanceDescription
        self.clothingPreference = clothingPreference
        self.createdAt = now
        self.updatedAt = now
    }
}