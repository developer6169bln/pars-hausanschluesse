import SwiftUI

class CameraViewModel: ObservableObject {
    @Published var capturedImage: UIImage?
    @Published var isPresentingPicker = false
}
