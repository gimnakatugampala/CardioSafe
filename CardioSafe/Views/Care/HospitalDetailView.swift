import SwiftUI
import MapKit
import Observation

// MARK: - Route model (MapKit first, OpenStreetMap fallback)

enum HospitalRouteError: LocalizedError {
    case locationDenied, locationUnavailable, noRoute
    var errorDescription: String? {
        switch self {
        case .locationDenied: "Location access is off. Allow it in Settings to see the distance from you."
        case .locationUnavailable: "Your location couldn’t be found. Check that you’re outdoors or have a signal, then try again."
        case .noRoute: "No driving route was found between your location and this hospital."
        }
    }
}

@MainActor @Observable
final class HospitalRouteViewModel {
    enum Phase { case idle, locating, routing, ready, failed }

    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var origin: CLLocationCoordinate2D?
    private(set) var originDescription = ""
    private(set) var polyline: MKPolyline?
    private(set) var distanceMetres: Double?
    private(set) var travelSeconds: Double?
    private(set) var straightLineMetres: Double?
    private(set) var routeCount = 0
    private(set) var fastestDistanceMetres: Double?
    private(set) var fastestSeconds: Double?
    private(set) var routeVersion = UUID()
    private(set) var sourceNote = ""

    @ObservationIgnored private let location = WalkingLocationViewModel()
    @ObservationIgnored private var directions: MKDirections?
    @ObservationIgnored private var generation = UUID()

