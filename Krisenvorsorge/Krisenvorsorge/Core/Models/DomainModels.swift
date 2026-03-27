import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case de, en, tr, ar
    var id: String { rawValue }
}

enum EmergencyScenarioKey: String, CaseIterable, Codable, Identifiable {
    case blackout, evacuation, natureDisaster, homeStay
    var id: String { rawValue }
}

struct EmergencyPlanStep: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var textKey: String
    /// Nutzer hat Schritt als erledigt markiert.
    var done: Bool = false
}

struct EmergencyScenarioPlan: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var key: EmergencyScenarioKey
    var title: String
    var steps: [EmergencyPlanStep]
}

struct EmergencyContact: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var phoneNumber: String
}

struct EmergencyProfile: Codable, Equatable {
    var fullName: String
    var address: String
    var bloodType: String?
    var allergies: String?
    var medications: [String]
    var emergencyContacts: [EmergencyContact]
}

enum InventoryCategoryKey: String, CaseIterable, Codable, Identifiable {
    case water, food, medicine, equipment
    var id: String { rawValue }
}

struct InventoryItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Stable key für Kit-Abgleich (z. B. "water_6l").
    var itemKey: String
    var name: String
    var category: InventoryCategoryKey
    var quantity: Int
    var unit: String
    var essential: Bool
    var expiryDate: Date?
}

enum ShopScenarioKey: String, CaseIterable, Codable, Identifiable {
    case blackout, evacuation, homeStay
    var id: String { rawValue }
}

enum KitLevelKey: String, CaseIterable, Codable, Identifiable {
    case basic, recommended, optimal
    var id: String { rawValue }
}

struct PreparedKitItemRequirement: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Muss zur Inventory.itemKey passen, damit Completion berechnet werden kann.
    var itemKey: String
    var quantity: Int
}

struct PreparedKit: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var scenario: ShopScenarioKey
    var persons: Int
    var durationDays: Int
    var level: KitLevelKey
    var description: String
    var items: [PreparedKitItemRequirement]
    var priceEstimate: Double?
    /// Für MVP optional.
    var affiliateLink: String?
}

struct HandbookArticle: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var category: String
    var title: String
    var iconName: String
    var paragraphs: [String]
}

enum MeetupKey: String, CaseIterable, Codable, Identifiable {
    case home, backup, outsideCity
    var id: String { rawValue }
}

struct MeetupPoint: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var key: MeetupKey
    var title: String
    var addressOrHint: String
}

struct AppData: Codable, Equatable {
    var language: AppLanguage = .de
    var profile: EmergencyProfile
    var scenarioPlans: [EmergencyScenarioPlan]
    var inventory: [InventoryItem]
    var kits: [PreparedKit]
    var handbook: [HandbookArticle]
    var meetups: [MeetupPoint]

