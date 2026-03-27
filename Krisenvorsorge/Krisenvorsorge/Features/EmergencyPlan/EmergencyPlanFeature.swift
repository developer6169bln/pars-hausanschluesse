import SwiftUI

struct EmergencyPlanFeature: View {
    @EnvironmentObject private var vm: AppViewModel

    @State private var selectedScenarioId: UUID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.data.scenarioPlans) { plan in
                    Section {
                        NavigationLink(value: plan.id) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Localization.scenarioTitle(for: plan.key, lang: vm.language))
                                        .font(.headline)
                                    Text("\(plan.steps.filter { $0.done }.count)/\(plan.steps.count) ✓")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle(Localization.t("tabEmergencyPlan", lang: vm.language))
            .navigationDestination(for: UUID.self) { scenarioId in
                if let plan = vm.data.scenarioPlans.first(where: { $0.id == scenarioId }) {
                    EmergencyScenarioDetailView(scenarioId: plan.id)
                } else {
                    Text("—")
                }
            }
        }
    }
}

private struct EmergencyScenarioDetailView: View {
    let scenarioId: UUID

    @EnvironmentObject private var vm: AppViewModel

    private var plan: EmergencyScenarioPlan {
        vm.data.scenarioPlans.first(where: { $0.id == scenarioId })!
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Localization.scenarioTitle(for: plan.key, lang: vm.language))
                        .font(.title3.bold())
                    Text("\(plan.steps.filter { $0.done }.count)/\(plan.steps.count) ✓")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                ForEach(plan.steps) { step in
                    Button {
                        vm.toggleEmergencyStepDone(scenarioId: plan.id, stepId: step.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.done ? .green : .secondary)
                            Text(Localization.emergencyStepText(step, lang: vm.language))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

