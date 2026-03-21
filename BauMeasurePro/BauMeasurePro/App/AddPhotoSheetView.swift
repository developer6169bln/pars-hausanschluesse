import SwiftUI

struct AddPhotoSheetView: View {
    let projectId: UUID
    /// Wird nach erfolgreichem Speichern mit der neuen Foto-Messung aufgerufen; bei Abbruch `nil`.
    var onDismiss: (Measurement?) -> Void = { _ in }

    @EnvironmentObject var viewModel: MapViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationService = LocationService()
    private let storage = StorageService()

    @State private var pickedImage: UIImage?
    @State private var measurePoints: [CGPoint] = []
    @State private var currentAddress = ""
    @State private var showCamera = false
    @State private var showGalleryPicker = false
    @State private var referenceMetersText = ""  // z. B. "10.5" → Anzeige in Metern

    var body: some View {
        NavigationStack {
            Group {
                if let img = pickedImage {
                    measureView(image: img)
                } else {
                    photoSourceMenu
                }
            }
            .navigationTitle("Foto hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { doDismiss(saved: nil) }
                }
                if pickedImage != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") { saveAndDismiss() }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, image: $pickedImage) { showCamera = false }
                .ignoresSafeArea()
        }
        .onDisappear { reset() }
    }

    private var photoSourceMenu: some View {
        VStack(spacing: 24) {
            Text("Foto auswählen")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(spacing: 16) {
                Button {
                    showCamera = true
                } label: {
                    Label("Mit Kamera aufnehmen", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                Button {
                    showGalleryPicker = true
                } label: {
                    Label("Aus Galerie wählen", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            if showGalleryPicker {
                CameraView(image: $pickedImage)
                    .padding(.top, 8)
            }
            Spacer()
        }
        .padding(.top, 20)
    }

    private func measureView(image: UIImage) -> some View {
        let (totalPx, segmentPx) = distanceFromPoints(measurePoints)
        return VStack(spacing: 16) {
            Text(currentAddress.isEmpty ? "Adresse wird ermittelt…" : currentAddress)
                .font(.headline)
            PhotoMeasureView(image: image, points: $measurePoints)
                .frame(minHeight: 300)
            Text("Tippe auf das Bild, um Messpunkte zu setzen (\(measurePoints.count) Punkte)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if measurePoints.count >= 2 {
                VStack(spacing: 8) {
                    Text("Abstand: \(Int(totalPx)) px")
                        .font(.headline)
                    TextField("Tatsächliche Länge in Metern (z. B. 10.5)", text: $referenceMetersText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    if segmentPx.count == 1 {
                        Text("Punkt 1 → 2: \(Int(segmentPx[0])) px")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if segmentPx.count > 1 {
                        ForEach(Array(segmentPx.enumerated()), id: \.offset) { i, len in
                            Text("Segment \(i + 1)→\(i + 2): \(Int(len)) px")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Länge in m eingeben, damit die Messung in Metern angezeigt wird.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            Spacer()
        }
        .padding()
        .onAppear { resolveAddress() }
    }

    private func distanceFromPoints(_ points: [CGPoint]) -> (total: Double, segments: [Double]) {
        guard points.count >= 2 else { return (0, []) }
        var segments: [Double] = []
        var total: Double = 0
        for i in 1 ..< points.count {
            let dx = Double(points[i].x - points[i - 1].x)
            let dy = Double(points[i].y - points[i - 1].y)
            let d = (dx * dx + dy * dy).squareRoot()
            segments.append(d)
            total += d
        }
        return (total, segments)
    }

    private func resolveAddress() {
        guard let loc = locationService.location else {
            currentAddress = "Standort unbekannt"
            return
        }
        locationService.getAddress(from: loc) { addr in
            currentAddress = addr.isEmpty ? "Unbekannte Adresse" : addr
        }
    }

    private func saveAndDismiss() {
        let project = viewModel.project(byId: projectId)
        let projectName = project?.name
        let overlay = StorageService.PhotoOverlayInfo(
            strasse: project?.strasse,
            hausnummer: project?.hausnummer,
            nvtNummer: project?.nvtNummer,
            date: Date()
        )
        guard let img = pickedImage,
              let path = storage.saveImage(img, projectName: projectName, overlay: overlay) else { return }
        // GPS-Daten: optional erfassen (wenn vorhanden).
        let loc = locationService.location
        let lat: Double = loc?.coordinate.latitude ?? 0
        let lon: Double = loc?.coordinate.longitude ?? 0
        let horizAcc = loc?.horizontalAccuracy
        let vertAcc = loc?.verticalAccuracy
        let alt = loc?.altitude
        let course = loc?.course
        let courseAcc = loc?.courseAccuracy
        let (totalPx, segmentPx) = distanceFromPoints(measurePoints)
        var photoPoints: [PhotoPoint] = []
        for (i, pt) in measurePoints.enumerated() {
            let dist = i == 0 ? 0.0 : (i <= segmentPx.count ? segmentPx[i - 1] : 0)
            photoPoints.append(PhotoPoint(x: Double(pt.x), y: Double(pt.y), distance: dist))
        }
        let refM = Double(referenceMetersText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        let refMeters: Double? = (refM != nil && refM! > 0) ? refM! : nil
        var m = Measurement(
            imagePath: path,
            latitude: lat,
            longitude: lon,
            horizontalAccuracy: horizAcc,
            verticalAccuracy: vertAcc,
            altitude: alt,
            course: course,
            courseAccuracy: courseAcc,
            address: currentAddress,
            points: photoPoints,
            totalDistance: totalPx,
            referenceMeters: refMeters,
            date: Date()
        )
        if let project = viewModel.project(byId: projectId) {
            let nextIndex = project.measurements.count + 1
            m.index = nextIndex
        }
        // Foto-Messungen: keine Start-/End-GPS-Koordinaten.
        viewModel.addMeasurement(toProjectId: projectId, m)
        doDismiss(saved: m)
    }

    private func doDismiss(saved: Measurement?) {
        reset()
        onDismiss(saved)
        dismiss()
    }

    private func reset() {
        pickedImage = nil
        measurePoints = []
        currentAddress = ""
        showCamera = false
        showGalleryPicker = false
        referenceMetersText = ""
    }
}