    func start(to place: MapPlace) async {
        stop()
        let token = generation
        errorMessage = nil
        polyline = nil; distanceMetres = nil; travelSeconds = nil
        fastestDistanceMetres = nil; fastestSeconds = nil
        straightLineMetres = nil; routeCount = 0; sourceNote = ""
        phase = .locating
        do {
            let (coordinate, description) = try await currentOrigin(token: token)
            guard generation == token, !Task.isCancelled else { return }
            origin = coordinate
            originDescription = description
            straightLineMetres = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: place.item.location)
            phase = .routing

            var candidates: [(line: MKPolyline, metres: Double, seconds: Double)] = []
            var note = "Apple Maps"

            // 1. Apple Maps (MapKit)
            do {
                let request = MKDirections.Request()
                request.source = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
                request.destination = place.item
                request.transportType = .automobile
                request.requestsAlternateRoutes = true
                let calculation = MKDirections(request: request)
                directions = calculation
                let timeout = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(20)); calculation.cancel() } catch {}
                }
                defer { timeout.cancel() }
                let response = try await calculation.calculate()
                candidates = response.routes.map { ($0.polyline, $0.distance, $0.expectedTravelTime) }
            } catch {
                guard generation == token, !Task.isCancelled, !(error is CancellationError) else { return }
                #if DEBUG
                print("MKDirections failed:", error)
                #endif
            }
            guard generation == token, !Task.isCancelled else { return }

            // 2. Fallback: OpenStreetMap road routing (works where Apple Maps has no driving data)
            if candidates.isEmpty {
                let roads = try await CommunityRoadRoutingService().routes(from: coordinate, to: place.coordinate)
                candidates = roads.map { ($0.polyline, $0.distanceMetres, $0.seconds) }
                note = "OpenStreetMap (FOSSGIS)"
            }
            guard generation == token, !Task.isCancelled else { return }

            guard let shortest = candidates.min(by: { $0.metres < $1.metres }) else {
                throw HospitalRouteError.noRoute
            }
            sourceNote = note
            polyline = shortest.line
            distanceMetres = shortest.metres
            travelSeconds = shortest.seconds
            routeCount = candidates.count
            if let fastest = candidates.min(by: { $0.seconds < $1.seconds }),
               fastest.seconds < shortest.seconds {
                fastestDistanceMetres = fastest.metres
                fastestSeconds = fastest.seconds
            }
            routeVersion = UUID()
            phase = .ready
        } catch {
            guard generation == token, !Task.isCancelled, !(error is CancellationError) else { return }
            phase = .failed
            errorMessage = (error as? HospitalRouteError)?.errorDescription
                ?? (error as? CommunityRoutingError)?.errorDescription
                ?? ((error as? URLError) != nil
                    ? "Check your connection and try again."
                    : "No driving route could be found from here to this hospital.")
        }
    }

    func stop() {
        generation = UUID()
        directions?.cancel(); directions = nil
        location.stop()
        if phase == .locating || phase == .routing { phase = .idle }
    }

    private func currentOrigin(token: UUID) async throws -> (CLLocationCoordinate2D, String) {
        #if targetEnvironment(simulator)
        return (CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612), "Sample Colombo location · Simulator")
        #else
        location.start()
        defer { location.stop() }
        var deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while location.location == nil && ContinuousClock.now < deadline {
            if Task.isCancelled || generation != token { throw CancellationError() }
            switch location.authorization {
            case .denied, .restricted: throw HospitalRouteError.locationDenied
            case .notDetermined: deadline = ContinuousClock.now.advanced(by: .seconds(12)) // waiting on the permission prompt
            default: break
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        guard let fix = location.location, fix.horizontalAccuracy <= 200,
              abs(fix.timestamp.timeIntervalSinceNow) < 30 else { throw HospitalRouteError.locationUnavailable }
        return (fix.coordinate, "Your device location")
        #endif
    }

    static func distanceText(_ metres: Double) -> String {
        metres < 1000 ? "\(Int(metres.rounded())) m"
            : "\((metres / 1000).formatted(.number.precision(.fractionLength(1)))) km"
    }

    static func durationText(_ seconds: Double) -> String {
        let minutes = max(1, Int(ceil(seconds / 60)))
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

// MARK: - Hospital detail

struct HospitalDetailView: View {
    @Environment(HospitalArrivalViewModel.self) private var arrival
    let hospital: MapPlace
    let distance: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingCall = false
    @Environment(\.openURL) private var openURL
    @State private var contactError: String?
    @Environment(\.colorScheme) private var scheme
    @State private var routeModel = HospitalRouteViewModel()
    @State private var camera: MapCameraPosition

    init(hospital: MapPlace, distance: String) {
        self.hospital = hospital
        self.distance = distance
        _camera = State(initialValue: .region(MKCoordinateRegion(center: hospital.coordinate,
                                                                 latitudinalMeters: 1500, longitudinalMeters: 1500)))
    }

    private var phoneURL: URL? {
        guard let phone = hospital.item.phoneNumber else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("CARE FINDER", systemImage: "cross.case.fill")
                            .font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(CardioSafeTheme.accent(for: scheme))
                        Text(hospital.name).font(.largeTitle.bold()).tracking(-0.8)
                        Text(hospital.address).font(.subheadline).foregroundStyle(.secondary)
                        Label(distance, systemImage: "location.fill")
                            .font(.caption.weight(.medium)).foregroundStyle(CardioSafeTheme.accent(for: scheme))
                    }
                    Map(position: $camera) {
                        if let saved = arrival.reminder, saved.place.id == hospital.id {
                            MapCircle(center: hospital.coordinate, radius: HospitalArrivalReminder.radiusMetres)
                                .foregroundStyle(.teal.opacity(0.12)).stroke(.teal, lineWidth: 2)
                        }
                        if let polyline = routeModel.polyline {
                            MapPolyline(polyline)
                                .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        }
                        if let origin = routeModel.origin {
                            Annotation("Your location", coordinate: origin) {
                                Circle().fill(.blue).frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(.white, lineWidth: 3))
                            }
                        }
                        Marker(hospital.name, systemImage: "cross.case.fill", coordinate: hospital.coordinate)
                            .tint(CardioSafeTheme.teal)
                    }
                    .mapControls { MapCompass(); MapScaleView() }
                    .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 18))

                    routeCard

                    Button {
                        hospital.item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    } label: {
                        Label("Directions in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    if phoneURL != nil, let number = hospital.item.phoneNumber {
                        Button { confirmingCall = true } label: {
                            Label(number, systemImage: "phone").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Label("Phone number unavailable", systemImage: "phone.badge.exclamationmark").foregroundStyle(.secondary)
                    }
                    if let url = hospital.item.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                        Link(destination: url) { Label("Hospital website", systemImage: "safari") }
                    }
                    if let contactError { Text(contactError).font(.caption).foregroundStyle(.secondary) }
                    HospitalArrivalReminderCard(hospital: hospital)
                    HStack {
                        Text("Department queues").font(.title3.bold())
                        Spacer()
                        Image(systemName: "person.3.sequence.fill").foregroundStyle(CardioSafeTheme.accent(for: scheme)).accessibilityHidden(true)
                    }.padding(.top, 8)
                    HospitalQueuesView(mapPlaceID: hospital.id)
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "truck.box.fill").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ambulance availability").font(.subheadline.weight(.semibold))
                            Text("Dispatch is not connected. Opening this hospital does not request an ambulance.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 18))
                    Text("Place details supplied by Apple Maps. Contact the hospital to confirm services.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .background(CardioSafeTheme.background(for: scheme))
            .foregroundStyle(CardioSafeTheme.text(for: scheme))
            .tint(CardioSafeTheme.teal)
            .navigationTitle("Hospital details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await routeModel.start(to: hospital) }
            .onDisappear { routeModel.stop() }
            .onChange(of: routeModel.routeVersion) { _, _ in
                guard let polyline = routeModel.polyline else { return }
                let rect = polyline.boundingMapRect
                camera = .rect(rect.insetBy(dx: -max(rect.width * 0.2, 400), dy: -max(rect.height * 0.2, 400)))
            }
            .confirmationDialog("Call this hospital?", isPresented: $confirmingCall, titleVisibility: .visible) {
                if let url = phoneURL {
                    Button("Call \(hospital.item.phoneNumber ?? "hospital")") {
                        openURL(url) { accepted in
                            if !accepted { contactError = "Calls are unavailable on this device. Use the displayed number on a phone." }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: Shortest route card

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Shortest road distance", systemImage: "car.fill")
                .font(.headline).foregroundStyle(CardioSafeTheme.accent(for: scheme))
            switch routeModel.phase {
            case .idle, .locating:
                HStack(spacing: 10) { ProgressView(); Text("Finding your location…").font(.subheadline).foregroundStyle(.secondary) }
            case .routing:
                HStack(spacing: 10) { ProgressView(); Text("Finding the shortest route…").font(.subheadline).foregroundStyle(.secondary) }
            case .ready:
                readyContent
            case .failed:
                Text(routeModel.errorMessage ?? "The route couldn’t be calculated.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { Task { await routeModel.start(to: hospital) } } label: {
                    Label("Try again", systemImage: "arrow.clockwise").frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private var readyContent: some View {
        if let metres = routeModel.distanceMetres, let seconds = routeModel.travelSeconds {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(HospitalRouteViewModel.distanceText(metres))
                        .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(routeModel.routeCount > 1 ? "by road · shortest of \(routeModel.routeCount) routes" : "by road")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(HospitalRouteViewModel.durationText(seconds)).font(.title3.bold()).monospacedDigit()
                    Text("driving").font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            if let straight = routeModel.straightLineMetres {
                Label("Straight-line distance: \(HospitalRouteViewModel.distanceText(straight))", systemImage: "arrow.up.right")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let fastDistance = routeModel.fastestDistanceMetres, let fastSeconds = routeModel.fastestSeconds {
                Label("A faster route takes \(HospitalRouteViewModel.durationText(fastSeconds)) but is \(HospitalRouteViewModel.distanceText(fastDistance)).",
                      systemImage: "bolt.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("From: \(routeModel.originDescription)")
                .font(.caption).foregroundStyle(.secondary)
            Text("Route source: \(routeModel.sourceNote). Traffic and road closures can change the route. In an emergency call 1990.")
                .font(.caption2).foregroundStyle(.secondary)
            if routeModel.sourceNote.hasPrefix("OpenStreetMap") {
                HStack(spacing: 10) {
                    Link("© OpenStreetMap", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    Link("FOSSGIS", destination: URL(string: "https://routing.openstreetmap.de/about.html")!)
                }.font(.caption2)
            }
            Button { Task { await routeModel.start(to: hospital) } } label: {
                Label("Recalculate from my location", systemImage: "arrow.clockwise").frame(minHeight: 44)
            }
            .font(.subheadline)
        }
    }
}
