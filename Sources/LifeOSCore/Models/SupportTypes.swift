import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case traditionalChinese = "zh-Hant"

    public var id: String { rawValue }

    public var localeIdentifier: String { rawValue }
}

public enum EntryDirection: String, CaseIterable, Codable, Identifiable {
    case income
    case expense

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        }
    }
}

public enum CategoryScope: String, CaseIterable, Codable, Identifiable {
    case income
    case expense
    case asset

    public var id: String { rawValue }
}

public enum AccountKind: String, CaseIterable, Codable, Identifiable {
    case cash
    case bank
    case digital
    case investment

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cash: "Cash"
        case .bank: "Bank"
        case .digital: "Digital"
        case .investment: "Investment"
        }
    }

    public var isLiquid: Bool {
        switch self {
        case .cash, .bank, .digital:
            true
        case .investment:
            false
        }
    }
}

public enum GoalState: String, CaseIterable, Codable, Identifiable {
    case active
    case planned
    case paused
    case done

    public var id: String { rawValue }
}

public enum ProjectState: String, CaseIterable, Codable, Identifiable {
    case active
    case planned
    case paused
    case done

    public var id: String { rawValue }
}

public enum TaskState: String, CaseIterable, Codable, Identifiable {
    case todo
    case doing
    case done

    public var id: String { rawValue }
}

public enum TaskPriority: String, CaseIterable, Codable, Identifiable {
    case low
    case medium
    case high
    case critical

    public var id: String { rawValue }

    public var rank: Int {
        switch self {
        case .critical: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        }
    }
}

public enum DailyPlanItemKind: String, CaseIterable, Codable, Identifiable {
    case focus
    case timeBlock

    public var id: String { rawValue }
}

public enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case ledger
    case planned
    case assets
    case tasks
    case calendar
    case goals
    case projects
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .ledger: "Ledger"
        case .planned: "Planned"
        case .assets: "Assets"
        case .tasks: "Tasks"
        case .calendar: "Calendar"
        case .goals: "Goals"
        case .projects: "Projects"
        case .settings: "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .ledger: "list.bullet.rectangle.portrait"
        case .planned: "calendar.badge.clock"
        case .assets: "chart.line.uptrend.xyaxis"
        case .tasks: "checklist"
        case .calendar: "calendar"
        case .goals: "flag.2.crossed.fill"
        case .projects: "square.stack.3d.up.fill"
        case .settings: "gearshape.fill"
        }
    }
}

public struct OverviewSnapshot {
    public var monthIncome: Decimal
    public var monthExpense: Decimal
    public var monthNet: Decimal
    public var plannedIncome30Days: Decimal
    public var plannedExpense30Days: Decimal
    public var plannedNet30Days: Decimal
    public var assetTotal: Decimal
    public var liquidBalance: Decimal
    public var investableAssetTotal: Decimal
    public var totalWealthSnapshot: Decimal
    public var freeCashAfterPlanned30Days: Decimal
    public var projectedLiquidAfter30Days: Decimal
    public var accountBalances: [AccountBalanceSnapshot]
    public var urgentTasks: [TaskItem]
    public var todayEvents: [CalendarItem]
    public var upcomingPlanned: [PlannedEntry]
    public var projectStatuses: [ProjectStatusSnapshot]
    public var conflicts: [ConflictItem]

