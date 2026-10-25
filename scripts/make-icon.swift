import AppKit
import SwiftUI

// macOS icon grid: 1024 canvas, 824 body, ~185 corner radius.
struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.48, blue: 0.38), Color(red: 0.88, green: 0.30, blue: 0.22)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 3)
                .frame(width: 824, height: 824)
            HStack(spacing: 34) {
                ForEach([0.30, 0.55, 0.85, 1.0, 0.75, 0.50, 0.28], id: \.self) { h in
                    Capsule().fill(.white).frame(width: 48, height: 470 * h)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .frame(width: 1024, height: 1024)
    }
}

let out = CommandLine.arguments[1]
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
