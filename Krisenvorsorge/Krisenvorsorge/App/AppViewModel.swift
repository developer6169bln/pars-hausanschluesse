import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var data: AppData

    private let store = AppDataStore()

    init() {
        self.data = store.load() ?? AppData.sample
    }

    var language: AppLanguage {
        get { data.language }
        set {
            data.language = newValue
            persist()
        }
    }

    func persist() {
        store.save(data)
    }

    func setLanguage(_ language: AppLanguage) {
        data.language = language
        persist()
    }

    func toggleEmergencyStepDone(scenarioId: UUID, stepId: UUID) {
        for idx in data.scenarioPlans.indices {
            if data.scenarioPlans[idx].id == scenarioId {
                for stepIdx in data.scenarioPlans[idx].steps.indices {
                    if data.scenarioPlans[idx].steps[stepIdx].id == stepId {
                        data.scenarioPlans[idx].steps[stepIdx].done.toggle()
                        persist()
                        return
                    }
                }
            }
        }
    }

    func setInventoryQuantity(itemId: UUID, quantity: Int) {
        for idx in data.inventory.indices {
            if data.inventory[idx].id == itemId {
                data.inventory[idx].quantity = max(0, quantity)
                persist()
                return
            }
        }
    }
}

