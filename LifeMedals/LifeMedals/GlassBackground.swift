import SwiftUI

/// Compatibility wrapper for screens that have not yet moved to `PixelBackground`.
/// Keeping the type during the staged migration avoids touching business screens.
struct GlassBackground: View {
    var body: some View {
        PixelBackground()
    }
}
