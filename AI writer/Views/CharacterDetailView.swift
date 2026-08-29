import SwiftData
import SwiftUI

struct CharacterDetailView: View {
    @Bindable var character: Character
    @Bindable var store: ManuscriptStore
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section("Базовое") {
                TextField("Имя", text: $character.name)
                Picker("Вид", selection: $character.species) {
                    ForEach(Species.allCases) { species in
                        Label(species.label, systemImage: species.icon).tag(species)
                    }
                }
                Picker("Пол", selection: $character.isMale) {
                    Text("Мужской").tag(true)
                    Text("Женский").tag(false)
                }
                .pickerStyle(.segmented)
            }
            Section("Параметры") {
                textField("Возраст", keyPath: \.age, placeholder: "например, «около тридцати» или «неизвестен»")
                textField("Рост", keyPath: \.height, placeholder: "например, «178 см»")
                textField("Вес", keyPath: \.weight, placeholder: "например, «70 кг»")
                textField("Цвет волос", keyPath: \.hairColor, placeholder: "например, «тёмно-русый»")
                textField("Длина волос", keyPath: \.hairLength, placeholder: "например, «короткие», «до плеч», «лысый»")
            }
            Section("Внешность") {
                TextEditor(text: optionalField(\.appearanceDescription))
                    .frame(minHeight: 90)
                    .overlay(alignment: .topLeading) {
                        if character.appearanceDescription?.isEmpty != false {
                            Text("Общее описание внешности")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
            }
            Section("Одежда") {
                TextEditor(text: optionalField(\.clothingPreference))
                    .frame(minHeight: 90)
                    .overlay(alignment: .topLeading) {
                        if character.clothingPreference?.isEmpty != false {
                            Text("Стиль и предпочтения в одежде")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(character.name.isEmpty ? "Персонаж" : character.name)
        .onChange(of: character.name) {
            store.scheduleCharacterSave(character, context: context)
        }
        .onChange(of: character.species) {
            store.scheduleCharacterSave(character, context: context)
        }
        .onChange(of: character.isMale) {
            store.scheduleCharacterSave(character, context: context)
        }
        .onDisappear {
            store.saveCharacterNow(character, context: context)
        }
    }

    private func textField(_ title: String, keyPath: ReferenceWritableKeyPath<Character, String?>, placeholder: String) -> some View {
        TextField(title, text: optionalField(keyPath), prompt: Text(placeholder))
    }

    /// Binding that maps optional String fields to a non-optional text and
    /// schedules a debounced save on every keystroke.
    private func optionalField(_ keyPath: ReferenceWritableKeyPath<Character, String?>) -> Binding<String> {
        Binding(
            get: { character[keyPath: keyPath] ?? "" },
            set: { newValue in
                character[keyPath: keyPath] = newValue
                store.scheduleCharacterSave(character, context: context)
            }
        )
    }
}