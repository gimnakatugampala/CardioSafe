import Foundation

nonisolated enum SOSJourneyStatus: String, CaseIterable {
    case pending, accepted, assigned, patientArrived = "patient_arrived", transporting, hospitalArrived = "hospital_arrived", completed, cancelled
    var title: String {
        switch self {
        case .pending: "New SOS"
        case .accepted: "Awaiting ambulance"
        case .assigned: "Ambulance on the way"
        case .patientArrived: "Arrived at patient"
        case .transporting: "On the way to hospital"
        case .hospitalArrived: "Arrived at hospital"
        case .completed: "Handover completed"
        case .cancelled: "Cancelled"
        }
    }
    var next: Self? {
        switch self {
        case .pending: .accepted
        case .accepted: .assigned
        case .assigned: .patientArrived
        case .patientArrived: .transporting
        case .transporting: .hospitalArrived
        case .hospitalArrived: .completed
        default: nil
        }
    }
    var action: String {
        switch self {
        case .pending: "Accept request"
        case .accepted: "Assign ambulance"
        case .assigned: "Confirm arrived at patient"
        case .patientArrived: "Confirm patient picked up"
        case .transporting: "Confirm arrived at hospital"
        case .hospitalArrived: "Complete handover"
        default: "Completed"
        }
    }
    var timestamp: String? {
        switch self {
        case .assigned: "assignedAt"
        case .patientArrived: "patientArrivedAt"
        case .transporting: "pickedUpAt"
        case .hospitalArrived: "hospitalArrivedAt"
        case .completed: "completedAt"
        default: nil
        }
    }
    var active: Bool { self != .completed && self != .cancelled }
}
