import Foundation
import SwiftData

@MainActor
public final class LifeOSRepository {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func createLedgerEntry(
        title: String,
        direction: EntryDirection,
        amount: Decimal,
        occurredOn: Date,
        account: Account?,
        category: Category?,
        project: Project?,
        note: String = ""
    ) throws -> LedgerEntry {
        let entry = LedgerEntry(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            direction: direction,
            amount: amount,
            occurredOn: occurredOn,
            note: note,
            account: account,
            category: category,
            project: project
        )
        context.insert(entry)
        try save()
        return entry
    }

    @discardableResult
    public func createPlannedEntry(
        title: String,
        direction: EntryDirection,
        amount: Decimal,
        dueOn: Date,
        account: Account?,
        category: Category?,
        project: Project?,
        note: String = ""
    ) throws -> PlannedEntry {
        let entry = PlannedEntry(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            direction: direction,
            amount: amount,
            dueOn: dueOn,
            note: note,
            account: account,
            category: category,
            project: project
        )
        context.insert(entry)
        try save()
        return entry
    }

    @discardableResult
    public func createAssetSnapshot(
        title: String,
        amount: Decimal,
        capturedOn: Date,
        account: Account?,
        category: Category?,
        quoteSymbol: String? = nil,
        units: Decimal? = nil,
        costBasis: Decimal? = nil,
        note: String = ""
    ) throws -> AssetSnapshot {
        let normalizedSymbol = quoteSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let storedSymbol = (normalizedSymbol?.isEmpty == false) ? normalizedSymbol : nil
        let snapshot = AssetSnapshot(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            capturedOn: capturedOn,
            note: note,
            quoteSymbol: storedSymbol,
            units: units,
            costBasis: costBasis,
            account: account,
            category: category
        )
        context.insert(snapshot)
        try save()
        return snapshot
    }

