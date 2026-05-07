import SwiftData

public enum LifeOSModelContainer {
    public static var schema: Schema {
        let models: [any PersistentModel.Type] = [
            Account.self,
            Category.self,
            Goal.self,
            Project.self,
            TaskItem.self,
            CalendarItem.self,
            DailyPlanItem.self,
            LedgerEntry.self,
            PlannedEntry.self,
            AssetSnapshot.self,
        ]
        return Schema(models)
    }

    @MainActor
    public static func shared(inMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "LifeOSData",
            schema: schema,
            isStoredInMemoryOnly: inMemoryOnly
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
