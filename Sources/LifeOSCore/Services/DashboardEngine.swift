import Foundation

public enum DashboardEngine {
    public static func makeOverview(
        accounts: [Account],
        ledgerEntries: [LedgerEntry],
        plannedEntries: [PlannedEntry],
        assetSnapshots: [AssetSnapshot],
        tasks: [TaskItem],
        calendarItems: [CalendarItem],
        projects: [Project],
        language: AppLanguage = .english,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> OverviewSnapshot {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)) ?? referenceDate
        let monthWindow = calendar.dateInterval(of: .month, for: referenceDate) ?? DateInterval(start: monthStart, duration: 31 * 24 * 60 * 60)
        let thirtyDaysLater = calendar.date(byAdding: .day, value: 30, to: referenceDate) ?? referenceDate
        let todayStart = calendar.startOfDay(for: referenceDate)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? referenceDate

        let monthLedger = ledgerEntries.filter { monthWindow.contains($0.occurredOn) }
        let monthIncome = sum(monthLedger.filter { $0.direction == .income }.map(\.amount))
        let monthExpense = sum(monthLedger.filter { $0.direction == .expense }.map(\.amount))

        let nearPlanned = plannedEntries
            .filter { $0.dueOn >= todayStart && $0.dueOn <= thirtyDaysLater }
            .sorted { $0.dueOn < $1.dueOn }
        let plannedIncome = sum(nearPlanned.filter { $0.direction == .income }.map(\.amount))
        let plannedExpense = sum(nearPlanned.filter { $0.direction == .expense }.map(\.amount))

        let assetTotal = latestAssetTotal(assetSnapshots)
        let latestSnapshots = latestAssetSnapshots(assetSnapshots)
        let accountBalances = makeAccountBalances(accounts: accounts, ledgerEntries: ledgerEntries)
        let liquidBalance = sum(accountBalances.filter { $0.kind.isLiquid }.map(\.balance))
        let investableAssetTotal = sum(latestSnapshots.filter(isNonLiquidAssetSnapshot).map(\.amount))
        let totalWealthSnapshot = liquidBalance + investableAssetTotal
        let freeCashAfterPlanned30Days = liquidBalance - plannedExpense
        let projectedLiquidAfter30Days = liquidBalance + plannedIncome - plannedExpense

        let urgentTasks = tasks
            .filter { $0.status != .done }
            .sorted {
                if $0.priority.rank != $1.priority.rank {
                    return $0.priority.rank < $1.priority.rank
                }
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            .prefix(5)

        let todayEvents = calendarItems
            .filter { item in
                item.startDate < tomorrowStart && item.endDate >= todayStart
            }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)

        let projectStatuses = projects
            .map { project in
                let projectTasks = tasks.filter { $0.project?.id == project.id }
                let openTasks = projectTasks.filter { $0.status != .done }
                let completedTaskCount = projectTasks.count - openTasks.count
                let readiness = projectTasks.isEmpty ? 0 : Int((Double(completedTaskCount) / Double(projectTasks.count)) * 100)
                let focus = openTasks.first?.title ?? localizedString("Add the first task or time block.", language: language)
                return ProjectStatusSnapshot(
                    id: project.id,
                    title: project.title,
                    readiness: readiness,
                    openTaskCount: openTasks.count,
                    deadline: project.deadline,
                    state: project.state,
                    focus: focus
                )
            }
            .sorted {
                if $0.readiness != $1.readiness {
                    return $0.readiness < $1.readiness
                }
                return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
            }

        let conflicts = collectConflicts(tasks: tasks, calendarItems: calendarItems, projectStatuses: projectStatuses, language: language, referenceDate: referenceDate)