    @discardableResult
    public func createTask(
        title: String,
        dueDate: Date?,
        priority: TaskPriority,
        project: Project?,
        note: String = ""
    ) throws -> TaskItem {
        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority,
            dueDate: dueDate,
            note: note,
            project: project
        )
        context.insert(task)
        try save()
        return task
    }

    @discardableResult
    public func createCalendarItem(
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool,
        location: String,
        note: String,
        project: Project?
    ) throws -> CalendarItem {
        let item = CalendarItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: startDate,
            endDate: max(endDate, startDate),
            allDay: allDay,
            location: location,
            note: note,
            project: project
        )
        context.insert(item)
        try save()
        return item
    }

    @discardableResult
    public func createDailyPlanItem(
        kind: DailyPlanItemKind,
        plannedDate: Date,
        task: TaskItem?,
        calendarItem: CalendarItem? = nil,
        note: String = "",
        sortOrder: Int = 0,
        calendar: Calendar = .current
    ) throws -> DailyPlanItem {
        let normalizedDate = calendar.startOfDay(for: plannedDate)
        if let task,
           let existing = try existingDailyPlanItem(task: task, kind: kind, plannedDate: normalizedDate, calendar: calendar) {
            return existing
        }

        let resolvedSortOrder = sortOrder > 0 ? sortOrder : (try nextDailyPlanSortOrder(on: normalizedDate, kind: kind, calendar: calendar))
        let item = DailyPlanItem(
            kind: kind,
            plannedDate: normalizedDate,
            sortOrder: resolvedSortOrder,
            note: note,
            task: task,
            calendarItem: calendarItem
        )
        context.insert(item)
        try save()
        return item
    }

    @discardableResult
    public func scheduleTask(
        _ task: TaskItem,
        kind: DailyPlanItemKind,
        plannedDate: Date,
        startDate: Date? = nil,
        endDate: Date? = nil,
        note: String = "",
        calendar: Calendar = .current
    ) throws -> DailyPlanItem {
        let normalizedDate = calendar.startOfDay(for: plannedDate)
        if let existing = try existingDailyPlanItem(task: task, kind: kind, plannedDate: normalizedDate, calendar: calendar) {
            return existing
        }

        let linkedCalendarItem: CalendarItem?
        if kind == .timeBlock {
            let start = startDate ?? plannedDate
            let fallbackEnd = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(60 * 60)
            let rawEnd = endDate ?? fallbackEnd
            let safeEnd = rawEnd > start ? rawEnd : fallbackEnd
            let calendarItem = CalendarItem(
                title: task.title,
                startDate: start,
                endDate: safeEnd,
                allDay: false,
                location: "",
                note: note.isEmpty ? "Created from Daily Command Center." : note,
                project: task.project
            )
            context.insert(calendarItem)
            linkedCalendarItem = calendarItem
        } else {
            linkedCalendarItem = nil
        }

        let item = DailyPlanItem(
            kind: kind,
            plannedDate: normalizedDate,
            sortOrder: try nextDailyPlanSortOrder(on: normalizedDate, kind: kind, calendar: calendar),
            note: note,
            task: task,
            calendarItem: linkedCalendarItem
        )
        context.insert(item)
        try save()
        return item
    }

    @discardableResult
    public func applyWeekPlanDraft(_ draft: WeekPlanDraft, calendar: Calendar = .current) throws -> WeekPlanApplyResult {
        try applyWeekPlanDraft(draft, request: .all(in: draft), calendar: calendar)
    }

    @discardableResult
    public func applyWeekPlanDraft(_ draft: WeekPlanDraft, request: WeekPlanApplyRequest, calendar: Calendar = .current) throws -> WeekPlanApplyResult {
        var focusCreated = 0
        var focusSkippedExisting = 0
        var timeBlocksCreated = 0
        var timeBlocksSkippedExisting = 0
        var timeBlocksSkippedForConflict = 0
        var timeBlocksRescheduled = 0
        var timeBlocksSkippedNoAvailableSlot = 0
        var timeBlockOutcomes: [WeekPlanTimeBlockApplyOutcome] = []
        var busyIntervals = try context.fetch(FetchDescriptor<CalendarItem>()).map {
            DateInterval(start: $0.startDate, end: $0.endDate)
        }

        for item in draft.days.flatMap(\.items) {
            guard request.selectedDraftItemIDs.contains(item.id) else {
                continue
            }

            let normalizedDate = calendar.startOfDay(for: item.plannedDate)

            if try existingDailyPlanItem(task: item.task, kind: .focus, plannedDate: normalizedDate, calendar: calendar) == nil {
                _ = try createDailyPlanItem(
                    kind: .focus,
                    plannedDate: normalizedDate,
                    task: item.task,
                    note: "Created from This Week Battle Plan.",
                    calendar: calendar
                )
                focusCreated += 1
            } else {
                focusSkippedExisting += 1
            }

            guard request.timeBlockEnabledDraftItemIDs.contains(item.id),
                  let requestedStart = item.suggestedStart,
                  let requestedEnd = item.suggestedEnd else {
                continue
            }

            if try existingDailyPlanItem(task: item.task, kind: .timeBlock, plannedDate: normalizedDate, calendar: calendar) != nil {
                timeBlocksSkippedExisting += 1
                timeBlockOutcomes.append(
                    WeekPlanTimeBlockApplyOutcome(
                        draftItemID: item.id,
                        taskID: item.task.id,
                        status: .skippedExisting,
                        requestedStart: requestedStart,
                        scheduledStart: nil,
                        scheduledEnd: nil,
                        message: "Time block already exists."
                    )
                )
                continue
            }

            let requestedInterval = DateInterval(start: requestedStart, end: requestedEnd)
            let requestedHasConflict = busyIntervals.contains { intervalsOverlap($0, requestedInterval) }
            if requestedHasConflict && request.options.conflictResolution == .skip {
                timeBlocksSkippedForConflict += 1
                timeBlockOutcomes.append(
                    WeekPlanTimeBlockApplyOutcome(
                        draftItemID: item.id,
                        taskID: item.task.id,
                        status: .skippedConflict,
                        requestedStart: requestedStart,
                        scheduledStart: nil,
                        scheduledEnd: nil,
                        message: "Skipped time block due to conflict."
                    )
                )
                continue
            }

            guard let resolvedInterval = resolveWeekPlanTimeBlockInterval(
                requestedStart: requestedStart,
                requestedEnd: requestedEnd,
                dayStart: normalizedDate,
                busyIntervals: busyIntervals,
                options: request.options,
                calendar: calendar
            ) else {
                timeBlocksSkippedNoAvailableSlot += 1
                timeBlockOutcomes.append(
                    WeekPlanTimeBlockApplyOutcome(
                        draftItemID: item.id,
                        taskID: item.task.id,
                        status: .skippedNoAvailableSlot,
                        requestedStart: requestedStart,
                        scheduledStart: nil,
                        scheduledEnd: nil,
                        message: "Focus only: no available slot."
                    )
                )
                continue
            }

            _ = try scheduleTask(
                item.task,
                kind: .timeBlock,
                plannedDate: normalizedDate,
                startDate: resolvedInterval.start,
                endDate: resolvedInterval.end,
                note: "Created from This Week Battle Plan.",
                calendar: calendar
            )
            busyIntervals.append(resolvedInterval)
            timeBlocksCreated += 1
            let wasRescheduled = resolvedInterval.start != requestedStart || resolvedInterval.end != requestedEnd
            if wasRescheduled {
                timeBlocksRescheduled += 1
            }
            timeBlockOutcomes.append(
                WeekPlanTimeBlockApplyOutcome(
                    draftItemID: item.id,
                    taskID: item.task.id,
                    status: wasRescheduled ? .rescheduled : .created,
                    requestedStart: requestedStart,
                    scheduledStart: resolvedInterval.start,
                    scheduledEnd: resolvedInterval.end,
                    message: wasRescheduled ? "Moved to the next available slot." : "Created at suggested time."
                )
            )
        }

        return WeekPlanApplyResult(
            focusCreated: focusCreated,
            focusSkippedExisting: focusSkippedExisting,
            timeBlocksCreated: timeBlocksCreated,
            timeBlocksSkippedExisting: timeBlocksSkippedExisting,
            timeBlocksSkippedForConflict: timeBlocksSkippedForConflict,
            timeBlocksRescheduled: timeBlocksRescheduled,
            timeBlocksSkippedNoAvailableSlot: timeBlocksSkippedNoAvailableSlot,
            timeBlockOutcomes: timeBlockOutcomes
        )
    }

    @discardableResult
    public func moveDailyPlanItem(
        _ item: DailyPlanItem,
        to plannedDate: Date,
        before target: DailyPlanItem? = nil,
        calendar: Calendar = .current
    ) throws -> DailyPlanItem {
        let sourceDate = item.plannedDate
        let normalizedDate = calendar.startOfDay(for: plannedDate)

        if let task = item.task,
           let existing = try existingDailyPlanItem(task: task, kind: item.kind, plannedDate: normalizedDate, calendar: calendar),
           existing.id != item.id {
            context.delete(item)
            try normalizeDailyPlanSortOrders(on: sourceDate, kind: item.kind, calendar: calendar)
            try normalizeDailyPlanSortOrders(on: normalizedDate, kind: existing.kind, calendar: calendar)
            try save()
            return existing
        }

        item.plannedDate = normalizedDate
        item.sortOrder = try insertionSortOrder(on: normalizedDate, kind: item.kind, before: target, excluding: item.id, calendar: calendar)
        if item.kind == .timeBlock, let calendarItem = item.calendarItem {
            shift(calendarItem, toSameTimeOn: normalizedDate, calendar: calendar)
        }

        try normalizeDailyPlanSortOrders(on: sourceDate, kind: item.kind, calendar: calendar)
        try normalizeDailyPlanSortOrders(on: normalizedDate, kind: item.kind, calendar: calendar)
        try save()
        return item
    }

    @discardableResult
    public func postponeDailyPlanItem(_ item: DailyPlanItem, calendar: Calendar = .current) throws -> DailyPlanItem {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: item.plannedDate) ?? item.plannedDate.addingTimeInterval(24 * 60 * 60)
        return try moveDailyPlanItem(item, to: nextDay, calendar: calendar)
    }

    @discardableResult
    public func reorderDailyPlanItem(_ item: DailyPlanItem, toIndex requestedIndex: Int, calendar: Calendar = .current) throws -> DailyPlanItem {
        var items = try dailyPlanItems(on: item.plannedDate, kind: item.kind, calendar: calendar)
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return item
        }

        let movingItem = items.remove(at: currentIndex)
        let targetIndex = min(max(requestedIndex, 0), items.count)
        items.insert(movingItem, at: targetIndex)

        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
        try save()
        return item
    }

    public func unscheduleDailyPlanItem(_ item: DailyPlanItem, calendar: Calendar = .current) throws {
        let plannedDate = item.plannedDate
        let kind = item.kind
        context.delete(item)
        try normalizeDailyPlanSortOrders(on: plannedDate, kind: kind, calendar: calendar)
        try save()
    }

    @discardableResult
    public func createGoal(
        title: String,
        summary: String,
        targetDate: Date?,
        state: GoalState = .active
    ) throws -> Goal {
        let goal = Goal(title: title.trimmingCharacters(in: .whitespacesAndNewlines), summary: summary, state: state, targetDate: targetDate)
        context.insert(goal)
        try save()
        return goal
    }

    @discardableResult
    public func createProject(
        title: String,
        summary: String,
        deadline: Date?,
        goal: Goal?,
        state: ProjectState = .active,
        note: String = ""
    ) throws -> Project {
        let project = Project(title: title.trimmingCharacters(in: .whitespacesAndNewlines), summary: summary, state: state, deadline: deadline, note: note, goal: goal)
        context.insert(project)
        try save()
        return project
    }

    @discardableResult
    public func createAccount(name: String, kind: AccountKind, note: String = "") throws -> Account {
        let account = Account(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, note: note)
        context.insert(account)
        try save()
        return account
    }

    @discardableResult
    public func createCategory(name: String, scope: CategoryScope, note: String = "") throws -> Category {
        let category = Category(name: name.trimmingCharacters(in: .whitespacesAndNewlines), scope: scope, note: note)
        context.insert(category)
        try save()
        return category
    }

    public func toggleTask(_ task: TaskItem) throws {
        task.status = task.status == .done ? .todo : .done
        try save()
    }

    @discardableResult
    public func settle(_ plannedEntry: PlannedEntry, occurredOn: Date = .now) throws -> LedgerEntry {
        let entry = LedgerEntry(
            title: plannedEntry.title,
            direction: plannedEntry.direction,
            amount: plannedEntry.amount,
            occurredOn: occurredOn,
            note: plannedEntry.note,
            account: plannedEntry.account,
            category: plannedEntry.category,
            project: plannedEntry.project
        )
        context.insert(entry)
        context.delete(plannedEntry)
        try save()
        return entry
    }

    public func delete<Model: PersistentModel>(_ model: Model) throws {
        context.delete(model)
        try save()
    }

    public func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private func existingDailyPlanItem(
        task: TaskItem,
        kind: DailyPlanItemKind,
        plannedDate: Date,
        calendar: Calendar
    ) throws -> DailyPlanItem? {
        let items = try context.fetch(FetchDescriptor<DailyPlanItem>())
        return items.first { item in
            item.task?.id == task.id &&
            item.kind == kind &&
            calendar.isDate(item.plannedDate, inSameDayAs: plannedDate)
        }
    }

    private func dailyPlanItems(on plannedDate: Date, kind: DailyPlanItemKind, calendar: Calendar, excluding excludedID: UUID? = nil) throws -> [DailyPlanItem] {
        let items = try context.fetch(FetchDescriptor<DailyPlanItem>())
        return items
            .filter { item in
                item.kind == kind &&
                calendar.isDate(item.plannedDate, inSameDayAs: plannedDate) &&
                item.id != excludedID
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private func nextDailyPlanSortOrder(on plannedDate: Date, kind: DailyPlanItemKind, calendar: Calendar) throws -> Int {
        let items = try dailyPlanItems(on: plannedDate, kind: kind, calendar: calendar)
        return (items.map(\.sortOrder).max() ?? -1) + 1
    }

    private func insertionSortOrder(on plannedDate: Date, kind: DailyPlanItemKind, before target: DailyPlanItem?, excluding excludedID: UUID, calendar: Calendar) throws -> Int {
        guard let target,
              target.id != excludedID,
              target.kind == kind,
              calendar.isDate(target.plannedDate, inSameDayAs: plannedDate)
        else {
            return try nextDailyPlanSortOrder(on: plannedDate, kind: kind, calendar: calendar)
        }
        return target.sortOrder - 1
    }

    private func normalizeDailyPlanSortOrders(on plannedDate: Date, kind: DailyPlanItemKind, calendar: Calendar) throws {
        let items = try dailyPlanItems(on: plannedDate, kind: kind, calendar: calendar)
        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
    }

    private func calendarConflictExists(startDate: Date, endDate: Date) throws -> Bool {
        let items = try context.fetch(FetchDescriptor<CalendarItem>())
        return items.contains { item in
            item.startDate < endDate && item.endDate > startDate
        }
    }

    private func resolveWeekPlanTimeBlockInterval(
        requestedStart: Date,
        requestedEnd: Date,
        dayStart: Date,
        busyIntervals: [DateInterval],
        options: WeekPlanApplyOptions,
        calendar: Calendar
    ) -> DateInterval? {
        let requestedDuration = max(requestedEnd.timeIntervalSince(requestedStart), TimeInterval(options.slotDurationMinutes * 60))
        let duration = TimeInterval(max(options.slotDurationMinutes * 60, Int(requestedDuration)))
        let requestedInterval = DateInterval(start: requestedStart, duration: duration)
        if isWeekPlanSlotAvailable(requestedInterval, busyIntervals: busyIntervals) {
            return requestedInterval
        }

        guard options.conflictResolution == .findAvailableSlot else {
            return nil
        }

        let window = weekPlanSearchWindow(on: dayStart, options: options, calendar: calendar)
        let step = TimeInterval(max(options.searchStepMinutes, 1) * 60)
        let latestStart = window.end.addingTimeInterval(-duration)
        guard latestStart >= window.start else { return nil }

        let forwardStart = max(requestedStart, window.start)
        var candidateStart = alignToStep(forwardStart, step: step, calendar: calendar)
        while candidateStart <= latestStart {
            let candidate = DateInterval(start: candidateStart, duration: duration)
            if isWeekPlanSlotAvailable(candidate, busyIntervals: busyIntervals) {
                return candidate
            }
            candidateStart = candidateStart.addingTimeInterval(step)
        }

        var backwardStart = window.start
        let backwardLimit = min(requestedStart.addingTimeInterval(-step), latestStart)
        while backwardStart <= backwardLimit {
            let candidate = DateInterval(start: backwardStart, duration: duration)
            if isWeekPlanSlotAvailable(candidate, busyIntervals: busyIntervals) {
                return candidate
            }
            backwardStart = backwardStart.addingTimeInterval(step)
        }

        return nil
    }

    private func weekPlanSearchWindow(on dayStart: Date, options: WeekPlanApplyOptions, calendar: Calendar) -> DateInterval {
        let date = calendar.dateComponents([.year, .month, .day], from: dayStart)
        let start = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: date.year,
            month: date.month,
            day: date.day,
            hour: options.searchWindowStartHour,
            minute: options.searchWindowStartMinute
        )) ?? dayStart
        let end = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: date.year,
            month: date.month,
            day: date.day,
            hour: options.searchWindowEndHour,
            minute: options.searchWindowEndMinute
        )) ?? start.addingTimeInterval(14.5 * 60 * 60)
        return DateInterval(start: start, end: max(end, start))
    }

    private func isWeekPlanSlotAvailable(_ interval: DateInterval, busyIntervals: [DateInterval]) -> Bool {
        busyIntervals.contains { intervalsOverlap($0, interval) } == false
    }

    private func intervalsOverlap(_ lhs: DateInterval, _ rhs: DateInterval) -> Bool {
        lhs.start < rhs.end && lhs.end > rhs.start
    }

    private func alignToStep(_ date: Date, step: TimeInterval, calendar: Calendar) -> Date {
        let reference = calendar.startOfDay(for: date)
        let elapsed = date.timeIntervalSince(reference)
        let steps = ceil(elapsed / step)
        return reference.addingTimeInterval(steps * step)
    }

    private func shift(_ calendarItem: CalendarItem, toSameTimeOn plannedDate: Date, calendar: Calendar) {
        let duration = calendarItem.endDate.timeIntervalSince(calendarItem.startDate)
        let time = calendar.dateComponents([.hour, .minute, .second], from: calendarItem.startDate)
        let date = calendar.dateComponents([.year, .month, .day], from: plannedDate)
        let shiftedStart = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: date.year,
            month: date.month,
            day: date.day,
            hour: time.hour,
            minute: time.minute,
            second: time.second
        )) ?? plannedDate
        calendarItem.startDate = shiftedStart
        calendarItem.endDate = shiftedStart.addingTimeInterval(max(duration, 60 * 15))
    }
}
