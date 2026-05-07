import SwiftData
import SwiftUI
import LifeOSCore

struct InspectorDetailView: View {
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var plannedEntries: [PlannedEntry]
    @Query private var assetSnapshots: [AssetSnapshot]
    @Query private var tasks: [TaskItem]
    @Query private var calendarItems: [CalendarItem]
    @Query private var goals: [Goal]
    @Query private var projects: [Project]
    @Query private var accounts: [Account]
    @Query private var categories: [LifeOSCore.Category]

    var body: some View {
        Group {
            switch appState.inspectorSelection {
            case let .ledger(id):
                if let item = ledgerEntries.first(where: { $0.id == id }) {
                    LedgerInspector(entry: item)
                } else {
                    emptyInspector
                }
            case let .planned(id):
                if let item = plannedEntries.first(where: { $0.id == id }) {
                    PlannedInspector(entry: item)
                } else {
                    emptyInspector
                }
            case let .asset(id):
                if let item = assetSnapshots.first(where: { $0.id == id }) {
                    AssetInspector(snapshot: item)
                } else {
                    emptyInspector
                }
            case let .task(id):
                if let item = tasks.first(where: { $0.id == id }) {
                    TaskInspector(task: item)
                } else {
                    emptyInspector
                }
            case let .calendar(id):
                if let item = calendarItems.first(where: { $0.id == id }) {
                    CalendarInspector(item: item)
                } else {
                    emptyInspector
                }
            case let .goal(id):
                if let item = goals.first(where: { $0.id == id }) {
                    GoalInspector(goal: item)
                } else {
                    emptyInspector
                }
            case let .project(id):
                if let item = projects.first(where: { $0.id == id }) {
                    ProjectInspector(project: item)
                } else {
                    emptyInspector
                }
            case let .account(id):
                if let item = accounts.first(where: { $0.id == id }) {
                    AccountInspector(account: item)
                } else {
                    emptyInspector
                }
            case let .category(id):
                if let item = categories.first(where: { $0.id == id }) {
                    CategoryInspector(category: item)
                } else {
                    emptyInspector
                }
            case .none:
                emptyInspector
            }
        }
        .padding(18)
    }

    private var emptyInspector: some View {
        ContentUnavailableView(l10n.text("Inspector"), systemImage: "sidebar.right", description: Text(l10n.text("Select a record to inspect or edit it.")))
    }
}

private struct LedgerInspector: View {
    @Bindable var entry: LedgerEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n

    var body: some View {
        inspectorLayout(title: l10n.text("Ledger Entry")) {
            Picker(l10n.text("Direction"), selection: $entry.directionRaw) {
                ForEach(EntryDirection.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option.rawValue)
                }
            }
            TextField(l10n.text("Title"), text: $entry.title)
            TextField(l10n.text("Amount"), value: $entry.amount, format: .number)
            DatePicker(l10n.text("Occurred On"), selection: $entry.occurredOn, displayedComponents: [.date])
            Text([entry.account?.name, entry.category?.name, entry.project?.title].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
            TextField(l10n.text("Note"), text: $entry.note, axis: .vertical)
                .lineLimit(3...6)
        } footer: {
            inspectorFooter(l10n: l10n, deleteAction: { tryDelete(entry) }, saveAction: { trySave() })
        }
    }

    private func trySave() { try? LifeOSRepository(context: modelContext).save() }
    private func tryDelete(_ model: LedgerEntry) { try? LifeOSRepository(context: modelContext).delete(model); appState.inspectorSelection = nil }
}

private struct PlannedInspector: View {
    @Bindable var entry: PlannedEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n

