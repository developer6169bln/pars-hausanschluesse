import SwiftUI

struct PhotoMeasureView: View {
    var image: UIImage
    @Binding var points: [CGPoint]

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()

                // Linie zwischen den Messpunkten (verbindet Punkte der Reihe nach)
                if points.count >= 2 {
                    Path { path in
                        path.move(to: points[0])
                        for i in 1 ..< points.count {
                            path.addLine(to: points[i])
                        }
                    }
                    .stroke(.red, lineWidth: 3)
                }

                ForEach(points.indices, id: \.self) { i in
                    Circle()
                        .fill(.red)
                        .frame(width: 12, height: 12)
                        .position(points[i])
                }
            }
            .onTapGesture { location in
                points.append(location)
            }
        }
    }
}
