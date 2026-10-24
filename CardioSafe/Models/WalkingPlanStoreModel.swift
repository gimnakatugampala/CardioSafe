import CoreData

@MainActor
enum WalkingPlanStoreModel {
    static func makeModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "WalkingPlanRecord"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("ownerID", type: .stringAttributeType),
            attribute("walkingMinutes", type: .integer64AttributeType),
            attribute("restMinutesPerBreak", type: .integer64AttributeType, optional: true),
            attribute("updatedAt", type: .dateAttributeType)
        ]
        entity.uniquenessConstraints = [["ownerID"]]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    private static func attribute(_ name: String, type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}
