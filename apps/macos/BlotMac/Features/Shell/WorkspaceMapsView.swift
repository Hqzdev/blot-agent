import MapKit
import Observation
import BlotDesign
import SwiftUI

@Observable
private final class MapsSearch {
    struct Place: Identifiable {
        let id = UUID()
        let item: MKMapItem
    }
    private(set) var places: [Place] = []
    private(set) var searching = false
    private(set) var error: String?
    private(set) var completed = false
    var camera: MapCameraPosition = .automatic

    func search(_ query: String) async {
        guard !query.isEmpty else { return }
        searching = true
        error = nil
        completed = false
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            places = response.mapItems.map { Place(item: $0) }
            camera = .region(response.boundingRegion)
        } catch {
            guard !Task.isCancelled else { return }
            places = []
            self.error = error.localizedDescription
        }
        searching = false
        completed = true
    }
}

struct WorkspaceMapsView: View {
    @State private var search = MapsSearch()
    @State private var query = ""
    @State private var submitted = ""
    @State private var requestID = UUID()
    @State private var selected: UUID?
    var body: some View {
        @Bindable var search = search
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Maps", subtitle: "Find a place or address and open it in Apple Maps.")
            HStack(spacing: KSpace.sm) {
                KSearchField(placeholder: "Search for a place or address", text: $query, onSubmit: submit)
                KButton(title: "Search", icon: "search", kind: .primary, loading: search.searching) { submit() }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = search.error {
                InlineFeedback(text: error, tone: .error)
            } else if search.completed && search.places.isEmpty {
                InlineFeedback(text: "No places found. Try another name or address.")
            }
            HStack(spacing: 0) {
                if search.searching {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(0..<3) { _ in SkeletonText(lines: 2) }
                        Spacer()
                    }.padding(18).frame(width: 220)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Loading places")
                    VDivider()
                } else if !search.places.isEmpty {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(search.places) { place in
                                Button {
                                    selected = place.id
                                    search.camera = .item(place.item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.item.name ?? "Place").font(KFont.label()).foregroundStyle(K.text)
                                        Text(place.item.address?.fullAddress ?? "").font(KFont.caption()).foregroundStyle(K.text2)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                        .contentShape(Rectangle()).kHover(radius: K.rMd, active: selected == place.id)
                                }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm)
                            }
                        }.padding(6)
                    }.frame(width: 220)
                    VDivider()
                }
                if search.searching && search.places.isEmpty {
                    SkeletonBlock(radius: K.rLg)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Loading map results")
                } else {
                    Map(position: $search.camera, selection: $selected) {
                        ForEach(search.places) { place in Marker(item: place.item).tag(place.id) }
                    }.mapControls { MapCompass(); MapZoomStepper() }
                }
            }.clipShape(RoundedRectangle(cornerRadius: K.rLg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: K.rLg, style: .continuous).strokeBorder(K.border, lineWidth: 1))
                .frame(maxHeight: .infinity)
                .loadingTransition(isLoading: search.searching)
            if let place = search.places.first(where: { $0.id == selected }) {
                KButton(title: "Open in Apple Maps", icon: "square-arrow-out-up-right") { place.item.openInMaps() }
            }
        }.padding(.horizontal, K.pageInset).padding(.vertical, K.pageTopInset)
        .task(id: requestID) { await search.search(submitted) }
    }
    private func submit() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        selected = nil
        submitted = value
        requestID = UUID()
    }
}
