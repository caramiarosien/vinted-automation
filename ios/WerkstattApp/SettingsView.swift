import SwiftUI
import UniformTypeIdentifiers
import WerkstattCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var location = ""
    @State private var share: ShareFile?
    @State private var importOpen = false
    @State private var restoreURL: URL?
    @State private var confirmRestore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Deine Werkstatt.\nAuf deinem iPhone.").font(WerkstattTheme.title)
                    .foregroundStyle(WerkstattTheme.ink).accessibilityAddTraits(.isHeader)
                PaperCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "Dein Abholort", subtitle: "Wird für neue Beschreibungen verwendet. Bestehende Angebote bleiben erhalten.")
                        TextField("Ort, z. B. Konstanz", text: $location).textFieldStyle(.roundedBorder)
                            .textContentType(.addressCity).autocorrectionDisabled()
                        Button("Abholort speichern") { model.setDefaultLocation(location.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            .disabled(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || location == model.library.defaultLocation)
                    }
                }
                PaperCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "Sichern & umziehen", subtitle: "Eine ZIP-Sicherung enthält deinen Bestand mit Originalfotos. Bewahre sie beispielsweise in „Dateien“ auf.")
                        Button {
                            if let url = model.exportBackup() { share = ShareFile(url: url) }
                        } label: { Label("Vollständige Sicherung erstellen", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.bordered).disabled(model.isBusy)
                        Button { importOpen = true } label: { Label("Sicherung wiederherstellen", systemImage: "arrow.counterclockwise") }
                            .disabled(model.isBusy)
                        Text("Eine Wiederherstellung ersetzt den aktuellen Bestand. Sichere ihn vorher, wenn du ihn behalten möchtest.")
                            .font(.footnote).foregroundStyle(WerkstattTheme.muted)
                    }
                }
                PaperCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "So arbeitet die App")
                        Label("Fotos, Antworten und Artikel werden lokal gespeichert.", systemImage: "iphone")
                        Label("Beschriftungen werden auf dem Gerät ausgelesen.", systemImage: "text.viewfinder")
                        Label("Bildanalyse und Preisrecherche erfolgen über deinen Chat und einen bewussten Export.", systemImage: "bubble.left.and.text.bubble.right")
                        Label("Angebote veröffentlichst du selbst auf dem Marktplatz.", systemImage: "checkmark.circle")
                    }.font(.subheadline).foregroundStyle(WerkstattTheme.muted)
                }
                Text("Werkstatt · Version 1.0").font(.footnote).foregroundStyle(WerkstattTheme.muted)
                    .frame(maxWidth: .infinity)
            }.padding(20)
        }.workshopBackground().navigationTitle("Einstellungen")
        .onAppear { location = model.library.defaultLocation }
        .onChange(of: model.library.defaultLocation) { _, value in location = value }
        .sheet(item: $share) { ShareSheet(urls: [$0.url]) }
        .fileImporter(isPresented: $importOpen, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let url): restoreURL = url; confirmRestore = true
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Bestand ersetzen?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Sicherung wiederherstellen", role: .destructive) {
                if let restoreURL { model.restoreBackup(url: restoreURL) }
                restoreURL = nil
            }
            Button("Abbrechen", role: .cancel) { restoreURL = nil }
        } message: { Text("Deine aktuellen Artikel und Fotos werden durch die gewählte Sicherung ersetzt. Diese Änderung lässt sich nur mit einer vorherigen Sicherung rückgängig machen.") }
    }
}
