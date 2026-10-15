import SwiftUI
import WerkstattCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            NavigationStack { InboxView() }
                .tabItem { Label("Inbox", systemImage: "tray") }
                .badge(model.library.photos.filter { $0.itemID == nil }.count)
            NavigationStack { CollectionView() }
                .tabItem { Label("Werkstatt", systemImage: "square.grid.2x2") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        .tint(WerkstattTheme.accent)
        .alert("Das hat nicht geklappt", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.resetError() } }
        )) {
            Button("OK") { model.resetError() }
        } message: { Text(model.errorMessage ?? "Bitte versuche es erneut.") }
    }
}

private struct CollectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter: ItemStatus?
    private var items: [Item] {
        model.library.items.filter { filter == nil || $0.displayStatus == filter }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aus Dingen\nwerden Angebote.").font(WerkstattTheme.title)
                        .foregroundStyle(WerkstattTheme.ink).accessibilityAddTraits(.isHeader)
                    Text("Deine Artikel, ihre Geschichten und der nächste Schritt.")
                        .foregroundStyle(WerkstattTheme.muted)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterButton("Alle", status: nil)
                        ForEach(ItemStatus.allCases, id: \.rawValue) { status in
                            filterButton(status.label, status: status)
                        }
                    }
                }
                if items.isEmpty {
                    ContentUnavailableView(
                        filter == nil ? "Noch keine Artikel" : "Hier ist noch Platz",
                        systemImage: "square.grid.2x2",
                        description: Text(filter == nil ? "Importiere Fotos in die Inbox und fasse die Bilder eines Artikels zusammen." : "In diesem Status gibt es noch keine Artikel.")
                    )
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(items, id: \.id) { item in
                            NavigationLink { ItemDetailView(itemID: item.id) } label: {
                                PaperCard {
                                    HStack(alignment: .top, spacing: 14) {
                                        PhotoThumbnail(url: coverURL(for: item))
                                            .frame(width: 84, height: 100).clipShape(RoundedRectangle(cornerRadius: 12))
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(item.title.isEmpty ? item.kind.label : item.title)
                                                .font(.headline).foregroundStyle(WerkstattTheme.ink).lineLimit(3)
                                            Text(item.priceType == .free ? "Zu verschenken" : item.price.map { $0.formatted(.currency(code: "EUR")) } ?? "Preis noch offen")
                                                .font(.subheadline).foregroundStyle(WerkstattTheme.muted)
                                            StatusBadge(text: item.displayStatus.label)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(20)
        }.workshopBackground().navigationTitle("Werkstatt")
    }

    private func coverURL(for item: Item) -> URL? {
        let id = item.coverPhotoID ?? item.photoOrder.first
        guard let photo = model.library.photos.first(where: { $0.id == id && $0.itemID == item.id }) else { return nil }
        return model.photoURL(photo)
    }

    private func filterButton(_ title: String, status: ItemStatus?) -> some View {
        Button { filter = status } label: {
            Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(filter == status ? .white : WerkstattTheme.ink)
                .background(filter == status ? WerkstattTheme.accent : .white.opacity(0.7), in: Capsule())
        }.accessibilityAddTraits(filter == status ? [.isSelected] : [])
    }
}
