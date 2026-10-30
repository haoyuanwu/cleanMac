// swiftc cleanMac/Views/Components/CleanMacLogo.swift Scripts/render_app_icon.swift -o /tmp/render-cleanmac-icon
// /tmp/render-cleanmac-icon <project root>
import SwiftUI
import AppKit

@main
struct RenderAppIcon {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("cleanMac/Assets.xcassets/AppIcon.appiconset")
        for pixels in [16, 32, 64, 128, 256, 512, 1024] {
            let renderer = ImageRenderer(content: CleanMacLogo().frame(width: CGFloat(pixels), height: CGFloat(pixels)))
            renderer.scale = 1
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: output.appendingPathComponent("AppIcon-\(pixels).png"))
            if pixels == 1024 { try png.write(to: root.appendingPathComponent("Design/cleanMac-logo-source.png")) }
        }
    }
}
