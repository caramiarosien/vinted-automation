import SwiftUI
import UIKit
import WerkstattCore

struct ListingPreview: View {
    let itemID: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var platform: Platform = .vinted
    @State private var copied: String?
    private var tint: Color { platform == .vinted ? Color(red: 0.02, green: 0.45, blue: 0.48) : WerkstattTheme.accent }

    var body: some View {
        Group {
            if let item = model.item(id: itemID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if item.priceType != .free {
                            Picker("Plattform für die Vorschau", selection: $platform) {
                                Text("Vinted").tag(Platform.vinted)
                                Text("Kleinanzeigen").tag(Platform.kleinanzeigen)
                            }.pickerStyle(.segmented).accessibilityIdentifier("preview.platform")
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text(platform.label).font(.headline).foregroundStyle(tint)
                                Spacer(); Text("Beispielansicht").font(.caption).foregroundStyle(.secondary)
                            }.padding(16)
                            let images = photos(item)
                            if images.isEmpty {
                                PhotoThumbnail(url: nil).frame(height: 260)
                            } else {
                                TabView {
                                    ForEach(Array(images.enumerated()), id: \.element.id) { index, photo in
                                        PhotoThumbnail(url: model.photoURL(photo), fit: .fit)
                                            .accessibilityLabel("Vorschaufoto \(index + 1) von \(images.count)")
                                    }
                                }.frame(height: 310).tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
                                    .background(Color.white).accessibilityIdentifier("preview.photos")
                            }
                            VStack(alignment: .leading, spacing: 16) {
                                if platform == .kleinanzeigen { price(item) }
                                Text(item.title.isEmpty ? item.kind.label : item.title).font(.title3.weight(.semibold)).accessibilityIdentifier("preview.title")
                                if platform == .vinted { price(item) }
                                HStack(spacing: 8) {
                                    if !item.condition.isEmpty { StatusBadge(text: item.condition) }
                                    if !item.brand.isEmpty { StatusBadge(text: item.brand) }
                                }
                                if platform == .kleinanzeigen, ["pickup", "both"].contains(item.answers["delivery"] ?? "") {
                                    Label(model.library.defaultLocation, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Divider()
                                Text("Beschreibung").font(.headline)
                                Text(item.description.isEmpty ? "Eine Beschreibung fehlt noch." : item.description)
                                    .font(.body).textSelection(.enabled).accessibilityIdentifier("preview.description")
                            }.padding(18)
                        }.background(.white, in: RoundedRectangle(cornerRadius: 20))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        HStack {
                            Button { UIPasteboard.general.string = item.title; copied = "title" } label: { Label(copied == "title" ? "Kopiert" : "Titel kopieren", systemImage: "doc.on.doc") }
                            Spacer()
                            Button { UIPasteboard.general.string = item.description; copied = "text" } label: { Label(copied == "text" ? "Kopiert" : "Text kopieren", systemImage: "doc.on.doc") }
                        }.font(.subheadline)
                        Button {
                            var update = item; update.platform = platform
                            model.saveItem(update)
                        } label: {
                            Text(item.platform == platform ? "\(platform.label) als Ziel gewählt" : "Für \(platform.label) vorbereiten")
                        }.buttonStyle(PrimaryButtonStyle()).disabled(item.platform == platform)
                            .accessibilityIdentifier("preview.usePlatform")
                    }.padding(20)
                }.workshopBackground()
                .onAppear { platform = item.priceType == .free ? .kleinanzeigen : item.platform == .kleinanzeigen ? .kleinanzeigen : .vinted }
            } else { ContentUnavailableView("Angebot nicht verfügbar", systemImage: "tray") }
        }
        .navigationTitle("Vorschau").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
    }
    private func price(_ item: Item) -> some View {
        Text(item.priceType == .free ? "Zu verschenken" : item.price.map { $0.formatted(.currency(code: "EUR")) + (item.priceType == .negotiable ? " VB" : "") } ?? "Preis offen")
            .font(.title2.bold()).foregroundStyle(tint)
    }
    private func photos(_ item: Item) -> [Photo] {
        model.library.photos.filter { $0.itemID == itemID && $0.isSelected }.sorted { a, b in
            let aRank = a.id == item.coverPhotoID ? -1 : item.photoOrder.firstIndex(of: a.id) ?? Int.max
            let bRank = b.id == item.coverPhotoID ? -1 : item.photoOrder.firstIndex(of: b.id) ?? Int.max
            return aRank < bRank
        }
    }
}

struct PublicationEditor: View {
    let item: Item
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Platform> = []
    @State private var vintedURL = ""
    @State private var kleinanzeigenURL = ""
    @State private var unknown = false

    var body: some View {
        Form {
            Section {
                Text("Wo ist dein Angebot bereits online?")
                ForEach([Platform.vinted, .kleinanzeigen], id: \.rawValue) { platform in
                    Button {
                        if selected.contains(platform) { selected.remove(platform) } else { selected.insert(platform) }
                    } label: {
                        HStack {
                            Text(platform.label)
                            Spacer()
                            Image(systemName: selected.contains(platform) ? "checkmark.circle.fill" : "circle")
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(platform) ? [.isSelected] : [])
                        .accessibilityIdentifier("publication." + platform.rawValue)
                    if selected.contains(platform) {
                        TextField("Öffentlicher Anzeigenlink (optional)", text: platform == .vinted ? $vintedURL : $kleinanzeigenURL)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
                if unknown { Toggle("Online · Plattform noch offen", isOn: $unknown) }
            } footer: { Text("Hier bestätigst du eine bestehende Anzeige. Es wird nichts veröffentlicht.") }
            Button("Veröffentlichung speichern", action: save)
                .buttonStyle(PrimaryButtonStyle()).listRowBackground(Color.clear)
                .accessibilityIdentifier("publication.save")
        }
        .navigationTitle("Veröffentlichung").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }

        }
        .onAppear {
            selected = Set(item.publications.compactMap(\.platform))
            unknown = item.publications.contains { $0.platform == nil }
            vintedURL = item.publications.first { $0.platform == .vinted }?.url ?? ""
            kleinanzeigenURL = item.publications.first { $0.platform == .kleinanzeigen }?.url ?? ""
            if item.status == .published && item.publications.isEmpty {
                if item.platform == .both { unknown = true } else { selected.insert(item.platform) }
            }
        }
    }
    private func save() {
        var records = [Platform.vinted, .kleinanzeigen].filter { selected.contains($0) }.map { platform in
            ListingPublication(platform: platform, url: (platform == .vinted ? vintedURL : kleinanzeigenURL).trimmingCharacters(in: .whitespacesAndNewlines), confirmedAt: Date())
        }
        if unknown && selected.isEmpty { records.append(ListingPublication(confirmedAt: Date())) }
        model.resetError(); model.setPublications(itemID: item.id, publications: records, expectedRevision: item.revision)
        if model.errorMessage == nil { dismiss() }
    }

}
