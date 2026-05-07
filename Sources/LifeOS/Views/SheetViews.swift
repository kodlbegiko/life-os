import SwiftData
import SwiftUI
import LifeOSCore

struct QuickEntrySheetContainer: View {
    let sheet: LifeOSAppState.QuickSheet

    var body: some View {
        switch sheet {
        case .ledger:
            LedgerEntryFormSheet()
        case .planned:
            PlannedEntryFormSheet()
        case .task:
            TaskFormSheet()
        case .calendar:
            CalendarFormSheet()
        }
    }
}

struct LedgerEntryFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\Account.createdAt, order: .forward)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\LifeOSCore.Category.createdAt, order: .forward)]) private var categories: [LifeOSCore.Category]
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .forward)]) private var projects: [Project]

    @State private var title = ""
    @State private var direction: EntryDirection = .expense
    @State private var amountText = ""
    @State private var occurredOn = Date.now
    @State private var note = ""
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var projectID: UUID?

    var body: some View {
        entrySheetLayout(title: l10n.text("New Ledger Entry"), saveTitle: l10n.text("Save Ledger Entry"), saveAction: save, disabled: invalidAmount == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            Picker(l10n.text("Direction"), selection: $direction) {
                ForEach(EntryDirection.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option)
                }
            }
            .accessibilityIdentifier("sheet-ledger-direction")

            TextField(l10n.text("Title"), text: $title)
                .accessibilityIdentifier("sheet-ledger-title")
            TextField(l10n.text("Amount"), text: $amountText)
                .accessibilityIdentifier("sheet-ledger-amount")
            DatePicker(l10n.text("Occurred On"), selection: $occurredOn, displayedComponents: [.date])
                .accessibilityIdentifier("sheet-ledger-date")
            accountPicker(selection: $accountID, accounts: accounts, l10n: l10n)
            categoryPicker(selection: $categoryID, categories: categories.filter { $0.scope == (direction == .income ? .income : .expense) || $0.scope == .expense }, l10n: l10n)
            projectPicker(selection: $projectID, projects: projects, l10n: l10n)
            TextField(l10n.text("Note"), text: $note, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("sheet-ledger-note")
        }
    }

    private var invalidAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
    }

    private func save() {
        guard let amount = invalidAmount else { return }
        let repository = LifeOSRepository(context: modelContext)
        _ = try? repository.createLedgerEntry(
            title: title,
            direction: direction,
            amount: amount,
            occurredOn: occurredOn,
            account: accounts.first(where: { $0.id == accountID }),
            category: categories.first(where: { $0.id == categoryID }),
            project: projects.first(where: { $0.id == projectID }),
            note: note
        )
        dismiss()
    }
}

struct PlannedEntryFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\Account.createdAt, order: .forward)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\LifeOSCore.Category.createdAt, order: .forward)]) private var categories: [LifeOSCore.Category]
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .forward)]) private var projects: [Project]

    @State private var title = ""
    @State private var direction: EntryDirection = .expense
    @State private var amountText = ""
    @State private var dueOn = Date.now
    @State private var note = ""
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var projectID: UUID?

    var body: some View {
        entrySheetLayout(title: l10n.text("New Planned Entry"), saveTitle: l10n.text("Save Planned Entry"), saveAction: save, disabled: invalidAmount == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            Picker(l10n.text("Direction"), selection: $direction) {
                ForEach(EntryDirection.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option)
                }
            }
            .accessibilityIdentifier("sheet-planned-direction")

            TextField(l10n.text("Title"), text: $title)
                .accessibilityIdentifier("sheet-planned-title")
            TextField(l10n.text("Amount"), text: $amountText)
                .accessibilityIdentifier("sheet-planned-amount")
            DatePicker(l10n.text("Due On"), selection: $dueOn, displayedComponents: [.date])
                .accessibilityIdentifier("sheet-planned-date")
            accountPicker(selection: $accountID, accounts: accounts, l10n: l10n)
            categoryPicker(selection: $categoryID, categories: categories.filter { $0.scope == (direction == .income ? .income : .expense) || $0.scope == .expense }, l10n: l10n)
            projectPicker(selection: $projectID, projects: projects, l10n: l10n)
            TextField(l10n.text("Note"), text: $note, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("sheet-planned-note")
        }
    }

    private var invalidAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
    }

    private func save() {
        guard let amount = invalidAmount else { return }
        let repository = LifeOSRepository(context: modelContext)
        _ = try? repository.createPlannedEntry(
            title: title,
            direction: direction,
            amount: amount,
            dueOn: dueOn,
            account: accounts.first(where: { $0.id == accountID }),
            category: categories.first(where: { $0.id == categoryID }),
            project: projects.first(where: { $0.id == projectID }),
            note: note
        )
        dismiss()
    }
}