    public init(
        monthIncome: Decimal,
        monthExpense: Decimal,
        monthNet: Decimal,
        plannedIncome30Days: Decimal,
        plannedExpense30Days: Decimal,
        plannedNet30Days: Decimal,
        assetTotal: Decimal,
        liquidBalance: Decimal,
        investableAssetTotal: Decimal,
        totalWealthSnapshot: Decimal,
        freeCashAfterPlanned30Days: Decimal,
        projectedLiquidAfter30Days: Decimal,
        accountBalances: [AccountBalanceSnapshot],
        urgentTasks: [TaskItem],
        todayEvents: [CalendarItem],
        upcomingPlanned: [PlannedEntry],
        projectStatuses: [ProjectStatusSnapshot],
        conflicts: [ConflictItem]
    ) {
        self.monthIncome = monthIncome
        self.monthExpense = monthExpense
        self.monthNet = monthNet
        self.plannedIncome30Days = plannedIncome30Days
        self.plannedExpense30Days = plannedExpense30Days
        self.plannedNet30Days = plannedNet30Days
        self.assetTotal = assetTotal
        self.liquidBalance = liquidBalance
        self.investableAssetTotal = investableAssetTotal
        self.totalWealthSnapshot = totalWealthSnapshot
        self.freeCashAfterPlanned30Days = freeCashAfterPlanned30Days
        self.projectedLiquidAfter30Days = projectedLiquidAfter30Days
        self.accountBalances = accountBalances
        self.urgentTasks = urgentTasks
        self.todayEvents = todayEvents
        self.upcomingPlanned = upcomingPlanned
        self.projectStatuses = projectStatuses
        self.conflicts = conflicts
    }
}

public struct AccountBalanceSnapshot: Identifiable {
    public let id: UUID
    public let name: String
    public let kind: AccountKind
    public let balance: Decimal

    public init(id: UUID, name: String, kind: AccountKind, balance: Decimal) {
        self.id = id
        self.name = name
        self.kind = kind
        self.balance = balance
    }
}

public struct ProjectStatusSnapshot: Identifiable {
    public let id: UUID
    public let title: String
    public let readiness: Int
    public let openTaskCount: Int
    public let deadline: Date?
    public let state: ProjectState
    public let focus: String

    public init(id: UUID, title: String, readiness: Int, openTaskCount: Int, deadline: Date?, state: ProjectState, focus: String) {
        self.id = id
        self.title = title
        self.readiness = readiness
        self.openTaskCount = openTaskCount
        self.deadline = deadline
        self.state = state
        self.focus = focus
    }
}

public enum ConflictSeverity: String, Identifiable {
    case medium
    case high
    case critical

    public var id: String { rawValue }
}

public struct ConflictItem: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let severity: ConflictSeverity
    public let action: String

    public init(id: String, title: String, detail: String, severity: ConflictSeverity, action: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.action = action
    }
}

public enum CommandPlanSource: String, Identifiable {
    case manual
    case automatic

    public var id: String { rawValue }
}

public struct CommandCenterSnapshot {
    public let generatedAt: Date
    public let days: [CommandDaySnapshot]
    public let deadlineRisks: [CommandRiskItem]

    public var today: CommandDaySnapshot? {
        days.first
    }

    public init(generatedAt: Date, days: [CommandDaySnapshot], deadlineRisks: [CommandRiskItem]) {
        self.generatedAt = generatedAt
        self.days = days
        self.deadlineRisks = deadlineRisks
    }
}

public struct CommandDaySnapshot: Identifiable {
    public let id: String
    public let date: Date
    public let focusItems: [CommandFocusItem]
    public let timeBlocks: [CommandTimeBlockItem]
    public let deadlineRisks: [CommandRiskItem]

    public init(id: String, date: Date, focusItems: [CommandFocusItem], timeBlocks: [CommandTimeBlockItem], deadlineRisks: [CommandRiskItem]) {
        self.id = id
        self.date = date
        self.focusItems = focusItems
        self.timeBlocks = timeBlocks
        self.deadlineRisks = deadlineRisks
    }
}

public struct CommandFocusItem: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let source: CommandPlanSource
    public let task: TaskItem?
    public let planItem: DailyPlanItem?
    public let dueDate: Date?
    public let projectTitle: String?
    public let priority: TaskPriority?

    public init(id: String, title: String, detail: String, source: CommandPlanSource, task: TaskItem?, planItem: DailyPlanItem?, dueDate: Date?, projectTitle: String?, priority: TaskPriority?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.source = source
        self.task = task
        self.planItem = planItem
        self.dueDate = dueDate
        self.projectTitle = projectTitle
        self.priority = priority
    }
}

