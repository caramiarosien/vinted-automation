import SwiftUI
import PhotosUI
import WerkstattCore

struct InboxView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pickerPhotos: [PhotosPickerItem] = []
    @State private var selected: Set<String> = []
    @State private var kind: ProductKind = .other
    @State private var cameraOpen = false
    @State private var groupingOpen = false
    @State private var importing = false
    @State private var destinationID: String?
    @State private var showDestination = false
    private var photos: [Photo] {
        model.library.photos.filter { $0.itemID == nil }.sorted { $0.importedAt > $1.importedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ein neuer Anfang\nfür deine Dinge.").font(WerkstattTheme.title)
                        .foregroundStyle(WerkstattTheme.ink).accessibilityAddTraits(.isHeader)
                    Text("Fotos hinzufügen. Zusammengehörige Bilder auswählen. Ein Angebot vorbereiten.")
                        .foregroundStyle(WerkstattTheme.muted)
                }
                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerPhotos, maxSelectionCount: 100, matching: .images) {
                        Label("Fotos wählen", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                    Button { cameraOpen = true } label: {
                        Image(systemName: "camera").font(.title3).padding(4)
                    }.buttonStyle(.bordered).accessibilityLabel("Neues Foto aufnehmen")
                        .disabled(!CameraPicker.isAvailable)
                        .accessibilityHint(CameraPicker.isAvailable ? "Öffnet die Kamera." : "Auf diesem Gerät ist keine Kamera verfügbar. Wähle Fotos aus der Mediathek.")
                }.disabled(importing || model.isBusy)
                if importing { ProgressView("Fotos werden lokal gespeichert …").frame(maxWidth: .infinity) }
                if photos.isEmpty {
                    ContentUnavailableView("Deine Inbox ist leer", systemImage: "tray",
                        description: Text("Die App speichert eigene Kopien. Deine Fotos bleiben in der Fotomediathek erhalten."))
                } else {
                    HStack {
                        Text("\(photos.count) Fotos").font(.headline)
                        Spacer()
                        Button(selected.count == photos.count ? "Auswahl aufheben" : "Alle auswählen") {
                            selected = selected.count == photos.count ? [] : Set(photos.map(\.id))
                        }.font(.subheadline)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            Button {
                                if selected.contains(photo.id) { selected.remove(photo.id) } else { selected.insert(photo.id) }
                            } label: {
                                PhotoThumbnail(url: model.photoURL(photo)).frame(height: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: selected.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title2).foregroundStyle(selected.contains(photo.id) ? WerkstattTheme.accent : .white)
                                            .background(.white, in: Circle()).padding(10)
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected.contains(photo.id) ? WerkstattTheme.accent : .clear, lineWidth: 3))
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Foto \(index + 1)")
                                .accessibilityValue(selected.contains(photo.id) ? "Ausgewählt" : "Nicht ausgewählt")
                                .accessibilityHint("Doppeltippen, um das Foto für einen Artikel auszuwählen.")
                        }
                    }
                    Text("Wähle jeweils die Fotos eines einzelnen Artikels. Zugeordnete Originale werden automatisch unter „Bearbeitet“ abgelegt.")
                        .font(.footnote).foregroundStyle(WerkstattTheme.muted)
                }
            }.padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                Button { destinationID = nil; groupingOpen = true } label: {
                    Label("Artikel aus \(selected.count) Fotos", systemImage: "arrow.right")
                }.buttonStyle(PrimaryButtonStyle()).disabled(importing || model.isBusy)
                    .padding(16).background(WerkstattTheme.paper)
            }
        }
        .workshopBackground().navigationTitle("Inbox")
        .onChange(of: pickerPhotos) { _, values in
            guard !values.isEmpty else { return }
            importing = true
            Task {
                var failures: [String] = []
                for value in values {
                    do {
                        if let data = try await value.loadTransferable(type: Data.self) {
                            await model.importPhotoData(data, filename: "Foto-\(UUID().uuidString).jpg")
                            if let message = model.errorMessage { failures.append(message) }
                        } else { failures.append("Ein ausgewähltes Foto konnte nicht geladen werden.") }
                    } catch { failures.append("Das Foto konnte nicht importiert werden: \(error.localizedDescription)") }
                }
                pickerPhotos = []
                importing = false
                if !failures.isEmpty { model.errorMessage = "\(failures.count) Fotos konnten nicht importiert werden. Die übrigen sind gespeichert.\n" + failures.joined(separator: "\n") }
            }
        }
        .fullScreenCover(isPresented: $cameraOpen) {
            CameraPicker { data in
                cameraOpen = false
                Task { await model.importPhotoData(data, filename: "Kamera-\(UUID().uuidString).jpg") }
            }.ignoresSafeArea()
        }
        .sheet(isPresented: $groupingOpen, onDismiss: {
            if destinationID != nil { showDestination = true }
        }) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SectionHeading(title: "Was möchtest du anbieten?", subtitle: "Die Auswahl bestimmt, welche wichtigen Fragen wir dir stellen.")
                        ForEach(ProductKind.allCases, id: \.rawValue) { option in
                            Button { kind = option } label: {
                                HStack {
                                    Text(option.label).font(.headline)
                                    Spacer()
                                    Image(systemName: kind == option ? "checkmark.circle.fill" : "circle")
                                }.padding(18).foregroundStyle(WerkstattTheme.ink)
                                    .background(kind == option ? WerkstattTheme.accent.opacity(0.12) : .white, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain).accessibilityAddTraits(kind == option ? [.isSelected] : [])
                        }
                        Button {
                            if let id = model.createItem(photoIDs: photos.filter { selected.contains($0.id) }.map(\.id), kind: kind) {
                                selected = []
                                destinationID = id
                                groupingOpen = false
                            }
                        } label: { Text("Artikel anlegen") }.buttonStyle(PrimaryButtonStyle())
                    }.padding(20)
                }.workshopBackground().navigationTitle("Neuer Artikel")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { groupingOpen = false } } }
            }.presentationDetents([.large])
        }
        .navigationDestination(isPresented: $showDestination) {
            if let destinationID { ItemDetailView(itemID: destinationID) }
        }
    }
}