    var body: some View {
        inspectorLayout(title: l10n.text("Planned Entry")) {
            Picker(l10n.text("Direction"), selection: $entry.directionRaw) {
                ForEach(EntryDirection.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option.rawValue)
                }
            }
            TextField(l10n.text("Title"), text: $entry.title)
            TextField(l10n.text("Amount"), value: $entry.amount, format: .number)
            DatePicker(l10n.text("Due On"), selection: $entry.dueOn, displayedComponents: [.date])
            Text([entry.account?.name, entry.category?.name, entry.project?.title].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
            TextField(l10n.text("Note"), text: $entry.note, axis: .vertical)
                .lineLimit(3...6)
            Button(l10n.text("Convert To Ledger")) {
                _ = try? LifeOSRepository(context: modelContext).settle(entry)
                appState.inspectorSelection = nil
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("inspector-planned-settle")
        } footer: {
            inspectorFooter(l10n: l10n, deleteAction: { tryDelete(entry) }, saveAction: { trySave() })
        }
    }

    private func trySave() { try? LifeOSRepository(context: modelContext).save() }
    private func tryDelete(_ model: PlannedEntry) { try? LifeOSRepository(context: modelContext).delete(model); appState.inspectorSelection = nil }
}

private struct AssetInspector: View {
    @Bindable var snapshot: AssetSnapshot
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(MarketQuoteStore.self) private var marketQuoteStore
    @Environment(LocalizationStore.self) private var l10n
    @State private var quoteSymbol = ""
    @State private var unitsText = ""
    @State private var costBasisText = ""
    @State private var didLoad = false

    var body: some View {
        inspectorLayout(title: l10n.text("Asset Snapshot")) {
            TextField(l10n.text("Title"), text: $snapshot.title)
            TextField(l10n.text("Reference Amount"), value: $snapshot.amount, format: .number)
            DatePicker(l10n.text("Captured On"), selection: $snapshot.capturedOn, displayedComponents: [.date])
            Text([snapshot.account?.name, snapshot.category?.name].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
            Divider()
            Text(l10n.text("Taiwan Live Quote"))
                .font(.headline)
            TextField(l10n.text("Ticker"), text: $quoteSymbol)
            TextField(l10n.text("Units / Shares"), text: $unitsText)
            TextField(l10n.text("Cost Basis (optional)"), text: $costBasisText)
            if let quote = marketQuoteStore.quote(for: snapshot), let marketValue = marketQuoteStore.liveValue(for: snapshot) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.format("Live market value: %@", marketValue.currencyString))
                        .font(.headline)
                    Text(l10n.format("Quote: %@ · Updated %@ %@", quote.lastPrice.quotePriceString, quote.tradeDate ?? "-", quote.tradeTime ?? "-"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let dayChangeValue = marketQuoteStore.positionDayChangeValue(for: snapshot) {
                        Text(l10n.format("Day change: %@", dayChangeValue.signedCurrencyString) + (marketQuoteStore.dayChangePercent(for: snapshot).map { " · \($0.signedPercentDisplayString)" } ?? ""))
                            .foregroundStyle(dayChangeValue >= 0 ? .green : .red)
                    }
                    if let profit = marketQuoteStore.unrealizedProfit(for: snapshot) {
                        Text(l10n.format("Unrealized P/L: %@", profit.signedCurrencyString) + (marketQuoteStore.unrealizedReturn(for: snapshot).map { " · \($0.signedPercentDisplayString)" } ?? ""))
                            .foregroundStyle(profit >= 0 ? .green : .red)
                    }
                }
            } else if snapshot.usesLiveMarketQuote {
                Text(l10n.text("No live quote loaded yet. Open Assets and refresh quotes."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            TextField(l10n.text("Note"), text: $snapshot.note, axis: .vertical)
                .lineLimit(3...6)
        } footer: {
            inspectorFooter(l10n: l10n, deleteAction: { tryDelete(snapshot) }, saveAction: { trySave() })
        }
        .onAppear {
            guard didLoad == false else { return }
            quoteSymbol = snapshot.quoteSymbol ?? ""
            unitsText = snapshot.units.map(decimalToPlainString) ?? ""
            costBasisText = snapshot.costBasis.map(decimalToPlainString) ?? ""
            didLoad = true
        }
    }

    private func trySave() {
        snapshot.quoteSymbol = normalizedQuoteSymbol
        snapshot.units = decimalOrNil(from: unitsText)
        snapshot.costBasis = decimalOrNil(from: costBasisText)
        try? LifeOSRepository(context: modelContext).save()
    }
    private func tryDelete(_ model: AssetSnapshot) { try? LifeOSRepository(context: modelContext).delete(model); appState.inspectorSelection = nil }

    private func decimalOrNil(from raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard trimmed.isEmpty == false else { return nil }
        return Decimal(string: trimmed)
    }

    private var normalizedQuoteSymbol: String? {
        let trimmed = quoteSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func decimalToPlainString(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }
}

private struct TaskInspector: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n

    var body: some View {
        inspectorLayout(title: l10n.text("Task")) {
            TextField(l10n.text("Title"), text: $task.title)
            Picker(l10n.text("Status"), selection: $task.statusRaw) {
                ForEach(TaskState.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option.rawValue)
                }
            }
            Picker(l10n.text("Priority"), selection: $task.priorityRaw) {
                ForEach(TaskPriority.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option.rawValue)
                }
            }
            if let binding = Binding($task.dueDate) {
                DatePicker(l10n.text("Due Date"), selection: binding)
            }
            Text(task.project?.title ?? l10n.text("No linked project"))
                .foregroundStyle(.secondary)
            TextField(l10n.text("Note"), text: $task.note, axis: .vertical)
                .lineLimit(3...6)
        } footer: {
            inspectorFooter(l10n: l10n, deleteAction: { tryDelete(task) }, saveAction: { trySave() })
        }
    }

    private func trySave() { try? LifeOSRepository(context: modelContext).save() }
    private func tryDelete(_ model: TaskItem) { try? LifeOSRepository(context: modelContext).delete(model); appState.inspectorSelection = nil }
}

private struct CalendarInspector: View {
    @Bindable var item: CalendarItem
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n

