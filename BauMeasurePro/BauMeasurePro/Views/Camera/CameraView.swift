import SwiftUI
import PhotosUI

struct CameraView: View {
    @Binding var image: UIImage?
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Label("Foto aufnehmen", systemImage: "camera")
        }
        .onChange(of: item) { _, _ in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    image = UIImage(data: data)
                }
            }
        }
    }
}
