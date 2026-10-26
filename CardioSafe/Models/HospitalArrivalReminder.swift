import Foundation

struct ArrivalPlace: Codable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    var isValid: Bool {
        !name.isEmpty && latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct HospitalArrivalReminder: Codable, Equatable, Identifiable {
    let id: UUID
    let place: ArrivalPlace
    var hasBeenOutside: Bool
    static let radiusMetres: Double = 200
    var regionID: String { "cardiosafe.arrival." + id.uuidString }
}

enum ArrivalLocationPermission { case notDetermined, whenInUse, always, denied }
struct ArrivalAccess {
    let permission: ArrivalLocationPermission
    let precise: Bool
    let supported: Bool
    var canMonitor: Bool { supported && precise && permission == .always }
}
enum ArrivalEvent {
    case accessChanged
    case started(String)
    case state(String, inside: Bool)
    case entered(String)
    case exited(String)
    case failed(String?)
}
@MainActor protocol ArrivalMonitoring: AnyObject {
    var onEvent: ((ArrivalEvent) -> Void)? { get set }
    var access: ArrivalAccess { get }
    func requestWhenInUse()
    func requestAlways()
    func start(_ reminder: HospitalArrivalReminder)
    func stop()
}
@MainActor protocol ArrivalNotifying {
    func authorize() async throws -> Bool
    func schedule(id: String) async throws
    func cancel(id: String)
}
@MainActor protocol ArrivalReminderStoring {
    func load() throws -> HospitalArrivalReminder?
    func save(_ reminder: HospitalArrivalReminder?) throws
}
@MainActor final class ArrivalReminderStore: ArrivalReminderStoring {
    private let defaults: UserDefaults
    private let key = "hospitalArrivalReminder.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() throws -> HospitalArrivalReminder? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let reminder = try JSONDecoder().decode(HospitalArrivalReminder.self, from: data)
        guard reminder.place.isValid else { throw CocoaError(.fileReadCorruptFile) }
        return reminder
    }
    func save(_ reminder: HospitalArrivalReminder?) throws {
        if let reminder { defaults.set(try JSONEncoder().encode(reminder), forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}