        return OverviewSnapshot(
            monthIncome: monthIncome,
            monthExpense: monthExpense,
            monthNet: monthIncome - monthExpense,
            plannedIncome30Days: plannedIncome,
            plannedExpense30Days: plannedExpense,
            plannedNet30Days: plannedIncome - plannedExpense,
            assetTotal: assetTotal,
            liquidBalance: liquidBalance,
            investableAssetTotal: investableAssetTotal,
            totalWealthSnapshot: totalWealthSnapshot,
            freeCashAfterPlanned30Days: freeCashAfterPlanned30Days,
            projectedLiquidAfter30Days: projectedLiquidAfter30Days,
            accountBalances: accountBalances,
            urgentTasks: Array(urgentTasks),
            todayEvents: Array(todayEvents),
            upcomingPlanned: Array(nearPlanned.prefix(6)),
            projectStatuses: Array(projectStatuses.prefix(6)),
            conflicts: Array(conflicts.prefix(8))
        )
    }

    public static func collectConflicts(
        tasks: [TaskItem],
        calendarItems: [CalendarItem],
        projectStatuses: [ProjectStatusSnapshot],
        language: AppLanguage = .english,
        referenceDate: Date = .now
    ) -> [ConflictItem] {
        var items: [ConflictItem] = []
        let locale = Locale(identifier: language.localeIdentifier)

        for task in tasks where task.status != .done {
            guard let dueDate = task.dueDate else { continue }
            if dueDate < referenceDate {
                let dueDateText = localizedDateTime(dueDate, locale: locale)
                items.append(
                    ConflictItem(
                        id: "task-overdue-\(task.id.uuidString)",
                        title: localizedString("Overdue task: %@", language: language, task.title),
                        detail: localizedString("Task should have been done by %@.", language: language, dueDateText),
                        severity: .high,
                        action: localizedString("Either finish it now, reschedule it, or delete it.", language: language)
                    )
                )
            } else if dueDate.timeIntervalSince(referenceDate) <= 2 * 24 * 60 * 60 && task.priority.rank <= TaskPriority.high.rank {
                items.append(
                    ConflictItem(
                        id: "task-soon-\(task.id.uuidString)",
                        title: localizedString("Urgent task window: %@", language: language, task.title),
                        detail: localizedString("Deadline is close and the task is still open.", language: language),
                        severity: .critical,
                        action: localizedString("Promote it into today focus.", language: language)
                    )
                )
            }
        }

        let sortedEvents = calendarItems.sorted { $0.startDate < $1.startDate }
        for (left, right) in zip(sortedEvents, sortedEvents.dropFirst()) where right.startDate < left.endDate {
            items.append(
                ConflictItem(
                    id: "calendar-overlap-\(left.id.uuidString)-\(right.id.uuidString)",
                    title: localizedString("Calendar overlap", language: language),
                    detail: localizedString("%@ overlaps with %@.", language: language, left.title, right.title),
                    severity: .high,
                    action: localizedString("Move one event or merge them into a single block.", language: language)
                )
            )
        }

        for project in projectStatuses {
            guard let deadline = project.deadline else { continue }
            if deadline.timeIntervalSince(referenceDate) <= 14 * 24 * 60 * 60 && project.readiness < 60 {
                items.append(
                    ConflictItem(
                        id: "project-risk-\(project.id.uuidString)",
                        title: localizedString("Project at risk: %@", language: language, project.title),
                        detail: localizedString("Readiness is %d%% with deadline close.", language: language, project.readiness),
                        severity: .medium,
                        action: localizedString("Focus on the next open task before adding new work.", language: language)
                    )
                )
            }
        }

        return items.sorted { lhs, rhs in
            severityRank(lhs.severity) < severityRank(rhs.severity)
        }
    }

    public static func latestAssetTotal(_ snapshots: [AssetSnapshot]) -> Decimal {
        sum(latestAssetSnapshots(snapshots).map(\.amount))
    }

    public static func latestAssetSnapshots(_ snapshots: [AssetSnapshot]) -> [AssetSnapshot] {
        let latestByKey = Dictionary(grouping: snapshots) { snapshot in
            let accountName = snapshot.account?.name ?? "unassigned"
            return "\(accountName)::\(snapshot.title)"
        }
        .compactMapValues { group in
            group.max { $0.capturedOn < $1.capturedOn }
        }

        return latestByKey.values.sorted { lhs, rhs in
            lhs.capturedOn > rhs.capturedOn
        }
    }

    public static func makeAccountBalances(accounts: [Account], ledgerEntries: [LedgerEntry]) -> [AccountBalanceSnapshot] {
        accounts.map { account in
            let balance = ledgerEntries
                .filter { $0.account?.id == account.id }
                .reduce(Decimal.zero) { partial, entry in
                    partial + (entry.direction == .income ? entry.amount : -entry.amount)
                }
            return AccountBalanceSnapshot(id: account.id, name: account.name, kind: account.kind, balance: balance)
        }
        .sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func sum(_ values: [Decimal]) -> Decimal {
        values.reduce(0, +)
    }

    private static func isNonLiquidAssetSnapshot(_ snapshot: AssetSnapshot) -> Bool {
        switch snapshot.account?.kind {
        case .some(let kind):
            return kind.isLiquid == false
        case .none:
            return true
        }
    }

    private static func severityRank(_ severity: ConflictSeverity) -> Int {
        switch severity {
        case .critical: 0
        case .high: 1
        case .medium: 2
        }
    }

    private static func localizedDateTime(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func localizedString(_ english: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        let template: String
        switch language {
        case .english:
            template = english
        case .traditionalChinese:
            template = zhHantTranslation(for: english)
        }
        return String(format: template, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }

    private static func zhHantTranslation(for english: String) -> String {
        switch english {
        case "Add the first task or time block.":
            return "先補上第一個任務或時間區塊。"
        case "Overdue task: %@":
            return "逾期任務：%@"
        case "Task should have been done by %@.":
            return "這項任務原本應該在 %@ 前完成。"
        case "Either finish it now, reschedule it, or delete it.":
            return "現在完成、重新排期，或直接刪除。"
        case "Urgent task window: %@":
            return "緊急任務視窗：%@"
        case "Deadline is close and the task is still open.":
            return "截止時間很近，任務仍未完成。"
        case "Promote it into today focus.":
            return "把它拉進今天的重點清單。"
        case "Calendar overlap":
            return "行事曆衝突"
        case "%@ overlaps with %@.":
            return "%@ 與 %@ 發生時間重疊。"
        case "Move one event or merge them into a single block.":
            return "移動其中一個事件，或合併成單一時段。"
        case "Project at risk: %@":
            return "高風險專案：%@"
        case "Readiness is %d%% with deadline close.":
            return "目前完成度為 %d%%，而且截止日已經很近。"
        case "Focus on the next open task before adding new work.":
            return "先處理下一個未完成任務，再新增其他工作。"
        default:
            return english
        }
    }
}

public enum CommandCenterEngine {
    public static func makeSnapshot(
        tasks: [TaskItem],
        calendarItems: [CalendarItem],
        projects: [Project],
        dailyPlanItems: [DailyPlanItem],
        language: AppLanguage = .english,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> CommandCenterSnapshot {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let dayStarts = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: todayStart) }
        let openTasks = tasks.filter { $0.status != .done }
        let manuallyScheduledTaskIDs = Set(dailyPlanItems.compactMap { $0.task?.id })
        let timeBlockPlansByCalendarID = Dictionary(
            dailyPlanItems
                .filter { $0.kind == .timeBlock && $0.calendarItem != nil }
                .compactMap { item -> (UUID, DailyPlanItem)? in
                    guard let calendarItem = item.calendarItem else { return nil }
                    return (calendarItem.id, item)
                },
            uniquingKeysWith: { first, _ in first }
        )
        let deadlineTaskIDsByDay = nextProjectTaskIDsByDeadlineDay(projects: projects, tasks: openTasks, dayStarts: dayStarts, calendar: calendar)
        let risks = makeDeadlineRisks(projects: projects, tasks: openTasks, dayStarts: dayStarts, language: language, calendar: calendar)

        let days = dayStarts.map { dayStart in
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
            let key = dayKey(dayStart, calendar: calendar)
            let manualFocus = dailyPlanItems
                .filter { item in
                    item.kind == .focus &&
                    calendar.isDate(item.plannedDate, inSameDayAs: dayStart) &&
                    item.task?.status != .done
                }
                .sorted {
                    if $0.sortOrder != $1.sortOrder {
                        return $0.sortOrder < $1.sortOrder
                    }
                    return $0.createdAt < $1.createdAt
                }
                .map { focusItem(for: $0, language: language) }

            let automatic = openTasks
                .filter { task in
                    guard manuallyScheduledTaskIDs.contains(task.id) == false else { return false }
                    return isAutomaticCandidate(
                        task,
                        dayStart: dayStart,
                        dayEnd: dayEnd,
                        todayStart: todayStart,
                        deadlineTaskIDs: deadlineTaskIDsByDay[key] ?? [],
                        calendar: calendar
                    )
                }
                .sorted(by: taskSort)
                .prefix(max(0, 5 - manualFocus.count))
                .map { focusItem(for: $0, source: .automatic, language: language) }

            let timeBlocks = calendarItems
                .filter { $0.startDate < dayEnd && $0.endDate >= dayStart }
                .sorted { $0.startDate < $1.startDate }
                .map { item in
                    timeBlockItem(for: item, planItem: timeBlockPlansByCalendarID[item.id], language: language)
                }

            let dayRisks = risks
                .filter { $0.deadline >= dayStart && $0.deadline < dayEnd }

            return CommandDaySnapshot(
                id: key,
                date: dayStart,
                focusItems: manualFocus + automatic,
                timeBlocks: timeBlocks,
                deadlineRisks: dayRisks
            )
        }

        return CommandCenterSnapshot(generatedAt: referenceDate, days: days, deadlineRisks: risks)
    }

    private static func focusItem(for item: DailyPlanItem, language: AppLanguage) -> CommandFocusItem {
        if let task = item.task {
            return focusItem(for: task, source: .manual, planItem: item, language: language)
        }

        return CommandFocusItem(
            id: "manual-\(item.id.uuidString)",
            title: localized("Untitled focus", language: language),
            detail: localized("Manual", language: language),
            source: .manual,
            task: nil,
            planItem: item,
            dueDate: nil,
            projectTitle: nil,
            priority: nil
        )
    }

    private static func timeBlockItem(for calendarItem: CalendarItem, planItem: DailyPlanItem?, language: AppLanguage) -> CommandTimeBlockItem {
        let source = planItem == nil ? localized("Calendar event", language: language) : localized("Task time block", language: language)
        let detailParts = [
            localizedDate(calendarItem.startDate, language: language),
            calendarItem.project?.title,
            source
        ]
        .compactMap { $0 }

        return CommandTimeBlockItem(
            id: "timeblock-\(calendarItem.id.uuidString)",
            title: calendarItem.title,
            detail: detailParts.joined(separator: " · "),
            calendarItem: calendarItem,
            planItem: planItem,
            task: planItem?.task
        )
    }

    private static func focusItem(for task: TaskItem, source: CommandPlanSource, planItem: DailyPlanItem? = nil, language: AppLanguage) -> CommandFocusItem {
        let projectTitle = task.project?.title
        let sourceText = source == .manual ? localized("Manual", language: language) : localized("Suggested", language: language)
        let detailParts = [
            projectTitle,
            task.dueDate.map { localizedDate($0, language: language) },
            sourceText
        ]
        .compactMap { $0 }

        return CommandFocusItem(
            id: "\(source.rawValue)-\(task.id.uuidString)",
            title: task.title,
            detail: detailParts.joined(separator: " · "),
            source: source,
            task: task,
            planItem: planItem,
            dueDate: task.dueDate,
            projectTitle: projectTitle,
            priority: task.priority
        )
    }

    private static func isAutomaticCandidate(
        _ task: TaskItem,
        dayStart: Date,
        dayEnd: Date,
        todayStart: Date,
        deadlineTaskIDs: Set<UUID>,
        calendar: Calendar
    ) -> Bool {
        if deadlineTaskIDs.contains(task.id) {
            return true
        }

        if let dueDate = task.dueDate {
            if dayStart == todayStart && dueDate < dayEnd {
                return true
            }
            return dueDate >= dayStart && dueDate < dayEnd
        }

        return dayStart == todayStart && task.priority.rank <= TaskPriority.high.rank
    }

    private static func nextProjectTaskIDsByDeadlineDay(projects: [Project], tasks: [TaskItem], dayStarts: [Date], calendar: Calendar) -> [String: Set<UUID>] {
        guard let firstDay = dayStarts.first, let lastDay = dayStarts.last else { return [:] }
        let lastDayEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay.addingTimeInterval(24 * 60 * 60)
        var result: [String: Set<UUID>] = [:]

        for project in projects where project.state != .done {
            guard let deadline = project.deadline, deadline >= firstDay, deadline < lastDayEnd else { continue }
            guard let nextTask = tasks
                .filter({ $0.project?.id == project.id })
                .sorted(by: taskSort)
                .first else { continue }

            let scheduledDay = max(firstDay, calendar.startOfDay(for: deadline))
            let key = dayKey(scheduledDay, calendar: calendar)
            result[key, default: []].insert(nextTask.id)
        }

        return result
    }

    private static func makeDeadlineRisks(projects: [Project], tasks: [TaskItem], dayStarts: [Date], language: AppLanguage, calendar: Calendar) -> [CommandRiskItem] {
        guard let firstDay = dayStarts.first, let lastDay = dayStarts.last else { return [] }
        let lastDayEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay.addingTimeInterval(24 * 60 * 60)

        return projects.compactMap { project in
            guard project.state != .done else { return nil }
            guard let deadline = project.deadline, deadline >= firstDay, deadline < lastDayEnd else { return nil }

            let projectTasks = tasks.filter { $0.project?.id == project.id }
            let openTasks = projectTasks.filter { $0.status != .done }
            let completed = projectTasks.count - openTasks.count
            let readiness = projectTasks.isEmpty ? 0 : Int((Double(completed) / Double(projectTasks.count)) * 100)
            guard readiness < 80 else { return nil }

            let nextTask = openTasks.sorted(by: taskSort).first
            let daysRemaining = max(0, calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: deadline)).day ?? 0)
            let severity: ConflictSeverity = daysRemaining <= 2 || readiness < 40 ? .high : .medium
            let detail = localized("Readiness %d%% · %d open tasks", language: language, readiness, openTasks.count)

            return CommandRiskItem(
                id: "deadline-\(project.id.uuidString)",
                title: project.title,
                detail: detail,
                deadline: deadline,
                severity: severity,
                project: project,
                nextTask: nextTask
            )
        }
        .sorted {
            if $0.severity != $1.severity {
                return severityRank($0.severity) < severityRank($1.severity)
            }
            return $0.deadline < $1.deadline
        }
    }

    private static func taskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.priority.rank != rhs.priority.rank {
            return lhs.priority.rank < rhs.priority.rank
        }
        return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
    }

    private static func severityRank(_ severity: ConflictSeverity) -> Int {
        switch severity {
        case .critical: 0
        case .high: 1
        case .medium: 2
        }
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func localizedDate(_ date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func localized(_ english: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        let template: String
        switch (english, language) {
        case ("Manual", .traditionalChinese):
            template = "手動"
        case ("Suggested", .traditionalChinese):
            template = "建議"
        case ("Untitled focus", .traditionalChinese):
            template = "未命名焦點"
        case ("Calendar event", .traditionalChinese):
            template = "行程事件"
        case ("Task time block", .traditionalChinese):
            template = "任務時間區塊"
        case ("Readiness %d%% · %d open tasks", .traditionalChinese):
            template = "就緒度 %d%% · %d 個未完成任務"
        default:
            template = english
        }
        return String(format: template, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }
}

public enum ScheduleQualityEngine {
    public static func makeSnapshot(
        tasks: [TaskItem],
        calendarItems: [CalendarItem],
        projects: [Project],
        dailyPlanItems: [DailyPlanItem],
        language: AppLanguage = .english,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> ScheduleQualitySnapshot {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let dayStarts = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: todayStart) }
        let lastDayEnd = dayStarts.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? todayStart.addingTimeInterval(7 * 24 * 60 * 60)

        let command = CommandCenterEngine.makeSnapshot(
            tasks: tasks,
            calendarItems: calendarItems,
            projects: projects,
            dailyPlanItems: dailyPlanItems,
            language: language,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let focusPlansInWindow = dailyPlanItems.filter { item in
            item.kind == .focus &&
            item.plannedDate >= todayStart &&
            item.plannedDate < lastDayEnd &&
            item.task?.status != .done
        }
        let timeBlockTaskKeys = Set(
            dailyPlanItems.compactMap { item -> String? in
                guard item.kind == .timeBlock,
                      item.plannedDate >= todayStart,
                      item.plannedDate < lastDayEnd,
                      let task = item.task,
                      task.status != .done
                else { return nil }
                return taskDayKey(taskID: task.id, date: item.plannedDate, calendar: calendar)
            }
        )
        let repeatedTasks = repeatedFocusTasks(focusPlansInWindow, calendar: calendar)
        let repeatedTaskIDs = Set(repeatedTasks.map { $0.task.id })
        let needsTimeBlockItems = command.days.flatMap { day in
            day.focusItems.compactMap { item -> ScheduleNeedsTimeBlockItem? in
                guard let task = item.task,
                      task.status != .done,
                      let reason = needsTimeBlockReason(for: task, lastDayEnd: lastDayEnd)
                else { return nil }

                let key = taskDayKey(taskID: task.id, date: day.date, calendar: calendar)
                guard timeBlockTaskKeys.contains(key) == false else { return nil }

                return ScheduleNeedsTimeBlockItem(
                    task: task,
                    planItem: item.planItem,
                    plannedDate: day.date,
                    reason: reason,
                    calendar: calendar
                )
            }
        }
        let needsTimeBlockIDsByDay = Dictionary(grouping: needsTimeBlockItems, by: { dayKey($0.plannedDate, calendar: calendar) })

        let days = command.days.map { day in
            let repeatedCount = day.focusItems.filter { item in
                item.task.map { repeatedTaskIDs.contains($0.id) } ?? false
            }.count
            let key = dayKey(day.date, calendar: calendar)
            return ScheduleQualityDaySnapshot(
                id: key,
                date: day.date,
                repeatedFocusCount: repeatedCount,
                needsTimeBlockCount: needsTimeBlockIDsByDay[key]?.count ?? 0,
                timeBlockCount: day.timeBlocks.count
            )
        }

        return ScheduleQualitySnapshot(
            generatedAt: referenceDate,
            days: days,
            repeatedTasks: repeatedTasks,
            needsTimeBlockItems: needsTimeBlockItems
        )
    }

    private static func repeatedFocusTasks(_ focusPlans: [DailyPlanItem], calendar: Calendar) -> [ScheduleRepeatedTask] {
        let grouped = Dictionary(grouping: focusPlans) { item in
            item.task?.id
        }

        return grouped.compactMap { taskID, items -> ScheduleRepeatedTask? in
            guard taskID != nil, let task = items.first?.task else { return nil }
            let dates = Array(Set(items.map { calendar.startOfDay(for: $0.plannedDate) })).sorted()
            guard dates.count > 1 else { return nil }
            let sortedItems = items.sorted {
                if $0.plannedDate != $1.plannedDate {
                    return $0.plannedDate < $1.plannedDate
                }
                return $0.sortOrder < $1.sortOrder
            }
            return ScheduleRepeatedTask(task: task, scheduledDates: dates, planItems: sortedItems)
        }
        .sorted {
            ($0.scheduledDates.first ?? .distantFuture) < ($1.scheduledDates.first ?? .distantFuture)
        }
    }

    private static func needsTimeBlockReason(for task: TaskItem, lastDayEnd: Date) -> ScheduleNeedsTimeBlockReason? {
        if task.priority.rank <= TaskPriority.high.rank {
            return .highPriority
        }
        if let dueDate = task.dueDate, dueDate < lastDayEnd {
            return .dueSoon
        }
        if let project = task.project,
           project.state != .done,
           let deadline = project.deadline,
           deadline < lastDayEnd {
            return .projectDeadlineSoon
        }
        return nil
    }

    private static func taskDayKey(taskID: UUID, date: Date, calendar: Calendar) -> String {
        "\(dayKey(date, calendar: calendar))-\(taskID.uuidString)"
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

public enum WeekPlanEngine {
    public static let maxFocusPerDay = 3

    public static func makeDraft(
        tasks: [TaskItem],
        calendarItems: [CalendarItem],
        projects: [Project],
        dailyPlanItems: [DailyPlanItem],
        language: AppLanguage = .english,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> WeekPlanDraft {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let dayStarts = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: todayStart) }
        let alreadyFocusedTaskIDsByDay = scheduledTaskIDsByDay(dailyPlanItems: dailyPlanItems, kind: .focus, dayStarts: dayStarts, calendar: calendar)
        let alreadyFocusedTaskIDsInWindow = Set(alreadyFocusedTaskIDsByDay.values.flatMap { $0 })
        let openTasks = tasks
            .filter { $0.status != .done }
            .sorted { weightedTaskSort($0, $1, projects: projects, referenceDate: referenceDate, calendar: calendar) }

        var selectedTaskIDs = Set<UUID>()
        var recentLineUseCount: [WeekPlanLine: Int] = [:]

        let days = dayStarts.map { dayStart in
            let key = dayKey(dayStart, calendar: calendar)
            let alreadyFocused = alreadyFocusedTaskIDsInWindow.union(alreadyFocusedTaskIDsByDay[key] ?? [])
            var dayItems: [WeekPlanDraftItem] = []
            var usedLinesForDay = Set<WeekPlanLine>()

            while dayItems.count < maxFocusPerDay {
                let candidate = chooseCandidate(
                    from: openTasks,
                    dayStart: dayStart,
                    selectedTaskIDs: selectedTaskIDs,
                    alreadyFocusedTaskIDs: alreadyFocused,
                    usedLinesForDay: usedLinesForDay,
                    recentLineUseCount: recentLineUseCount,
                    projects: projects,
                    referenceDate: referenceDate,
                    calendar: calendar
                )

                guard let task = candidate else { break }
                let line = classify(task)
                let slot = timeSlot(for: dayStart, index: dayItems.count, calendar: calendar)
                let conflict = slot.flatMap { conflictItem(overlapping: $0, calendarItems: calendarItems) }
                let reason = reason(for: task, line: line, dayStart: dayStart, projects: projects, language: language, calendar: calendar)

                dayItems.append(
                    WeekPlanDraftItem(
                        id: "\(key)-\(task.id.uuidString)",
                        task: task,
                        line: line,
                        reason: reason,
                        plannedDate: dayStart,
                        suggestedStart: slot?.start,
                        suggestedEnd: slot?.end,
                        timeBlockConflict: conflict != nil,
                        conflictTitle: conflict?.title
                    )
                )
                selectedTaskIDs.insert(task.id)
                usedLinesForDay.insert(line)
                recentLineUseCount[line, default: 0] += 1
            }

            return WeekPlanDayDraft(id: key, date: dayStart, items: dayItems)
        }

        return WeekPlanDraft(generatedAt: referenceDate, days: days)
    }

    public static func suggestedTimeSlot(on dayStart: Date, index: Int, calendar: Calendar = .current) -> DateInterval? {
        timeSlot(for: dayStart, index: index, calendar: calendar).map { DateInterval(start: $0.start, end: $0.end) }
    }

    public static func moveDraftItem(
        _ draft: WeekPlanDraft,
        itemID: String,
        to targetDate: Date,
        calendarItems: [CalendarItem],
        calendar: Calendar = .current
    ) -> WeekPlanDraft {
        let targetDay = calendar.startOfDay(for: targetDate)
        guard let movingItem = draft.days.flatMap(\.items).first(where: { $0.id == itemID }),
              draft.days.contains(where: { calendar.isDate($0.date, inSameDayAs: targetDay) })
        else {
            return draft
        }

        let targetItemCount = draft.days
            .first { calendar.isDate($0.date, inSameDayAs: targetDay) }?
            .items
            .filter { $0.id != itemID }
            .count ?? 0
        let editedItem = editedDraftItem(
            movingItem,
            plannedDate: targetDay,
            slotIndex: targetItemCount,
            calendarItems: calendarItems,
            calendar: calendar
        )
        let editedDays = draft.days.map { day in
            var items = day.items.filter { $0.id != itemID }
            if calendar.isDate(day.date, inSameDayAs: targetDay) {
                items.append(editedItem)
            }
            return WeekPlanDayDraft(id: day.id, date: day.date, items: items)
        }

        return WeekPlanDraft(id: draft.id, generatedAt: draft.generatedAt, days: editedDays)
    }

    public static func removeDraftItem(_ draft: WeekPlanDraft, itemID: String) -> WeekPlanDraft {
        let editedDays = draft.days.map { day in
            WeekPlanDayDraft(
                id: day.id,
                date: day.date,
                items: day.items.filter { $0.id != itemID }
            )
        }
        return WeekPlanDraft(id: draft.id, generatedAt: draft.generatedAt, days: editedDays)
    }

    public static func updateDraftItemTimeSlot(
        _ draft: WeekPlanDraft,
        itemID: String,
        slotIndex: Int,
        calendarItems: [CalendarItem],
        calendar: Calendar = .current
    ) -> WeekPlanDraft {
        let editedDays = draft.days.map { day in
            let editedItems = day.items.map { item in
                guard item.id == itemID else { return item }
                return editedDraftItem(
                    item,
                    plannedDate: item.plannedDate,
                    slotIndex: slotIndex,
                    calendarItems: calendarItems,
                    calendar: calendar
                )
            }
            return WeekPlanDayDraft(id: day.id, date: day.date, items: editedItems)
        }
        return WeekPlanDraft(id: draft.id, generatedAt: draft.generatedAt, days: editedDays)
    }

    private static func chooseCandidate(
        from tasks: [TaskItem],
        dayStart: Date,
        selectedTaskIDs: Set<UUID>,
        alreadyFocusedTaskIDs: Set<UUID>,
        usedLinesForDay: Set<WeekPlanLine>,
        recentLineUseCount: [WeekPlanLine: Int],
        projects: [Project],
        referenceDate: Date,
        calendar: Calendar
    ) -> TaskItem? {
        let candidates = tasks.filter { task in
            selectedTaskIDs.contains(task.id) == false &&
            alreadyFocusedTaskIDs.contains(task.id) == false
        }

        guard candidates.isEmpty == false else { return nil }

        let freshLineCandidates = candidates.filter { usedLinesForDay.contains(classify($0)) == false }
        let pool = freshLineCandidates.isEmpty ? candidates : freshLineCandidates

        return pool.sorted {
            let leftLine = classify($0)
            let rightLine = classify($1)
            let leftLineCount = recentLineUseCount[leftLine, default: 0]
            let rightLineCount = recentLineUseCount[rightLine, default: 0]
            if leftLineCount != rightLineCount {
                return leftLineCount < rightLineCount
            }

            let leftScore = urgencyScore($0, dayStart: dayStart, projects: projects, referenceDate: referenceDate, calendar: calendar)
            let rightScore = urgencyScore($1, dayStart: dayStart, projects: projects, referenceDate: referenceDate, calendar: calendar)
            if leftScore != rightScore {
                return leftScore > rightScore
            }

            if $0.priority.rank != $1.priority.rank {
                return $0.priority.rank < $1.priority.rank
            }

            return ($0.dueDate ?? $0.project?.deadline ?? .distantFuture) < ($1.dueDate ?? $1.project?.deadline ?? .distantFuture)
        }
        .first
    }

    private static func urgencyScore(
        _ task: TaskItem,
        dayStart: Date,
        projects: [Project],
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        var score = 100 - (task.priority.rank * 10)

        if let dueDate = task.dueDate {
            if dueDate < referenceDate {
                score += 100
            } else if dueDate >= dayStart && dueDate < dayEnd {
                score += 80
            } else {
                let daysUntilDue = max(0, calendar.dateComponents([.day], from: dayStart, to: calendar.startOfDay(for: dueDate)).day ?? 30)
                score += max(0, 45 - (daysUntilDue * 6))
            }
        }

        if let deadline = task.project?.deadline {
            let daysUntilDeadline = max(0, calendar.dateComponents([.day], from: dayStart, to: calendar.startOfDay(for: deadline)).day ?? 30)
            if deadline < dayEnd {
                score += 50
            } else {
                score += max(0, 35 - (daysUntilDeadline * 5))
            }
        }

        if projects.contains(where: { $0.id == task.project?.id && $0.state == .done }) {
            score -= 200
        }

        return score
    }

    private static func weightedTaskSort(_ lhs: TaskItem, _ rhs: TaskItem, projects: [Project], referenceDate: Date, calendar: Calendar) -> Bool {
        let leftScore = urgencyScore(lhs, dayStart: calendar.startOfDay(for: referenceDate), projects: projects, referenceDate: referenceDate, calendar: calendar)
        let rightScore = urgencyScore(rhs, dayStart: calendar.startOfDay(for: referenceDate), projects: projects, referenceDate: referenceDate, calendar: calendar)
        if leftScore != rightScore {
            return leftScore > rightScore
        }
        if lhs.priority.rank != rhs.priority.rank {
            return lhs.priority.rank < rhs.priority.rank
        }
        return (lhs.dueDate ?? lhs.project?.deadline ?? .distantFuture) < (rhs.dueDate ?? rhs.project?.deadline ?? .distantFuture)
    }

    private static func scheduledTaskIDsByDay(dailyPlanItems: [DailyPlanItem], kind: DailyPlanItemKind, dayStarts: [Date], calendar: Calendar) -> [String: Set<UUID>] {
        var result: [String: Set<UUID>] = [:]
        for dayStart in dayStarts {
            let key = dayKey(dayStart, calendar: calendar)
            let ids = dailyPlanItems
                .filter { item in
                    item.kind == kind &&
                    calendar.isDate(item.plannedDate, inSameDayAs: dayStart) &&
                    item.task?.status != .done
                }
                .compactMap { $0.task?.id }
            result[key] = Set(ids)
        }
        return result
    }

    private static func classify(_ task: TaskItem) -> WeekPlanLine {
        let haystack = [task.title, task.note, task.project?.title, task.project?.summary]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if containsAny(haystack, ["product challenge", "solve", "Research Fair", "科學獎", "competition", "競賽", "比賽"]) {
            return .competition
        }
        if containsAny(haystack, ["賺錢", "接案", "Part-time", "收入", "cash", "earning", "income", "gig"]) {
            return .earning
        }
        if containsAny(haystack, ["Demo Destination", "demoTrip", "travel", "trip", "旅遊", "行李"]) {
            return .travel
        }
        if containsAny(haystack, ["2330", "投資", "資產", "investment", "asset", "etf"]) {
            return .investment
        }
        if containsAny(haystack, ["casi", "seasonal training", "ski", "snow", "Seasonal Work"]) {
            return .snow
        }
        if containsAny(haystack, ["學術", "研究", "升學", "academic", "research", "university"]) {
            return .academic
        }
        return .general
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0.lowercased()) }
    }

    private static func reason(for task: TaskItem, line: WeekPlanLine, dayStart: Date, projects: [Project], language: AppLanguage, calendar: Calendar) -> String {
        if let dueDate = task.dueDate {
            if calendar.isDate(dueDate, inSameDayAs: dayStart) {
                return localized("Due today", language: language)
            }
            if dueDate < dayStart {
                return localized("Overdue", language: language)
            }
            let days = max(0, calendar.dateComponents([.day], from: dayStart, to: calendar.startOfDay(for: dueDate)).day ?? 0)
            if days <= 3 {
                return localized("Due in %d days", language: language, days)
            }
        }

        if let deadline = task.project?.deadline {
            let days = max(0, calendar.dateComponents([.day], from: dayStart, to: calendar.startOfDay(for: deadline)).day ?? 0)
            if days <= 7 {
                return localized("Project deadline in %d days", language: language, days)
            }
        }

        if projects.contains(where: { $0.id == task.project?.id }) {
            return localized("Balanced weekly progress", language: language)
        }

        return localized("Open task", language: language)
    }

    private static func editedDraftItem(
        _ item: WeekPlanDraftItem,
        plannedDate: Date,
        slotIndex: Int,
        calendarItems: [CalendarItem],
        calendar: Calendar
    ) -> WeekPlanDraftItem {
        let slot = timeSlot(for: plannedDate, index: slotIndex, calendar: calendar)
        let conflict = slot.flatMap { conflictItem(overlapping: $0, calendarItems: calendarItems) }
        return WeekPlanDraftItem(
            id: item.id,
            task: item.task,
            line: item.line,
            reason: item.reason,
            plannedDate: calendar.startOfDay(for: plannedDate),
            suggestedStart: slot?.start,
            suggestedEnd: slot?.end,
            timeBlockConflict: conflict != nil,
            conflictTitle: conflict?.title
        )
    }

    private static func timeSlot(for dayStart: Date, index: Int, calendar: Calendar) -> (start: Date, end: Date)? {
        let starts = [(19, 0), (20, 10), (21, 20)]
        guard index >= 0, index < starts.count else { return nil }
        let date = calendar.dateComponents([.year, .month, .day], from: dayStart)
        let (hour, minute) = starts[index]
        guard let start = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: date.year,
            month: date.month,
            day: date.day,
            hour: hour,
            minute: minute
        )) else {
            return nil
        }
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(60 * 60)
        return (start, end)
    }

    private static func conflictItem(overlapping slot: (start: Date, end: Date), calendarItems: [CalendarItem]) -> CalendarItem? {
        calendarItems.first { item in
            item.startDate < slot.end && item.endDate > slot.start
        }
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func localized(_ english: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        let template: String
        switch (english, language) {
        case ("Due today", .traditionalChinese):
            template = "今天到期"
        case ("Overdue", .traditionalChinese):
            template = "已逾期"
        case ("Due in %d days", .traditionalChinese):
            template = "%d 天後到期"
        case ("Project deadline in %d days", .traditionalChinese):
            template = "專案 %d 天後截止"
        case ("Balanced weekly progress", .traditionalChinese):
            template = "本週均衡推進"
        case ("Open task", .traditionalChinese):
            template = "未完成任務"
        default:
            template = english
        }
        return String(format: template, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }
}