public struct CommandTimeBlockItem: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let calendarItem: CalendarItem
    public let planItem: DailyPlanItem?
    public let task: TaskItem?

    public var isTaskSchedule: Bool {
        planItem != nil
    }

    public init(id: String, title: String, detail: String, calendarItem: CalendarItem, planItem: DailyPlanItem?, task: TaskItem?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.calendarItem = calendarItem
        self.planItem = planItem
        self.task = task
    }
}

public struct CommandRiskItem: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let deadline: Date
    public let severity: ConflictSeverity
    public let project: Project
    public let nextTask: TaskItem?

    public init(id: String, title: String, detail: String, deadline: Date, severity: ConflictSeverity, project: Project, nextTask: TaskItem?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.deadline = deadline
        self.severity = severity
        self.project = project
        self.nextTask = nextTask
    }
}

public struct ScheduleQualitySnapshot {
    public let generatedAt: Date
    public let days: [ScheduleQualityDaySnapshot]
    public let repeatedTasks: [ScheduleRepeatedTask]
    public let needsTimeBlockItems: [ScheduleNeedsTimeBlockItem]

    public var repeatedTaskCount: Int {
        repeatedTasks.count
    }

    public var needsTimeBlockCount: Int {
        needsTimeBlockItems.count
    }

    public var riskDayCount: Int {
        days.filter { $0.repeatedFocusCount > 0 || $0.needsTimeBlockCount > 0 }.count
    }

    public init(generatedAt: Date, days: [ScheduleQualityDaySnapshot], repeatedTasks: [ScheduleRepeatedTask], needsTimeBlockItems: [ScheduleNeedsTimeBlockItem]) {
        self.generatedAt = generatedAt
        self.days = days
        self.repeatedTasks = repeatedTasks
        self.needsTimeBlockItems = needsTimeBlockItems
    }

    public func day(on date: Date, calendar: Calendar = .current) -> ScheduleQualityDaySnapshot? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    public func repeatedTask(for taskID: UUID) -> ScheduleRepeatedTask? {
        repeatedTasks.first { $0.task.id == taskID }
    }

    public func needsTimeBlockIssue(for taskID: UUID, on date: Date, calendar: Calendar = .current) -> ScheduleNeedsTimeBlockItem? {
        needsTimeBlockItems.first { issue in
            issue.task.id == taskID && calendar.isDate(issue.plannedDate, inSameDayAs: date)
        }
    }
}

public struct ScheduleQualityDaySnapshot: Identifiable {
    public let id: String
    public let date: Date
    public let repeatedFocusCount: Int
    public let needsTimeBlockCount: Int
    public let timeBlockCount: Int

    public init(id: String, date: Date, repeatedFocusCount: Int, needsTimeBlockCount: Int, timeBlockCount: Int) {
        self.id = id
        self.date = date
        self.repeatedFocusCount = repeatedFocusCount
        self.needsTimeBlockCount = needsTimeBlockCount
        self.timeBlockCount = timeBlockCount
    }
}

public struct ScheduleRepeatedTask: Identifiable {
    public let id: String
    public let task: TaskItem
    public let scheduledDates: [Date]
    public let planItems: [DailyPlanItem]

    public init(task: TaskItem, scheduledDates: [Date], planItems: [DailyPlanItem]) {
        self.id = task.id.uuidString
        self.task = task
        self.scheduledDates = scheduledDates
        self.planItems = planItems
    }
}

public enum ScheduleNeedsTimeBlockReason: String, Codable, Identifiable {
    case highPriority
    case dueSoon
    case projectDeadlineSoon

    public var id: String { rawValue }
}