struct TaskFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .forward)]) private var projects: [Project]

    @State private var title = ""
    @State private var dueDate = Date.now
    @State private var hasDueDate = true
    @State private var priority: TaskPriority = .high
    @State private var note = ""
    @State private var projectID: UUID?

    var body: some View {
        entrySheetLayout(title: l10n.text("New Task"), saveTitle: l10n.text("Save Task"), saveAction: save, disabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            TextField(l10n.text("Title"), text: $title)
                .accessibilityIdentifier("sheet-task-title")
            Toggle(l10n.text("Has Due Date"), isOn: $hasDueDate)
                .accessibilityIdentifier("sheet-task-has-due")
            if hasDueDate {
                DatePicker(l10n.text("Due Date"), selection: $dueDate)
                    .accessibilityIdentifier("sheet-task-date")
            }
            Picker(l10n.text("Priority"), selection: $priority) {
                ForEach(TaskPriority.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option)
                }
            }
            .accessibilityIdentifier("sheet-task-priority")
            projectPicker(selection: $projectID, projects: projects, l10n: l10n)
            TextField(l10n.text("Note"), text: $note, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("sheet-task-note")
        }
    }

    private func save() {
        let repository = LifeOSRepository(context: modelContext)
        _ = try? repository.createTask(
            title: title,
            dueDate: hasDueDate ? dueDate : nil,
            priority: priority,
            project: projects.first(where: { $0.id == projectID }),
            note: note
        )
        dismiss()
    }
}

struct TaskScheduleSheet: View {
    let task: TaskItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocalizationStore.self) private var l10n

    @State private var kind: DailyPlanItemKind
    @State private var plannedDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var note = ""

    init(task: TaskItem, initialKind: DailyPlanItemKind) {
        self.task = task
        let baseDate = Date.now
        let defaultStart = Calendar.current.date(bySetting: .minute, value: 0, of: Date.now) ?? Date.now
        _kind = State(initialValue: initialKind)
        _plannedDate = State(initialValue: baseDate)
        _startTime = State(initialValue: defaultStart)
        _endTime = State(initialValue: defaultStart.addingTimeInterval(60 * 60))
    }

    var body: some View {
        entrySheetLayout(
            title: l10n.text("Schedule Task"),
            saveTitle: l10n.text("Save Schedule"),
            saveAction: save,
            disabled: kind == .timeBlock && combinedEnd <= combinedStart
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.headline)
                Text(task.project?.title ?? l10n.text("No linked project"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("sheet-schedule-task-summary")

            Picker(l10n.text("Schedule Mode"), selection: $kind) {
                ForEach(DailyPlanItemKind.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option)
                }
            }
            .accessibilityIdentifier("sheet-schedule-kind")

            DatePicker(l10n.text("Planned Date"), selection: $plannedDate, displayedComponents: [.date])
                .accessibilityIdentifier("sheet-schedule-date")

            if kind == .timeBlock {
                DatePicker(l10n.text("Start Time"), selection: $startTime, displayedComponents: [.hourAndMinute])
                    .accessibilityIdentifier("sheet-schedule-start-time")
                DatePicker(l10n.text("End Time"), selection: $endTime, displayedComponents: [.hourAndMinute])
                    .accessibilityIdentifier("sheet-schedule-end-time")
            }

            TextField(l10n.text("Note"), text: $note, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("sheet-schedule-note")
        }
    }

    private var combinedStart: Date {
        combined(date: plannedDate, time: startTime)
    }

    private var combinedEnd: Date {
        combined(date: plannedDate, time: endTime)
    }

    private func combined(date: Date, time: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: dateComponents.year,
            month: dateComponents.month,
            day: dateComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute
        )) ?? date
    }

    private func save() {
        let repository = LifeOSRepository(context: modelContext)
        _ = try? repository.scheduleTask(
            task,
            kind: kind,
            plannedDate: plannedDate,
            startDate: kind == .timeBlock ? combinedStart : nil,
            endDate: kind == .timeBlock ? combinedEnd : nil,
            note: note
        )
        dismiss()
    }
}

