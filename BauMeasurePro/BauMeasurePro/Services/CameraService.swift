import SwiftUI
import PhotosUI

/// Hilfsservice für Fotoauswahl (PhotosPicker / UIImagePickerController)
enum CameraService {
    static func loadImage(from item: PhotosPickerItem?) async -> UIImage? {
        guard let item = item,
              let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return UIImage(data: data)
    }
}
