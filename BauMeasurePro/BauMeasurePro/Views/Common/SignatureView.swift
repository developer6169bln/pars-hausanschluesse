import SwiftUI

/// Einfaches Unterschrifts-Pad für den Kunden im Projekt.
struct SignatureView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (UIImage) -> Void

    @State private var lines: [[CGPoint]] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                signatureContent
            }
            .navigationTitle("Unterschrift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(lines.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Löschen") { lines.removeAll() }
                }
            }
        }
    }

    private var signatureContent: some View {
        // gleiche Seitenverhältnisse wie im PDF: Breite ca. 515, Höhe ca. 60 → Faktor ~ 8,6
        let aspect: CGFloat = 515.0 / 60.0
        return GeometryReader { geo in
            let width = min(geo.size.width - 32, geo.size.height * aspect)
            let height = width / aspect
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.gray.opacity(0.4), lineWidth: 1)
                    .background(Color.white)
                Path { path in
                    for line in lines {
                        guard let first = line.first else { continue }
                        path.move(to: first)
                        for pt in line.dropFirst() {
                            path.addLine(to: pt)
                        }
                    }
                }
                .stroke(Color.black, lineWidth: 2)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = value.location
                        if lines.isEmpty {
                            lines.append([point])
                        } else {
                            lines[lines.count - 1].append(point)
                        }
                    }
                    .onEnded { _ in
                        lines.append([])
                    }
            )
            .padding()
        }
    }

    private func save() {
        // Bildgröße wie im PDF: 515 x 60 pt, hohe Auflösung durch scale 2
        let renderer = ImageRenderer(content: signatureContent.frame(width: 515, height: 60))
        renderer.scale = 2
        if let uiImage = renderer.uiImage {
            onSave(uiImage)
            dismiss()
        }
    }
}

