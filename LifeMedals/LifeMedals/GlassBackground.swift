import SwiftUI

/// A bright canvas that gives the system glass material just enough depth to refract.
struct GlassBackground: View {
    var body: some View {
        ZStack {
            Color.white

            Circle()
                .fill(Color(red: 0.80, green: 0.91, blue: 1.00).opacity(0.62))
                .frame(width: 540, height: 540)
                .blur(radius: 120)
                .offset(x: -390, y: -270)

            Circle()
                .fill(Color(red: 0.84, green: 0.98, blue: 0.92).opacity(0.52))
                .frame(width: 480, height: 480)
                .blur(radius: 125)
                .offset(x: 390, y: 270)

            Circle()
                .fill(Color(red: 1.00, green: 0.91, blue: 0.78).opacity(0.28))
                .frame(width: 380, height: 380)
                .blur(radius: 130)
                .offset(x: 330, y: -300)

            Rectangle()
                .fill(.white.opacity(0.18))
                .background(.ultraThinMaterial)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
    }
}