struct CalendarFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .forward)]) private var projects: [Project]

    @State private var title = ""
    @State private var startDate = Date.now
    @State private var endDate = Date.now.addingTimeInterval(60 * 60)
    @State private var allDay = false
    @State private var location = ""
    @State private var note = ""
    @State private var projectID: UUID?

    var body: some View {
        entrySheetLayout(title: l10n.text("New Calendar Item"), saveTitle: l10n.text("Save Calendar Item"), saveAction: save, disabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            TextField(l10n.text("Title"), text: $title)
                .accessibilityIdentifier("sheet-calendar-title")
            DatePicker(l10n.text("Start"), selection: $startDate)
                .accessibilityIdentifier("sheet-calendar-start")
            DatePicker(l10n.text("End"), selection: $endDate)
                .accessibilityIdentifier("sheet-calendar-end")
            Toggle(l10n.text("All Day"), isOn: $allDay)
                .accessibilityIdentifier("sheet-calendar-all-day")
            TextField(l10n.text("Location"), text: $location)
                .accessibilityIdentifier("sheet-calendar-location")
            projectPicker(selection: $projectID, projects: projects, l10n: l10n)
            TextField(l10n.text("Note"), text: $note, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("sheet-calendar-note")
        }
    }

    private func save() {
        let repository = LifeOSRepository(context: modelContext)
        _ = try? repository.createCalendarItem(
            title: title,
            startDate: startDate,
            endDate: max(endDate, startDate),
            allDay: allDay,
            location: location,
            note: note,
            project: projects.first(where: { $0.id == projectID })
        )
        dismiss()
    }
}

