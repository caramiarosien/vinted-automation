import SwiftUI
import UniformTypeIdentifiers
import UIKit
import WerkstattCore

struct ItemDetailView: View {
    let itemID: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var questionsOpen = false
    @State private var editorOpen = false
    @State private var importOpen = false
    @State private var previewOpen = false
    @State private var publicationOpen = false
    @State private var readinessOpen = false
    @State private var questionsAfterReadiness = false
    @State private var photosOpen = false
    @State private var descriptionOpen = false
    @State private var priceOpen = false
    @State private var analysisOpen = false
    @State private var exportOpen = false
    @State private var share: ShareFile?
    @State private var movingPhoto: Photo?
    @State private var initialFlowTriggered = false

    var body: some View {
        Group {
            if let item = model.item(id: itemID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(item)
                        actions(item)
                        questions(item)
                        descriptionCard(item)
                        photoCard(item)
                        priceCard(item)
                        analysisCard(item)
                        exportCard(item)
                    }.padding(20)
                }.workshopBackground()
            } else { ContentUnavailableView("Angebot nicht verfügbar", systemImage: "tray") }
        }
        .navigationTitle("Dein Angebot").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Bearbeiten") { editorOpen = true }.disabled(model.item(id: itemID) == nil) }
        }
        .sheet(isPresented: $questionsOpen) { NavigationStack { QuestionFlowView(itemID: itemID) } }
        .sheet(isPresented: $editorOpen) { if let item = model.item(id: itemID) { NavigationStack { ListingEditor(item: item) } } }
        .sheet(isPresented: $previewOpen) { NavigationStack { ListingPreview(itemID: itemID) } }
        .sheet(isPresented: $publicationOpen) { if let item = model.item(id: itemID) { NavigationStack { PublicationEditor(item: item) } } }
        .sheet(isPresented: $readinessOpen, onDismiss: {
            if questionsAfterReadiness { questionsAfterReadiness = false; questionsOpen = true }
        }) { readinessSheet }
        .sheet(item: $share) { ShareSheet(urls: [$0.url]) }
        .task {
            guard !initialFlowTriggered, let item = model.item(id: itemID), item.title.isEmpty, item.answers.isEmpty else { return }
            initialFlowTriggered = true
            await model.runOCR(itemID: itemID)
            if model.errorMessage == nil { questionsOpen = true }
        }
        .fileImporter(isPresented: $importOpen, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                model.resetError(); model.importAnalysis(url: url, itemID: itemID)
                if model.errorMessage == nil { questionsOpen = true }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Foto zurück in die Inbox?", isPresented: Binding(get: { movingPhoto != nil }, set: { if !$0 { movingPhoto = nil } })) {
            Button("In die Inbox verschieben") {
                if let photo = movingPhoto { model.regroup(photoIDs: [photo.id], destinationID: nil) }
                movingPhoto = nil
            }
            Button("Abbrechen", role: .cancel) { movingPhoto = nil }
        }
    }

    private func blockers(_ item: Item) -> [String] { Questionnaire.blockers(item: item, photos: model.library.photos.filter { $0.itemID == itemID }) }
    private func header(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 16) {
            PhotoThumbnail(url: coverURL(item), fit: .fit)
                .frame(width: 82, height: 100).background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(item.title.isEmpty ? item.kind.label : item.title).font(.headline).foregroundStyle(WerkstattTheme.ink).lineLimit(3)
                Text(price(item)).font(.title3.weight(.semibold)).foregroundStyle(WerkstattTheme.accent)
                HStack {
                    StatusBadge(text: item.displayStatus.label).accessibilityIdentifier("item.status")
                    Spacer(minLength: 0)
                    Button { publicationOpen = true } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Veröffentlichung verwalten").accessibilityIdentifier("item.publications")
                }
            }
        }
    }

    private func actions(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { previewOpen = true } label: { Label("Vorschau", systemImage: "eye") }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("item.preview")
                if item.status != .archived && item.status != .sold {
                    Button {
                        var update = item
                        update.status = item.status == .ready ? .draft : .ready
                        model.saveItem(update)
                    } label: { Label(item.status == .ready ? "Bereit" : item.hasPublicListing ? "Änderung bereit" : "Als bereit markieren", systemImage: item.status == .ready ? "checkmark.circle.fill" : "checkmark.circle") }
                        .buttonStyle(.bordered).disabled(item.status != .ready && !blockers(item).isEmpty)
                        .accessibilityIdentifier("item.ready")
                }
            }
            let remaining = blockers(item).count
            if remaining > 0 {
                Button { readinessOpen = true } label: {
                    Text(item.hasPublicListing ? "Angaben für die nächste Änderung prüfen" : "Noch \(remaining) \(remaining == 1 ? "Punkt" : "Punkte") offen")
                        .font(.caption)
                }.accessibilityIdentifier("item.readiness")
            }
        }
    }

    private func questions(_ item: Item) -> some View {
        let count = model.questions(item: item).count
        return Button { questionsOpen = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "checklist")
                Text(count == 0 ? "Antworten ansehen & ändern" : count == 1 ? "1 Frage beantworten" : "\(count) Fragen beantworten").fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }.padding(16).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).foregroundStyle(WerkstattTheme.accent).accessibilityIdentifier("item.questions")
    }

    private func descriptionCard(_ item: Item) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Beschreibung").font(.headline); Spacer(); Button("Bearbeiten") { editorOpen = true }.font(.subheadline) }
                if item.description.isEmpty { Text("Ergänze die Angaben über die Fragen.").foregroundStyle(WerkstattTheme.muted) }
                else { Text(item.description).font(.subheadline).lineLimit(descriptionOpen ? nil : 3).textSelection(.enabled).accessibilityIdentifier("item.description") }
                HStack {
                    if !item.description.isEmpty { Button(descriptionOpen ? "Weniger anzeigen" : "Mehr anzeigen") { descriptionOpen.toggle() }.accessibilityIdentifier("item.description.expand") }
                    Spacer()
                    Button("Neu erstellen") { model.regenerate(itemID: itemID) }
                }.font(.caption)
            }
        }
    }

    private func photoCard(_ item: Item) -> some View {
        PaperCard {
            DisclosureGroup(isExpanded: $photosOpen) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(orderedPhotos(item).enumerated()), id: \.element.id) { index, photo in
                            VStack(alignment: .leading, spacing: 10) {
                                PhotoThumbnail(url: model.photoURL(photo), fit: .fit).frame(width: 180, height: 190).background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                                Button {
                                    model.resetError()
                                    if !photo.isSelected { model.setPhotoSelected(photoID: photo.id, itemID: itemID, selected: true) }
                                    guard model.errorMessage == nil, var latest = model.item(id: itemID) else { return }
                                    latest.coverPhotoID = photo.id; latest.coverReason = "Von dir als Titelbild ausgewählt."
                                    latest.photoOrder = [photo.id] + latest.photoOrder.filter { $0 != photo.id }; model.saveItem(latest)
                                } label: { Label(item.coverPhotoID == photo.id ? "Titelbild" : "Als Titelbild", systemImage: item.coverPhotoID == photo.id ? "star.fill" : "star") }
                                    .buttonStyle(.bordered).font(.caption)
                                    .accessibilityLabel("Foto \(index + 1) als Titelbild wählen")
                                Toggle("Im Export", isOn: Binding(get: { model.library.photos.first { $0.id == photo.id }?.isSelected ?? false }, set: { model.setPhotoSelected(photoID: photo.id, itemID: itemID, selected: $0) })).font(.caption)
                                Button("Zurück in die Inbox", role: .destructive) { movingPhoto = photo }.font(.caption)
                            }.frame(width: 180)
                        }
                    }.padding(.top, 12)
                }
                if !item.coverReason.isEmpty { Text(item.coverReason).font(.caption).foregroundStyle(WerkstattTheme.muted).padding(.top, 8) }
            } label: { Label("Fotos · \(orderedPhotos(item).count)", systemImage: "photo.on.rectangle").font(.headline) }
            .accessibilityIdentifier("item.photos")
        }
    }

    @ViewBuilder private func priceCard(_ item: Item) -> some View {
        if !item.pricingNote.isEmpty || !item.sources.isEmpty {
            PaperCard {
                VStack(alignment: .leading, spacing: 0) {
                    Button { priceOpen.toggle() } label: {
                        HStack {
                            Label("Preis & Vergleiche", systemImage: "tag").font(.headline)
                            Spacer()
                            Image(systemName: priceOpen ? "chevron.up" : "chevron.down").font(.caption)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("item.pricing")
                        .accessibilityValue(priceOpen ? "Aufgeklappt" : "Zugeklappt")
                    if priceOpen { VStack(alignment: .leading, spacing: 14) {
                        if !item.pricingNote.isEmpty { Text(item.pricingNote).font(.subheadline).textSelection(.enabled).accessibilityIdentifier("price.reason") }
                        ForEach(Array(item.sources.enumerated()), id: \.offset) { _, source in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(sourceLabel(source.kind)).font(.caption)
                                    if !source.checked.isEmpty { Text("Geprüft: " + source.checked).font(.caption) }
                                    if !source.note.isEmpty { Text(source.note).font(.subheadline) }
                                    if let url = URL(string: source.url), url.scheme == "https" { Link("Quelle ansehen", destination: url) }
                                }.foregroundStyle(WerkstattTheme.muted).padding(.top, 6)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.title).font(.subheadline)
                                    if let value = source.price { Text(value, format: .currency(code: "EUR")).font(.caption).foregroundStyle(WerkstattTheme.muted) }
                                }
                            }
                        }
                    }.padding(.top, 12) }
                }
            }
        }
    }

    private func analysisCard(_ item: Item) -> some View {
        PaperCard {
            DisclosureGroup(isExpanded: $analysisOpen) {
                VStack(alignment: .leading, spacing: 12) {
                    Button { Task { await model.runOCR(itemID: itemID) } } label: { Label("Beschriftungen auslesen", systemImage: "text.viewfinder") }.disabled(model.isBusy)
                    Button { if let url = model.exportAnalysis(itemID: itemID) { share = ShareFile(url: url) } } label: { Label("Für Chat exportieren", systemImage: "square.and.arrow.up") }
                    Button { importOpen = true } label: { Label("Analyse importieren", systemImage: "square.and.arrow.down") }
                    if !item.facts.isEmpty {
                        Divider()
                        ForEach(Array(item.facts.enumerated()), id: \.offset) { _, fact in Text(fact).font(.caption).foregroundStyle(WerkstattTheme.muted) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            } label: { Label("Analyse & Details", systemImage: "sparkle.magnifyingglass").font(.headline) }
            .accessibilityIdentifier("item.analysis")
        }
    }

    private func exportCard(_ item: Item) -> some View {
        PaperCard {
            DisclosureGroup(isExpanded: $exportOpen) {
                VStack(alignment: .leading, spacing: 12) {
                    Button { if let url = model.exportListing(itemID: itemID) { share = ShareFile(url: url) } } label: { Label("Angebot & Fotos exportieren", systemImage: "square.and.arrow.up") }
                        .disabled(!blockers(item).isEmpty || ![.ready, .published, .sold].contains(item.status))
                    if item.platform != .kleinanzeigen { Button("Vinted öffnen") { if let url = URL(string: "https://www.vinted.de") { openURL(url) } } }
                    if item.platform != .vinted { Button("Kleinanzeigen öffnen") { if let url = URL(string: "https://www.kleinanzeigen.de") { openURL(url) } } }
                    ForEach(item.publications) { publication in
                        if let url = URL(string: publication.url), ListingPublication.isPublicURL(publication.url) { Link("Anzeige auf " + (publication.platform?.label ?? "dem Marktplatz"), destination: url) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            } label: { Label("Export & Marktplätze", systemImage: "square.and.arrow.up").font(.headline) }
        }
    }

    private var readinessSheet: some View {
        NavigationStack {
            List {
                if let item = model.item(id: itemID) {
                    ForEach(Array(blockers(item).enumerated()), id: \.offset) { _, text in Label(text, systemImage: "circle.dashed") }
                    Button("Fragen beantworten") { questionsAfterReadiness = true; readinessOpen = false }
                }
            }.navigationTitle("Noch offen").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { readinessOpen = false } } }
        }.presentationDetents([.medium, .large])
    }

    private func orderedPhotos(_ item: Item) -> [Photo] {
        model.library.photos.filter { $0.itemID == itemID }.sorted { (item.photoOrder.firstIndex(of: $0.id) ?? Int.max) < (item.photoOrder.firstIndex(of: $1.id) ?? Int.max) }
    }
    private func coverURL(_ item: Item) -> URL? {
        guard let photo = orderedPhotos(item).first(where: { $0.id == item.coverPhotoID }) ?? orderedPhotos(item).first else { return nil }
        return model.photoURL(photo)
    }
    private func price(_ item: Item) -> String {
        item.priceType == .free ? "Zu verschenken" : item.price.map { $0.formatted(.currency(code: "EUR")) + (item.priceType == .negotiable ? " VB" : "") } ?? "Preis offen"
    }
    private func sourceLabel(_ kind: String) -> String {
        switch kind {
        case "sold", "confirmed_sold": return "Belegter Verkauf"
        case "asking": return "Angebotspreis"
        case "refurbished": return "Refurbished · Händlerangebot"
        case "retail": return "Händlerangebot"
        case "buyback": return "Ankaufangebot"
        default: return "Zusätzlicher Vergleich"
        }
    }
}

private struct ListingEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var item: Item
    @State private var priceText = ""

    var body: some View {
        Form {
            Section("Dein Angebot") {
                TextField("Titel", text: $item.title)
                TextEditor(text: $item.description).frame(minHeight: 150).accessibilityLabel("Beschreibung")
                Text("Zustand, Funktion und Akku änderst du über die Auswahlfragen im Artikel.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Artikelinformationen") {
                Picker("Kategorie der Fragen", selection: $item.kind) {
                    ForEach(ProductKind.allCases, id: \.rawValue) { Text($0.label).tag($0) }
                }
                TextField("Marke", text: $item.brand)
                TextField("Kategorie", text: $item.category)
                TextField("Farbe", text: $item.color)
                TextField("Variante / Modell", text: $item.variant)
            }
            Section("Preis & Plattform") {
                Picker("Plattform", selection: $item.platform) {
                    ForEach(Platform.allCases, id: \.rawValue) { Text($0.label).tag($0) }
                }
                Picker("Preistyp", selection: $item.priceType) {
                    ForEach(PriceType.allCases, id: \.rawValue) { Text($0.label).tag($0) }
                }
                if item.priceType != .free {
                    TextField("Preis in Euro", text: $priceText).keyboardType(.decimalPad)
                } else {
                    Text("Zu verschenken · 0 € · Kleinanzeigen").foregroundStyle(.secondary)
                }
            }
            Section("Verwaltung") {
                Picker("Status", selection: $item.status) {
                    ForEach(ItemStatus.allCases, id: \.rawValue) { Text($0.label).tag($0) }
                }
                TextField("Link zum Angebot", text: $item.listingURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextEditor(text: $item.notes).frame(minHeight: 90).accessibilityLabel("Private Notizen")
                Text("Private Notizen werden nicht in die öffentliche Beschreibung übernommen.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Angebot bearbeiten").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    model.resetError()
                    if item.priceType == .free { item.price = 0; item.platform = .kleinanzeigen }
                    else if priceText.trimmingCharacters(in: .whitespaces).isEmpty { item.price = nil }
                    else if let price = Double(priceText.replacingOccurrences(of: ",", with: ".")), price.isFinite, price > 0 {
                        item.price = price
                    } else { model.errorMessage = "Bitte gib einen gültigen positiven Preis ein."; return }
                    model.saveItem(item)
                    if model.errorMessage == nil { dismiss() }
                }.fontWeight(.semibold)
            }
        }
        .onAppear { priceText = item.price.map { String($0).replacingOccurrences(of: ".", with: ",") } ?? "" }
        .onChange(of: item.priceType) { _, value in if value == .free { item.platform = .kleinanzeigen } }
    }
}
