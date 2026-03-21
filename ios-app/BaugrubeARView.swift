import SwiftUI
import ARKit
import SceneKit

// MARK: - ViewModel

final class BaugrubeARViewModel: NSObject, ObservableObject {
    @Published var startPoint: simd_float3?
    @Published var endPoint: simd_float3?
    @Published var distanceMeters: Float = 0

    func setPoint(from result: ARHitTestResult) {
        let pos = result.worldTransform.columns.3
        let p = simd_float3(pos.x, pos.y, pos.z)

        if startPoint == nil {
            startPoint = p
            endPoint = nil
            distanceMeters = 0
        } else {
            endPoint = p
            distanceMeters = simd_distance(startPoint!, p)
        }
    }

    func reset() {
        startPoint = nil
        endPoint = nil
        distanceMeters = 0
    }
}

// MARK: - AR View (UIKit)

struct BaugrubeARView: UIViewRepresentable {
    @ObservedObject var viewModel: BaugrubeARViewModel

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.delegate = context.coordinator
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        view.session.run(config)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, ARSCNViewDelegate {
        let viewModel: BaugrubeARViewModel

        init(viewModel: BaugrubeARViewModel) {
            self.viewModel = viewModel
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? ARSCNView else { return }
            let location = gesture.location(in: view)
            let hits = view.hitTest(location, types: [.featurePoint, .estimatedHorizontalPlane])
            if let result = hits.first {
                viewModel.setPoint(from: result)
            }
        }
    }
}

// MARK: - Screen (SwiftUI)

struct BaugrubeARScreen: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = BaugrubeARViewModel()
    let onFinished: (Double) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            BaugrubeARView(viewModel: vm)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Länge: \(vm.distanceMeters, specifier: "%.2f") m")
                    .font(.headline)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)

                Text("Tippe auf Startpunkt, dann auf Endpunkt.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Zurücksetzen") {
                        vm.reset()
                    }
                    .buttonStyle(.bordered)

                    Button("Übernehmen") {
                        onFinished(Double(vm.distanceMeters))
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.distanceMeters <= 0)
                }
            }
            .padding()
        }
    }
}