struct AssetSnapshotFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\Account.createdAt, order: .forward)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\LifeOSCore.Category.createdAt, order: .forward)]) private var categories: [LifeOSCore.Category]

    @State private var title = ""
    @State private var amountText = ""
    @State private var capturedOn = Date.now
    @State private var note = ""
    @State private var quoteSymbol = ""
    @State private var unitsText = ""
    @State private var costBasisText = ""
    @State private var accountID: UUID?
    @State private var categoryID: UUID?

    var body: some View {
        entrySheetLayout(title: l10n.text("New Asset Snapshot"), saveTitle: l10n.text("Save Asset Snapshot"), saveAction: save, disabled: invalidAmount == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            TextField(l10n.text("Title"), text: $title)
                .accessibilityIdentifier("sheet-asset-title")
            TextField(l10n.text("Reference Amount"), text: $amountText)
                .accessibilityIdentifier("sheet-asset-amount")
            DatePicker(l10n.text("Captured On"), selection: $capturedOn, displayedComponents: [.date])
                .accessibilityIdentifier("sheet-asset-date")
            accountPicker(selection: $accountID, accounts: accounts, l10n: l10n)
            categoryPicker(selection: $categoryID, categories: categories.filter { $0.scope == .asset }, l10n: l10n)
            Divider()
            Text(l10n.text("Taiwan Live Quote"))
                .font(.headline)
            TextField(l10n.text("Ticker (example: 2330)"), text: $quoteSymbol)
                .accessibilityIdentifier("sheet-asset-symbol")
            TextField(l10n.text("Units / Shares"), text: $unitsText)
                .accessibilityIdentifier("sheet-asset-units")
            TextField(l10n.text("Cost Basis (optional)"), text: $costBasisText)
                .accessibilityIdentifier("sheet-asset-cost-basis")
            TextField(l10n.text("Note"), text: $note, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("sheet-asset-note")
        }
    }

    private var invalidAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
    }

    private func save() {
        guard let amount = invalidAmount else { return }
        let repository = LifeOSRepository(context: modelContext)
        _ = try? repository.createAssetSnapshot(
            title: title,
            amount: amount,
            capturedOn: capturedOn,
            account: accounts.first(where: { $0.id == accountID }),
            category: categories.first(where: { $0.id == categoryID }),
            quoteSymbol: normalizedQuoteSymbol,
            units: decimalOrNil(from: unitsText),
            costBasis: decimalOrNil(from: costBasisText),
            note: note
        )
        dismiss()
    }

    private func decimalOrNil(from raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard trimmed.isEmpty == false else { return nil }
        return Decimal(string: trimmed)
    }

    private var normalizedQuoteSymbol: String? {
        let trimmed = quoteSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct GoalFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocalizationStore.self) private var l10n

    @State private var title = ""
    @State private var summary = ""
    @State private var state: GoalState = .active
    @State private var hasTargetDate = true
    @State private var targetDate = Date.now

    var body: some View {
        entrySheetLayout(title: l10n.text("New Goal"), saveTitle: l10n.text("Save Goal"), saveAction: save, disabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            TextField(l10n.text("Title"), text: $title)
                .accessibilityIdentifier("sheet-goal-title")
            TextField(l10n.text("Summary"), text: $summary, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("sheet-goal-summary")
            Picker(l10n.text("State"), selection: $state) {
                ForEach(GoalState.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option)
                }
            }
            .accessibilityIdentifier("sheet-goal-state")
            Toggle(l10n.text("Has Target Date"), isOn: $hasTargetDate)
                .accessibilityIdentifier("sheet-goal-has-target-date")
            if hasTargetDate {
                DatePicker(l10n.text("Target Date"), selection: $targetDate, displayedComponents: [.date])
                    .accessibilityIdentifier("sheet-goal-target-date")
            }
        }
    }

    private func save() {
        let repository = LifeOSRepository(context: modelContext)
        _ = try? repository.createGoal(title: title, summary: summary, targetDate: hasTargetDate ? targetDate : nil, state: state)
        dismiss()
    }
}

struct ProjectFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\Goal.createdAt, order: .forward)]) private var goals: [Goal]

    @State private var title = ""
    @State private var summary = ""
    @State private var state: ProjectState = .active
    @State private var hasDeadline = true
    @State private var deadline = Date.now
    @State private var note = ""
    @State private var goalID: UUID?

    var body: some View {
        entrySheetLayout(title: l10n.text("New Project"), saveTitle: l10n.text("Save Project"), saveAction: save, disabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            TextField(l10n.text("Title"), text: $title)
                .accessibilityIdentifier("sheet-project-title")
            TextField(l10n.text("Summary"), text: $summary, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("sheet-project-summary")
            Picker(l10n.text("State"), selection: $state) {
                ForEach(ProjectState.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option)
                }
            }
            .accessibilityIdentifier("sheet-project-state")
            goalPicker(selection: $goalID, goals: goals, l10n: l10n)
            Toggle(l10n.text("Has Deadline"), isOn: $hasDeadline)
                .accessibilityIdentifier("sheet-project-has-deadline")
            if hasDeadline {
                DatePicker(l10n.text("Deadline"), selection: $deadline, displayedComponents: [.date])
                    .accessibilityIdentifier("sheet-project-deadline")
            }
            TextField(l10n.text("Note"), text: $note, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("sheet-project-note")
        }
    }

    private func save() {
        let repository = LifeOSRepository(context: modelContext)
        _ = try? repository.createProject(
            title: title,
            summary: summary,
            deadline: hasDeadline ? deadline : nil,
            goal: goals.first(where: { $0.id == goalID }),
            state: state,
            note: note
        )
        dismiss()
    }
}