    var body: some View {
        inspectorLayout(title: l10n.text("Calendar Item")) {
            TextField(l10n.text("Title"), text: $item.title)
            DatePicker(l10n.text("Start"), selection: $item.startDate)
            DatePicker(l10n.text("End"), selection: $item.endDate)
            Toggle(l10n.text("All Day"), isOn: $item.allDay)
            TextField(l10n.text("Location"), text: $item.location)
            Text(item.project?.title ?? l10n.text("No linked project"))
                .foregroundStyle(.secondary)
            TextField(l10n.text("Note"), text: $item.note, axis: .vertical)
                .lineLimit(3...6)
        } footer: {
            inspectorFooter(l10n: l10n, deleteAction: { tryDelete(item) }, saveAction: { trySave() })
        }
    }

    private func trySave() { try? LifeOSRepository(context: modelContext).save() }
    private func tryDelete(_ model: CalendarItem) { try? LifeOSRepository(context: modelContext).delete(model); appState.inspectorSelection = nil }
}

private struct GoalInspector: View {
    @Bindable var goal: Goal
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n

    var body: some View {
        inspectorLayout(title: l10n.text("Goal")) {
            TextField(l10n.text("Title"), text: $goal.title)
            Picker(l10n.text("State"), selection: $goal.stateRaw) {
                ForEach(GoalState.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option.rawValue)
                }
            }
            if let binding = Binding($goal.targetDate) {
                DatePicker(l10n.text("Target Date"), selection: binding, displayedComponents: [.date])
            }
            TextField(l10n.text("Summary"), text: $goal.summary, axis: .vertical)
                .lineLimit(4...8)
        } footer: {
            inspectorFooter(l10n: l10n, deleteAction: { tryDelete(goal) }, saveAction: { trySave() })
        }
    }

    private func trySave() { try? LifeOSRepository(context: modelContext).save() }
    private func tryDelete(_ model: Goal) { try? LifeOSRepository(context: modelContext).delete(model); appState.inspectorSelection = nil }
}

private struct ProjectInspector: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n

