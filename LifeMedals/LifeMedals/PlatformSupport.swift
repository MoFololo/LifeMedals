import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Keeps platform image decoding in one place so feature views remain shared.
struct PlatformImageView: View {
    let data: Data

    var body: some View {
#if os(macOS)
        if let image = NSImage(data: data) {
            Image(nsImage: image).resizable()
        } else {
            fallback
        }
#elseif os(iOS)
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable()
        } else {
            fallback
        }
#endif
    }

    private var fallback: some View {
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
    }
}

extension View {
    @ViewBuilder
    func onMacPasteImages(perform: @escaping ([NSItemProvider]) -> Void) -> some View {
#if os(macOS)
        onPasteCommand(of: [.image], perform: perform)
#else
        self
#endif
    }

    @ViewBuilder
    func macOSMinimumWindowSize(width: CGFloat, height: CGFloat) -> some View {
#if os(macOS)
        frame(minWidth: width, minHeight: height)
#else
        self
#endif
    }

    @ViewBuilder
    func platformSheetWidth(_ width: CGFloat) -> some View {
#if os(macOS)
        frame(width: width)
#else
        frame(maxWidth: width)
#endif
    }

    /// A vertical `ScrollView` proposes an unconstrained horizontal ideal size
    /// on iOS. Clamp page bodies to the visible container so desktop max-width
    /// cards cannot make an iPhone page wider than its screen.
    @ViewBuilder
    func platformScrollableContentWidth(_ maximum: CGFloat) -> some View {
#if os(iOS)
        containerRelativeFrame(.horizontal) { available, _ in
            min(available, maximum)
        }
#else
        frame(maxWidth: maximum)
#endif
    }

    @ViewBuilder
    func platformOverlayPanelSize(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
#if os(iOS)
        frame(maxWidth: .infinity, maxHeight: .infinity)
#else
        frame(maxWidth: maxWidth, maxHeight: maxHeight)
#endif
    }

    /// Camera capture owns the phone screen while retaining the lightweight
    /// desktop sheet presentation.
    @ViewBuilder
    func platformCameraPresentation<Presented: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Presented
    ) -> some View {
#if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
#else
        sheet(isPresented: isPresented, content: content)
#endif
    }

    @ViewBuilder
    func iOSFullScreenCover<Item: Identifiable, Presented: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Presented
    ) -> some View {
#if os(iOS)
        fullScreenCover(item: item, content: content)
#else
        self
#endif
    }
}
