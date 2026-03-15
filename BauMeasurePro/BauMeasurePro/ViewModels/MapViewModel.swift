import Foundation
import CoreLocation

class MapViewModel: ObservableObject {
    @Published var projects: [Project] = []

    /// Alle Messungen aus allen Projekten (z. B. für die Karte).
    var allMeasurements: [Measurement] {
        projects.flatMap(\.measurements)
    }

    func addProject(_ project: Project) {
        projects.append(project)
    }

    func deleteProject(id: UUID) {
        projects.removeAll { $0.id == id }
    }

    func addMeasurement(toProjectId projectId: UUID, _ measurement: Measurement) {
        guard let i = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[i].measurements.append(measurement)
    }

    func updateMeasurement(projectId: UUID, _ measurement: Measurement) {
        guard let pIndex = projects.firstIndex(where: { $0.id == projectId }) else { return }
        guard let mIndex = projects[pIndex].measurements.firstIndex(where: { $0.id == measurement.id }) else { return }
        projects[pIndex].measurements[mIndex] = measurement
    }

    func deleteMeasurement(projectId: UUID, measurementId: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[i].measurements.removeAll { $0.id == measurementId }
    }

    func deleteThreeDScan(projectId: UUID, scanId: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == projectId }) else { return }
        var proj = projects[i]
        proj.threeDScans.removeAll { $0.id == scanId }
        projects[i] = proj
    }

    func updateProject(_ project: Project) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i] = project
    }

    func project(byId id: UUID) -> Project? {
        projects.first { $0.id == id }
    }
}