    var body: some View {
        inspectorLayout(title: l10n.text("Project")) {
            TextField(l10n.text("Title"), text: $project.title)
            Picker(l10n.text("State"), selection: $project.stateRaw) {
                ForEach(ProjectState.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option.rawValue)
                }
            }
            if let binding = Binding($project.deadline) {
                DatePicker(l10n.text("Deadline"), selection: binding, displayedComponents: [.date])
            }
            Text(project.goal?.title ?? l10n.text("No linked goal"))
                .foregroundStyle(.secondary)
            TextField(l10n.text("Summary"), text: $project.summary, axis: .vertical)
                .lineLimit(4...8)
            TextField(l10n.text("Note"), text: $project.note, axis: .vertical)
                .lineLimit(3...6)
        } footer: {
            inspectorFooter(l10n: l10n, deleteAction: { tryDelete(project) }, saveAction: { trySave() })
        }
    }

    private func trySave() { try? LifeOSRepository(context: modelContext).save() }
    private func tryDelete(_ model: Project) { try? LifeOSRepository(context: modelContext).delete(model); appState.inspectorSelection = nil }
}

private struct AccountInspector: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n

    var body: some View {
        inspectorLayout(title: l10n.text("Account")) {
            TextField(l10n.text("Name"), text: $account.name)
            Picker(l10n.text("Kind"), selection: $account.kindRaw) {
                ForEach(AccountKind.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option.rawValue)
                }
            }
            TextField(l10n.text("Note"), text: $account.note, axis: .vertical)
                .lineLimit(3...6)
        } footer: {
            inspectorFooter(l10n: l10n, deleteAction: { tryDelete(account) }, saveAction: { trySave() })
        }
    }

    private func trySave() { try? LifeOSRepository(context: modelContext).save() }
    private func tryDelete(_ model: Account) { try? LifeOSRepository(context: modelContext).delete(model); appState.inspectorSelection = nil }
}

private struct CategoryInspector: View {
    @Bindable var category: LifeOSCore.Category
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n

    var body: some View {
        inspectorLayout(title: l10n.text("Category")) {
            TextField(l10n.text("Name"), text: $category.name)
            Picker(l10n.text("Scope"), selection: $category.scopeRaw) {
                ForEach(CategoryScope.allCases) { option in
                    Text(option.localizedTitle(in: l10n.language)).tag(option.rawValue)
                }
            }
            TextField(l10n.text("Note"), text: $category.note, axis: .vertical)
                .lineLimit(3...6)
        } footer: {
            inspectorFooter(l10n: l10n, deleteAction: { tryDelete(category) }, saveAction: { trySave() })
        }
    }

    private func trySave() { try? LifeOSRepository(context: modelContext).save() }
    private func tryDelete(_ model: LifeOSCore.Category) { try? LifeOSRepository(context: modelContext).delete(model); appState.inspectorSelection = nil }
}

private func inspectorLayout<Content: View, Footer: View>(title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) -> some View {
    VStack(alignment: .leading, spacing: 16) {
        Text(title)
            .font(.title2.weight(.semibold))
        Form {
            content()
        }
        footer()
    }
}

@MainActor
private func inspectorFooter(l10n: LocalizationStore, deleteAction: @escaping () -> Void, saveAction: @escaping () -> Void) -> some View {
    HStack {
        Button(l10n.text("Delete"), role: .destructive, action: deleteAction)
            .accessibilityIdentifier("inspector-delete")
        Spacer()
        Button(l10n.text("Save"), action: saveAction)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("inspector-save")
    }
}

@MainActor
private extension Binding {
    init?(_ source: Binding<Value?>) {
        guard let wrappedValue = source.wrappedValue else { return nil }
        self.init(
            get: { source.wrappedValue ?? wrappedValue },
            set: { source.wrappedValue = $0 }
        )
    }
}
