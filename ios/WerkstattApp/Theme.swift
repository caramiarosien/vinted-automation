import SwiftUI
import UIKit
import WerkstattCore

enum WerkstattTheme {
    static let paper = Color(red: 0.97, green: 0.95, blue: 0.90)
    static let ink = Color(red: 0.13, green: 0.23, blue: 0.18)
    static let accent = Color(red: 0.19, green: 0.36, blue: 0.27)
    static let muted = Color(red: 0.38, green: 0.43, blue: 0.38)
    static let line = Color(red: 0.86, green: 0.86, blue: 0.80)
    static let title = Font.system(.largeTitle, design: .serif, weight: .medium)
    static let heading = Font.system(.title2, design: .serif, weight: .medium)
}

struct PaperCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(WerkstattTheme.line, lineWidth: 1))
    }
}

struct SectionHeading: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(WerkstattTheme.heading).foregroundStyle(WerkstattTheme.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(WerkstattTheme.muted) }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).padding(.vertical, 15).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .background(WerkstattTheme.accent.opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct StatusBadge: View {
    var text: String
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(WerkstattTheme.accent)
            .background(WerkstattTheme.accent.opacity(0.09), in: Capsule())
    }
}

struct PhotoThumbnail: View {
    var url: URL?
    var fit: ContentMode = .fill
    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: fit)
            } else {
                ZStack {
                    WerkstattTheme.line.opacity(0.4)
                    Image(systemName: "photo").font(.title2).foregroundStyle(WerkstattTheme.muted)
                }
            }
        }.clipped()
    }
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

extension View {
    func workshopBackground() -> some View {
        self.background(WerkstattTheme.paper.ignoresSafeArea()).tint(WerkstattTheme.accent)
    }
}