public struct ScheduleNeedsTimeBlockItem: Identifiable {
    public let id: String
    public let task: TaskItem
    public let planItem: DailyPlanItem?
    public let plannedDate: Date
    public let reason: ScheduleNeedsTimeBlockReason

    public init(task: TaskItem, planItem: DailyPlanItem?, plannedDate: Date, reason: ScheduleNeedsTimeBlockReason, calendar: Calendar = .current) {
        self.id = "\(Self.dayKey(plannedDate, calendar: calendar))-\(task.id.uuidString)"
        self.task = task
        self.planItem = planItem
        self.plannedDate = plannedDate
        self.reason = reason
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

public enum WeekPlanLine: String, CaseIterable, Codable, Identifiable {
    case competition
    case earning
    case travel
    case investment
    case snow
    case academic
    case general

    public var id: String { rawValue }
}

public struct WeekPlanDraft: Identifiable {
    public let id: UUID
    public let generatedAt: Date
    public let days: [WeekPlanDayDraft]

    public var focusCount: Int {
        days.reduce(0) { $0 + $1.items.count }
    }

    public var proposedTimeBlockCount: Int {
        days.reduce(0) { total, day in
            total + day.items.filter { $0.suggestedStart != nil && $0.suggestedEnd != nil }.count
        }
    }

    public var conflictCount: Int {
        days.reduce(0) { total, day in
            total + day.items.filter(\.timeBlockConflict).count
        }
    }

    public init(id: UUID = UUID(), generatedAt: Date, days: [WeekPlanDayDraft]) {
        self.id = id
        self.generatedAt = generatedAt
        self.days = days
    }
}

public struct WeekPlanDayDraft: Identifiable {
    public let id: String
    public let date: Date
    public let items: [WeekPlanDraftItem]

    public init(id: String, date: Date, items: [WeekPlanDraftItem]) {
        self.id = id
        self.date = date
        self.items = items
    }
}

public struct WeekPlanDraftItem: Identifiable {
    public let id: String
    public let task: TaskItem
    public let line: WeekPlanLine
    public let reason: String
    public let plannedDate: Date
    public let suggestedStart: Date?
    public let suggestedEnd: Date?
    public let timeBlockConflict: Bool
    public let conflictTitle: String?

    public init(
        id: String,
        task: TaskItem,
        line: WeekPlanLine,
        reason: String,
        plannedDate: Date,
        suggestedStart: Date?,
        suggestedEnd: Date?,
        timeBlockConflict: Bool,
        conflictTitle: String?
    ) {
        self.id = id
        self.task = task
        self.line = line
        self.reason = reason
        self.plannedDate = plannedDate
        self.suggestedStart = suggestedStart
        self.suggestedEnd = suggestedEnd
        self.timeBlockConflict = timeBlockConflict
        self.conflictTitle = conflictTitle
    }
}

public enum WeekPlanTimeBlockConflictResolution: String, Codable, Identifiable {
    case skip
    case findAvailableSlot

    public var id: String { rawValue }
}

public struct WeekPlanApplyOptions {
    public let conflictResolution: WeekPlanTimeBlockConflictResolution
    public let searchWindowStartHour: Int
    public let searchWindowStartMinute: Int
    public let searchWindowEndHour: Int
    public let searchWindowEndMinute: Int
    public let slotDurationMinutes: Int
    public let searchStepMinutes: Int

    public init(
        conflictResolution: WeekPlanTimeBlockConflictResolution = .findAvailableSlot,
        searchWindowStartHour: Int = 8,
        searchWindowStartMinute: Int = 0,
        searchWindowEndHour: Int = 22,
        searchWindowEndMinute: Int = 30,
        slotDurationMinutes: Int = 60,
        searchStepMinutes: Int = 10
    ) {
        self.conflictResolution = conflictResolution
        self.searchWindowStartHour = searchWindowStartHour
        self.searchWindowStartMinute = searchWindowStartMinute
        self.searchWindowEndHour = searchWindowEndHour
        self.searchWindowEndMinute = searchWindowEndMinute
        self.slotDurationMinutes = slotDurationMinutes
        self.searchStepMinutes = searchStepMinutes
    }
}

public struct WeekPlanApplyRequest {
    public let selectedDraftItemIDs: Set<String>
    public let timeBlockEnabledDraftItemIDs: Set<String>
    public let options: WeekPlanApplyOptions

    public init(
        selectedDraftItemIDs: Set<String>,
        timeBlockEnabledDraftItemIDs: Set<String>,
        options: WeekPlanApplyOptions = WeekPlanApplyOptions()
    ) {
        self.selectedDraftItemIDs = selectedDraftItemIDs
        self.timeBlockEnabledDraftItemIDs = timeBlockEnabledDraftItemIDs.intersection(selectedDraftItemIDs)
        self.options = options
    }

    public static func all(in draft: WeekPlanDraft, options: WeekPlanApplyOptions = WeekPlanApplyOptions()) -> WeekPlanApplyRequest {
        let eligibleIDs = Set(draft.days.flatMap(\.items).map(\.id))
        return WeekPlanApplyRequest(
            selectedDraftItemIDs: eligibleIDs,
            timeBlockEnabledDraftItemIDs: eligibleIDs,
            options: options
        )
    }
}

public enum WeekPlanTimeBlockApplyStatus: String, Codable, Equatable {
    case created
    case rescheduled
    case skippedExisting
    case skippedConflict
    case skippedNoAvailableSlot
}

public struct WeekPlanTimeBlockApplyOutcome: Identifiable {
    public let id: String
    public let draftItemID: String
    public let taskID: UUID
    public let status: WeekPlanTimeBlockApplyStatus
    public let requestedStart: Date?
    public let scheduledStart: Date?
    public let scheduledEnd: Date?
    public let message: String

    public init(
        draftItemID: String,
        taskID: UUID,
        status: WeekPlanTimeBlockApplyStatus,
        requestedStart: Date?,
        scheduledStart: Date?,
        scheduledEnd: Date?,
        message: String
    ) {
        self.id = "\(draftItemID)-\(status.rawValue)"
        self.draftItemID = draftItemID
        self.taskID = taskID
        self.status = status
        self.requestedStart = requestedStart
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.message = message
    }
}

public struct WeekPlanApplyResult {
    public let focusCreated: Int
    public let focusSkippedExisting: Int
    public let timeBlocksCreated: Int
    public let timeBlocksSkippedExisting: Int
    public let timeBlocksSkippedForConflict: Int
    public let timeBlocksRescheduled: Int
    public let timeBlocksSkippedNoAvailableSlot: Int
    public let timeBlockOutcomes: [WeekPlanTimeBlockApplyOutcome]

    public var totalSkipped: Int {
        focusSkippedExisting + timeBlocksSkippedExisting + timeBlocksSkippedForConflict + timeBlocksSkippedNoAvailableSlot
    }

    public init(
        focusCreated: Int,
        focusSkippedExisting: Int,
        timeBlocksCreated: Int,
        timeBlocksSkippedExisting: Int,
        timeBlocksSkippedForConflict: Int,
        timeBlocksRescheduled: Int = 0,
        timeBlocksSkippedNoAvailableSlot: Int = 0,
        timeBlockOutcomes: [WeekPlanTimeBlockApplyOutcome] = []
    ) {
        self.focusCreated = focusCreated
        self.focusSkippedExisting = focusSkippedExisting
        self.timeBlocksCreated = timeBlocksCreated
        self.timeBlocksSkippedExisting = timeBlocksSkippedExisting
        self.timeBlocksSkippedForConflict = timeBlocksSkippedForConflict
        self.timeBlocksRescheduled = timeBlocksRescheduled
        self.timeBlocksSkippedNoAvailableSlot = timeBlocksSkippedNoAvailableSlot
        self.timeBlockOutcomes = timeBlockOutcomes
    }
}