struct AccountFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocalizationStore.self) private var l10n

    @State private var name = ""
    @State private var kind: AccountKind = .cash
    @State private var note = ""

    var body: some View {
        entrySheetLayout(title: l10n.text("New Account"), saveTitle: l10n.text("Save Account"), saveAction: save, disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            TextField(l10n.text("Name"), text: $name)
                .accessibilityIdentifier("sheet-account-name")
            Picker(l10n.text("Kind"), selection: $kind) {
                ForEach(AccountKind.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option)
                }
            }
            TextField(l10n.text("Note"), text: $note, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private func save() {
        let repository = LifeOSRepository(context: modelContext)
        _ = try? repository.createAccount(name: name, kind: kind, note: note)
        dismiss()
    }
}

struct CategoryFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocalizationStore.self) private var l10n

    @State private var name = ""
    @State private var scope: CategoryScope = .expense
    @State private var note = ""

    var body: some View {
        entrySheetLayout(title: l10n.text("New Category"), saveTitle: l10n.text("Save Category"), saveAction: save, disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            TextField(l10n.text("Name"), text: $name)
                .accessibilityIdentifier("sheet-category-name")
            Picker(l10n.text("Scope"), selection: $scope) {
                ForEach(CategoryScope.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option)
                }
            }
            TextField(l10n.text("Note"), text: $note, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private func save() {
        let repository = LifeOSRepository(context: modelContext)
        _ = try? repository.createCategory(name: name, scope: scope, note: note)
        dismiss()
    }
}

@MainActor
private func entrySheetLayout<Content: View>(title: String, saveTitle: String, saveAction: @escaping () -> Void, disabled: Bool, @ViewBuilder content: () -> Content) -> some View {
    EntrySheetScaffold(title: title, saveTitle: saveTitle, saveAction: saveAction, disabled: disabled) {
        content()
    }
}

@MainActor
private func accountPicker(selection: Binding<UUID?>, accounts: [Account], l10n: LocalizationStore) -> some View {
    Picker(l10n.text("Account"), selection: selection) {
        Text(l10n.text("None")).tag(UUID?.none)
        ForEach(accounts, id: \.id) { account in
            Text(account.name).tag(Optional(account.id))
        }
    }
    .accessibilityIdentifier("picker-account")
}

@MainActor
private func categoryPicker(selection: Binding<UUID?>, categories: [LifeOSCore.Category], l10n: LocalizationStore) -> some View {
    Picker(l10n.text("Category"), selection: selection) {
        Text(l10n.text("None")).tag(UUID?.none)
        ForEach(categories, id: \.id) { category in
            Text(category.name).tag(Optional(category.id))
        }
    }
    .accessibilityIdentifier("picker-category")
}

@MainActor
private func projectPicker(selection: Binding<UUID?>, projects: [Project], l10n: LocalizationStore) -> some View {
    Picker(l10n.text("Project"), selection: selection) {
        Text(l10n.text("None")).tag(UUID?.none)
        ForEach(projects, id: \.id) { project in
            Text(project.title).tag(Optional(project.id))
        }
    }
    .accessibilityIdentifier("picker-project")
}

@MainActor
private func goalPicker(selection: Binding<UUID?>, goals: [Goal], l10n: LocalizationStore) -> some View {
    Picker(l10n.text("Goal"), selection: selection) {
        Text(l10n.text("None")).tag(UUID?.none)
        ForEach(goals, id: \.id) { goal in
            Text(goal.title).tag(Optional(goal.id))
        }
    }
    .accessibilityIdentifier("picker-goal")
}

@MainActor
private struct EntrySheetScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalizationStore.self) private var l10n

    let title: String
    let saveTitle: String
    let saveAction: () -> Void
    let disabled: Bool
    let content: Content

    init(
        title: String,
        saveTitle: String,
        saveAction: @escaping () -> Void,
        disabled: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.saveTitle = saveTitle
        self.saveAction = saveAction
        self.disabled = disabled
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            Form {
                content
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.text("Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        saveAction()
                    }
                    .disabled(disabled)
                    .accessibilityIdentifier("sheet-save-button")
                }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }
}
