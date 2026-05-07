import Foundation
import SwiftData

@Model
public final class Account {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var kindRaw: String
    public var note: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, kind: AccountKind, note: String = "", createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.note = note
        self.createdAt = createdAt
    }

    public var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .cash }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
public final class Category {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var scopeRaw: String
    public var note: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, scope: CategoryScope, note: String = "", createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.scopeRaw = scope.rawValue
        self.note = note
        self.createdAt = createdAt
    }

    public var scope: CategoryScope {
        get { CategoryScope(rawValue: scopeRaw) ?? .expense }
        set { scopeRaw = newValue.rawValue }
    }
}

@Model
public final class Goal {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var summary: String
    public var stateRaw: String
    public var targetDate: Date?
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, summary: String, state: GoalState = .active, targetDate: Date? = nil, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.summary = summary
        self.stateRaw = state.rawValue
        self.targetDate = targetDate
        self.createdAt = createdAt
    }

    public var state: GoalState {
        get { GoalState(rawValue: stateRaw) ?? .active }
        set { stateRaw = newValue.rawValue }
    }
}

@Model
public final class Project {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var summary: String
    public var stateRaw: String
    public var deadline: Date?
    public var note: String
    public var createdAt: Date
    public var goal: Goal?

    public init(id: UUID = UUID(), title: String, summary: String, state: ProjectState = .active, deadline: Date? = nil, note: String = "", goal: Goal? = nil, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.summary = summary
        self.stateRaw = state.rawValue
        self.deadline = deadline
        self.note = note
        self.goal = goal
        self.createdAt = createdAt
    }

    public var state: ProjectState {
        get { ProjectState(rawValue: stateRaw) ?? .active }
        set { stateRaw = newValue.rawValue }
    }
}

@Model
public final class TaskItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var statusRaw: String
    public var priorityRaw: String
    public var dueDate: Date?
    public var note: String
    public var createdAt: Date
    public var project: Project?

    public init(id: UUID = UUID(), title: String, status: TaskState = .todo, priority: TaskPriority = .medium, dueDate: Date? = nil, note: String = "", project: Project? = nil, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate
        self.note = note
        self.project = project
        self.createdAt = createdAt
    }

    public var status: TaskState {
        get { TaskState(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
}

@Model
public final class CalendarItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var allDay: Bool
    public var location: String
    public var note: String
    public var createdAt: Date
    public var project: Project?

    public init(id: UUID = UUID(), title: String, startDate: Date, endDate: Date, allDay: Bool = false, location: String = "", note: String = "", project: Project? = nil, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.allDay = allDay
        self.location = location
        self.note = note
        self.project = project
        self.createdAt = createdAt
    }
}

@Model
public final class DailyPlanItem {
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    public var plannedDate: Date
    public var sortOrder: Int
    public var note: String
    public var createdAt: Date
    public var task: TaskItem?
    public var calendarItem: CalendarItem?

    public init(
        id: UUID = UUID(),
        kind: DailyPlanItemKind,
        plannedDate: Date,
        sortOrder: Int = 0,
        note: String = "",
        task: TaskItem? = nil,
        calendarItem: CalendarItem? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.plannedDate = plannedDate
        self.sortOrder = sortOrder
        self.note = note
        self.task = task
        self.calendarItem = calendarItem
        self.createdAt = createdAt
    }

    public var kind: DailyPlanItemKind {
        get { DailyPlanItemKind(rawValue: kindRaw) ?? .focus }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
public final class LedgerEntry {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var directionRaw: String
    public var amount: Decimal
    public var occurredOn: Date
    public var note: String
    public var createdAt: Date
    public var account: Account?
    public var category: Category?
    public var project: Project?

    public init(id: UUID = UUID(), title: String, direction: EntryDirection, amount: Decimal, occurredOn: Date, note: String = "", account: Account? = nil, category: Category? = nil, project: Project? = nil, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.directionRaw = direction.rawValue
        self.amount = amount
        self.occurredOn = occurredOn
        self.note = note
        self.account = account
        self.category = category
        self.project = project
        self.createdAt = createdAt
    }

    public var direction: EntryDirection {
        get { EntryDirection(rawValue: directionRaw) ?? .expense }
        set { directionRaw = newValue.rawValue }
    }
}

@Model
public final class PlannedEntry {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var directionRaw: String
    public var amount: Decimal
    public var dueOn: Date
    public var note: String
    public var createdAt: Date
    public var account: Account?
    public var category: Category?
    public var project: Project?

    public init(id: UUID = UUID(), title: String, direction: EntryDirection, amount: Decimal, dueOn: Date, note: String = "", account: Account? = nil, category: Category? = nil, project: Project? = nil, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.directionRaw = direction.rawValue
        self.amount = amount
        self.dueOn = dueOn
        self.note = note
        self.account = account
        self.category = category
        self.project = project
        self.createdAt = createdAt
    }

    public var direction: EntryDirection {
        get { EntryDirection(rawValue: directionRaw) ?? .expense }
        set { directionRaw = newValue.rawValue }
    }
}

@Model
public final class AssetSnapshot {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var amount: Decimal
    public var capturedOn: Date
    public var note: String
    public var quoteSymbol: String?
    public var units: Decimal?
    public var costBasis: Decimal?
    public var createdAt: Date
    public var account: Account?
    public var category: Category?

    public init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        capturedOn: Date,
        note: String = "",
        quoteSymbol: String? = nil,
        units: Decimal? = nil,
        costBasis: Decimal? = nil,
        account: Account? = nil,
        category: Category? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.capturedOn = capturedOn
        self.note = note
        self.quoteSymbol = quoteSymbol
        self.units = units
        self.costBasis = costBasis
        self.account = account
        self.category = category
        self.createdAt = createdAt
    }

    public var normalizedQuoteSymbol: String? {
        let trimmed = (quoteSymbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    public var trackedUnits: Decimal? {
        guard let units, units > 0 else { return nil }
        return units
    }

    public var referenceCostBasis: Decimal {
        costBasis ?? amount
    }

    public var usesLiveMarketQuote: Bool {
        normalizedQuoteSymbol != nil && trackedUnits != nil
    }
}
