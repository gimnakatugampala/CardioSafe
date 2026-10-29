import SwiftUI
import MapKit

struct WalkingNearbyPlacesView: View {
    let model: WalkingMapLayersViewModel
    let refresh: () -> Void
    let onWalkHere: (MapPlace) -> Void
    var onRestHere: ((MapPlace) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Places in the searched map area · Apple Maps · Up to 20 per layer")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Refresh this area", action: refresh).disabled(model.isSearching)
                    if model.isSearching { ProgressView("Finding nearby places…") }
                }
                ForEach(MapPlaceCategory.allCases.filter { model.enabled.contains($0) }) { category in
                    Section(category.rawValue) {
                        if let error = model.errors[category] { Text(error).foregroundStyle(.secondary) }
                        else if model.places[category, default: []].isEmpty, !model.isSearching {
                            Text("No results in this area.").foregroundStyle(.secondary)
                        }
                        ForEach(model.places[category, default: []]) { place in
                            NavigationLink {
                                WalkingNearbyPlaceDetail(place: place, onWalkHere: onWalkHere, onRestHere: onRestHere)
                            } label: {
                                Label { VStack(alignment: .leading, spacing: 5) {
                                    Text(place.name)
                                    Text(place.address).font(.caption).foregroundStyle(.secondary)
                                } } icon: { Image(systemName: category.symbol) }
                            }
                        }
                    }
                }
                Section { Text("Place classifications come from Apple Maps and may be inaccurate. Results do not verify emergency capability, park accessibility or resting facilities.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Nearby places").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct WalkingNearbyPlaceDetail: View {
    let place: MapPlace
    var onWalkHere: ((MapPlace) -> Void)? = nil
    var onRestHere: ((MapPlace) -> Void)? = nil
    var body: some View {
        List {
            Section {
                Label(place.name, systemImage: place.category.symbol).font(.title3.bold())
                Text(place.address).foregroundStyle(.secondary)
                if let onWalkHere {
                    Button { onWalkHere(place) } label: {
                        Label("Walk here", systemImage: "figure.walk")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.borderedProminent)
                    Text("Show an estimated walking route inside your active CardioSafe map.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if place.category == .parks, let onRestHere {
                    Button("Remind me near this rest stop") { onRestHere(place) }
                    Text("For this walk only. This saves a 200 m reminder area, not a verified resting facility.").font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    place.item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                } label: { Label("Walking directions in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    .frame(minHeight: 44)
                Text("Opens Apple Maps. Your CardioSafe walking session stays active.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text(place.category == .hospitals
                     ? "Hospital search result from Apple Maps. Emergency services and opening hours are not verified."
                     : "Park search result from Apple Maps. Seating, access and suitability are not verified.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle(place.category == .hospitals ? "Hospital" : "Park").navigationBarTitleDisplayMode(.inline)
    }
}