    static var sample: AppData {
        AppData(
            language: .de,
            profile: EmergencyProfile(
                fullName: "Muster Person",
                address: "Musterstraße 1, 12345 Musterstadt",
                bloodType: "0+",
                allergies: nil,
                medications: ["Beispiel: 1x täglich"],
                emergencyContacts: [
                    EmergencyContact(name: "Kontakt 1", phoneNumber: "+49 000 000000"),
                    EmergencyContact(name: "Kontakt 2", phoneNumber: "+49 000 000000")
                ]
            ),
            scenarioPlans: EmergencyScenarioKey.allCases.map { key in
                switch key {
                case .blackout:
                    return EmergencyScenarioPlan(
                        key: .blackout,
                        title: "Stromausfall",
                        steps: [
                            EmergencyPlanStep(textKey: "step_blackout_1"),
                            EmergencyPlanStep(textKey: "step_blackout_2"),
                            EmergencyPlanStep(textKey: "step_blackout_3"),
                            EmergencyPlanStep(textKey: "step_blackout_4")
                        ]
                    )
                case .evacuation:
                    return EmergencyScenarioPlan(
                        key: .evacuation,
                        title: "Evakuierung",
                        steps: [
                            EmergencyPlanStep(textKey: "step_evac_1"),
                            EmergencyPlanStep(textKey: "step_evac_2"),
                            EmergencyPlanStep(textKey: "step_evac_3"),
                            EmergencyPlanStep(textKey: "step_evac_4")
                        ]
                    )
                case .natureDisaster:
                    return EmergencyScenarioPlan(
                        key: .natureDisaster,
                        title: "Naturkatastrophe",
                        steps: [
                            EmergencyPlanStep(textKey: "step_nature_1"),
                            EmergencyPlanStep(textKey: "step_nature_2"),
                            EmergencyPlanStep(textKey: "step_nature_3"),
                            EmergencyPlanStep(textKey: "step_nature_4")
                        ]
                    )
                case .homeStay:
                    return EmergencyScenarioPlan(
                        key: .homeStay,
                        title: "Zuhause bleiben",
                        steps: [
                            EmergencyPlanStep(textKey: "step_home_1"),
                            EmergencyPlanStep(textKey: "step_home_2"),
                            EmergencyPlanStep(textKey: "step_home_3"),
                            EmergencyPlanStep(textKey: "step_home_4")
                        ]
                    )
                }
            },
            inventory: [
                InventoryItem(itemKey: "water_6l", name: "Trinkwasser 6L", category: .water, quantity: 1, unit: "Flaschen", essential: true, expiryDate: nil),
                InventoryItem(itemKey: "food_72h", name: "Essen für 72h", category: .food, quantity: 1, unit: "Set", essential: true, expiryDate: nil),
                InventoryItem(itemKey: "medkit_basic", name: "Erste Hilfe Set", category: .medicine, quantity: 1, unit: "Set", essential: true, expiryDate: nil),
                InventoryItem(itemKey: "flashlight", name: "Taschenlampe", category: .equipment, quantity: 2, unit: "Stk", essential: false, expiryDate: nil)
            ],
            kits: [
                PreparedKit(
                    name: "72h Basis-Notfallpaket",
                    scenario: .blackout,
                    persons: 1,
                    durationDays: 3,
                    level: .basic,
                    description: "Grundversorgung für 72 Stunden (zivil, ohne Panik).",
                    items: [
                        PreparedKitItemRequirement(itemKey: "water_6l", quantity: 2),
                        PreparedKitItemRequirement(itemKey: "food_72h", quantity: 1),
                        PreparedKitItemRequirement(itemKey: "medkit_basic", quantity: 1)
                    ],
                    priceEstimate: 49.99,
                    affiliateLink: nil
                )
            ],
            handbook: [
                HandbookArticle(
                    category: "Grundlagen",
                    title: "Checkliste starten",
                    iconName: "checkmark.circle",
                    paragraphs: [
                        "Öffne den Notfallplan und arbeite die Schritte in Ruhe ab.",
                        "Markiere jeden erledigten Schritt, damit du den Überblick behältst."
                    ]
                ),
                HandbookArticle(
                    category: "Stromausfall",
                    title: "Wasser & Kühlung",
                    iconName: "drop.fill",
                    paragraphs: [
                        "Wasser priorisieren und nicht unnötig verschwenden.",
                        "Kühlen: Tür/Abdeckung so wenig wie möglich öffnen."
                    ]
                )
            ],
            meetups: [
                MeetupPoint(key: .home, title: "Zuhause", addressOrHint: "Wohnadresse oder vereinbarter Haus-Eingang"),
                MeetupPoint(key: .backup, title: "Backup-Ort", addressOrHint: "Vereinbarter Treffpunkt für den Fall der Trennung"),
                MeetupPoint(key: .outsideCity, title: "Außerhalb der Stadt", addressOrHint: "Optionaler Plan B außerhalb der direkten Gefahrenzone")
            ]
        )
    }
}

