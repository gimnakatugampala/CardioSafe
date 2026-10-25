import Foundation

struct PatientProfile: Codable, Equatable {
    var fullName = ""
    var dateOfBirth: Date?
    var phoneNumber = ""
    var emergencyContactName = ""
    var emergencyContactPhone = ""
}
