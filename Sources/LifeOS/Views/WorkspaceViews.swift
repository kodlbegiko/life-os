import SwiftData
import SwiftUI
import LifeOSCore
import UniformTypeIdentifiers

struct OverviewWorkspaceView: View {
    @State private var schedulingTask: TaskItem?
    @State private var schedulingKind: DailyPlanItemKind = .focus
    @State private var weekPlanDraft: WeekPlanDraft?
    @State private var weekPlanApplyResult: WeekPlanApplyResult?
    @State private var selectedWeekPlanItemIDs = Set<String>()
    @State private var timeBlockEnabledWeekPlanItemIDs = Set<String>()
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(MarketQuoteStore.self) private var marketQuoteStore
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\Account.createdAt, order: .forward)]) private var accounts: [Account]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var plannedEntries: [PlannedEntry]
    @Query private var assetSnapshots: [AssetSnapshot]
    @Query private var tasks: [TaskItem]
    @Query private var calendarItems: [CalendarItem]
    @Query private var projects: [Project]
    @Query private var dailyPlanItems: [DailyPlanItem]
    private let quoteRefreshTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    private var snapshot: OverviewSnapshot {
        DashboardEngine.makeOverview(
            accounts: accounts,
            ledgerEntries: ledgerEntries,
            plannedEntries: plannedEntries,
            assetSnapshots: assetSnapshots,
            tasks: tasks,
            calendarItems: calendarItems,
            projects: projects,
            language: l10n.language
        )
    }

    private var commandSnapshot: CommandCenterSnapshot {
        CommandCenterEngine.makeSnapshot(
            tasks: tasks,
            calendarItems: calendarItems,
            projects: projects,
            dailyPlanItems: dailyPlanItems,
            language: l10n.language
        )
    }

    private var scheduleQuality: ScheduleQualitySnapshot {
        ScheduleQualityEngine.makeSnapshot(
            tasks: tasks,
            calendarItems: calendarItems,
            projects: projects,
            dailyPlanItems: dailyPlanItems,
            language: l10n.language
        )
    }

    private var isEmpty: Bool {
        ledgerEntries.isEmpty && plannedEntries.isEmpty && assetSnapshots.isEmpty && tasks.isEmpty && calendarItems.isEmpty && projects.isEmpty
    }

    private var query: String {
        appState.trimmedSearchText
    }

    private var filteredUrgentTasks: [TaskItem] {
        snapshot.urgentTasks.filter {
            workspaceSearchMatches(query, fields: [$0.title, $0.note, $0.project?.title])
        }
    }

    private var filteredUpcomingPlanned: [PlannedEntry] {
        snapshot.upcomingPlanned.filter {
            workspaceSearchMatches(query, fields: [$0.title, $0.note, $0.account?.name, $0.category?.name, $0.project?.title])
        }
    }

    private var filteredTodayEvents: [CalendarItem] {
        snapshot.todayEvents.filter {
            workspaceSearchMatches(query, fields: [$0.title, $0.location, $0.note, $0.project?.title])
        }
    }

    private var filteredProjectStatuses: [ProjectStatusSnapshot] {
        snapshot.projectStatuses.filter {
            workspaceSearchMatches(query, fields: [$0.title, $0.focus, $0.deadline?.dayLabel(locale: l10n.locale)])
        }
    }

    private var filteredConflicts: [ConflictItem] {
        snapshot.conflicts.filter {
            workspaceSearchMatches(query, fields: [$0.title, $0.detail, $0.action, $0.severity.rawValue])
        }
    }

    private var hasOverviewResults: Bool {
        filteredUrgentTasks.isEmpty == false ||
        filteredUpcomingPlanned.isEmpty == false ||
        filteredTodayEvents.isEmpty == false ||
        filteredProjectStatuses.isEmpty == false ||
        filteredConflicts.isEmpty == false
    }

    private var latestAssetSnapshots: [AssetSnapshot] {
        DashboardEngine.latestAssetSnapshots(assetSnapshots)
    }

    private var trackedAssetSnapshots: [AssetSnapshot] {
        latestAssetSnapshots.filter(\.usesLiveMarketQuote)
    }

    private var investableSnapshots: [AssetSnapshot] {
        latestAssetSnapshots.filter { snapshot in
            switch snapshot.account?.kind {
            case .some(let kind):
                return kind.isLiquid == false
            case .none:
                return true
            }
        }
    }

    private var displayedAssetTotal: Decimal {
        latestAssetSnapshots.reduce(Decimal.zero) { total, snapshot in
            total + marketQuoteStore.displayValue(for: snapshot)
        }
    }

    private var displayedInvestableAssetTotal: Decimal {
        investableSnapshots.reduce(Decimal.zero) { total, snapshot in
            total + marketQuoteStore.displayValue(for: snapshot)
        }
    }

    private var displayedTotalWealth: Decimal {
        snapshot.liquidBalance + displayedInvestableAssetTotal
    }

    private var liquidAccountBalances: [AccountBalanceSnapshot] {
        snapshot.accountBalances.filter { $0.kind.isLiquid }
    }

    var body: some View {
        overviewContent
            .task(id: trackedAssetSnapshots.map { "\($0.id.uuidString):\($0.normalizedQuoteSymbol ?? "-"):\($0.units?.plainNumberString ?? "-")" }.joined(separator: "|")) {
                guard appState.activeSection == .overview else { return }
                await marketQuoteStore.refresh(for: trackedAssetSnapshots)
            }
            .onReceive(quoteRefreshTimer) { _ in
                guard appState.activeSection == .overview, trackedAssetSnapshots.isEmpty == false else { return }
                Task { await marketQuoteStore.refresh(for: trackedAssetSnapshots) }
            }
            .sheet(isPresented: Binding(
                get: { schedulingTask != nil },
                set: { isPresented in
                    if isPresented == false {
                        schedulingTask = nil
                    }
                }
            )) {
                if let schedulingTask {
                    TaskScheduleSheet(task: schedulingTask, initialKind: schedulingKind)
                        .environment(appState)
                }
            }
    }

    @ViewBuilder
    private var overviewContent: some View {
        if isEmpty {
            EmptyStateView(
                title: l10n.text("Start with a clean Life OS"),
                detail: l10n.text("This app starts with an empty local database. Install the starter template if you want a quick structure to edit."),
                buttonTitle: l10n.text("Install Starter Template")
            ) {
                _ = try? StarterTemplateService.installIfPossible(context: modelContext, language: l10n.language)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                        SectionHeader(
                            title: l10n.text("Daily Command Center"),
                            detail: workspaceDetailText(base: l10n.text("See today's must-do work, time blocks, deadline risk, and the next 7 days."), query: query, resultCount: filteredUrgentTasks.count + filteredUpcomingPlanned.count + filteredTodayEvents.count + filteredProjectStatuses.count + filteredConflicts.count, itemNoun: l10n.text("signals"), language: l10n.language),
                            buttonTitle: nil,
                            action: nil,
                            accessibilityID: "section-overview-header"
                        )

                        if appState.isSearching {
                            WorkspaceSearchBanner(query: query, resultCount: filteredUrgentTasks.count + filteredUpcomingPlanned.count + filteredTodayEvents.count + filteredProjectStatuses.count + filteredConflicts.count, itemNoun: l10n.text("signals")) {
                                appState.clearSearch()
                            }
                        }

                        weekPlanPanel

                        commandCenterPanel

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                            MetricCard(label: l10n.text("Total Wealth"), value: displayedTotalWealth.currencyString, detail: l10n.text("Liquid cash plus non-liquid assets"), tone: .primary)
                            MetricCard(label: l10n.text("Callable Now"), value: snapshot.liquidBalance.currencyString, detail: l10n.text("Current cash, bank, and digital balances"), tone: snapshot.liquidBalance >= 0 ? .blue : .red)
                            MetricCard(label: l10n.text("Invested"), value: displayedInvestableAssetTotal.currencyString, detail: trackedAssetSnapshots.isEmpty ? l10n.text("Latest non-liquid asset snapshots") : l10n.text("Includes live Taiwan quotes"), tone: .primary)
                            MetricCard(label: l10n.text("Reserved 30D"), value: snapshot.plannedExpense30Days.currencyString, detail: l10n.text("Planned outgoing commitments"), tone: .orange)
                            MetricCard(label: l10n.text("Free Cash"), value: snapshot.freeCashAfterPlanned30Days.currencyString, detail: l10n.text("Callable now minus planned expense"), tone: snapshot.freeCashAfterPlanned30Days >= 0 ? .green : .red)
                            MetricCard(label: l10n.text("30D Outlook"), value: snapshot.projectedLiquidAfter30Days.currencyString, detail: l10n.text("Callable now plus planned net"), tone: snapshot.projectedLiquidAfter30Days >= 0 ? .green : .red)
                        }

                        HStack(alignment: .top, spacing: 18) {
                            overviewColumn(title: l10n.text("Money Accounts"), systemImage: "wallet.bifold") {
                                if liquidAccountBalances.isEmpty {
                                    Text(l10n.text("Add ledger entries to show live callable balances by account."))
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(Array(liquidAccountBalances.enumerated()), id: \.element.id) { _, account in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(account.name)
                                                    .font(.headline)
                                                Text(account.kind.localizedTitle(in: l10n.language))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(account.balance.currencyString)
                                                .font(.headline.monospacedDigit())
                                                .foregroundStyle(account.balance >= 0 ? Color.primary : Color.red)
                                        }
                                    }
                                }
                            }

                            overviewColumn(title: l10n.text("Money Signals"), systemImage: "banknote") {
                                VStack(alignment: .leading, spacing: 10) {
                                    moneySignalRow(label: l10n.text("Callable now"), value: snapshot.liquidBalance.currencyString, tone: snapshot.liquidBalance >= 0 ? .blue : .red)
                                    moneySignalRow(label: l10n.text("Reserved next 30 days"), value: snapshot.plannedExpense30Days.currencyString, tone: .orange)
                                    moneySignalRow(label: l10n.text("Free after reserve"), value: snapshot.freeCashAfterPlanned30Days.currencyString, tone: snapshot.freeCashAfterPlanned30Days >= 0 ? .green : .red)
                                    moneySignalRow(label: l10n.text("Live investments"), value: displayedInvestableAssetTotal.currencyString, tone: .primary)
                                }
                            }
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                            MetricCard(label: l10n.text("This Month Income"), value: snapshot.monthIncome.currencyString, detail: l10n.text("Actual posted income"), tone: .green)
                            MetricCard(label: l10n.text("This Month Expense"), value: snapshot.monthExpense.currencyString, detail: l10n.text("Actual posted expense"), tone: .red)
                            MetricCard(label: l10n.text("This Month Net"), value: snapshot.monthNet.currencyString, detail: l10n.text("Income minus expense"), tone: snapshot.monthNet >= 0 ? .green : .red)
                            MetricCard(label: l10n.text("Next 30 Days"), value: snapshot.plannedNet30Days.currencyString, detail: l10n.text("Planned net movement"), tone: snapshot.plannedNet30Days >= 0 ? .blue : .orange)
                            MetricCard(label: l10n.text("Assets"), value: displayedAssetTotal.currencyString, detail: trackedAssetSnapshots.isEmpty ? l10n.text("Latest snapshot total") : l10n.text("Includes live Taiwan quotes"), tone: .primary)
                        }

                        if appState.isSearching && hasOverviewResults == false {
                            EmptyStateView(
                                title: l10n.text("No overview signals matched"),
                                detail: l10n.text("Try a broader keyword or clear the current search."),
                                buttonTitle: l10n.text("Clear Search"),
                                action: appState.clearSearch
                            )
                            .frame(minHeight: 240)
                        } else {

                            HStack(alignment: .top, spacing: 18) {
                                overviewColumn(title: l10n.text("Urgent Tasks"), systemImage: "checklist.checked") {
                                    if filteredUrgentTasks.isEmpty {
                                        Text(appState.isSearching ? l10n.text("No urgent tasks match the current search.") : l10n.text("No urgent tasks."))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(filteredUrgentTasks, id: \.id) { task in
                                            Button {
                                                appState.reveal(.task(task.id))
                                            } label: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text(task.title)
                                                        .font(.headline)
                                                    Text(task.dueDate?.shortLabel(locale: l10n.locale) ?? l10n.text("No due date"))
                                                        .font(.callout)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("overview-task-\(task.id.uuidString)")
                                        }
                                    }
                                }

                                overviewColumn(title: l10n.text("Upcoming Planned"), systemImage: "calendar.badge.clock") {
                                    if filteredUpcomingPlanned.isEmpty {
                                        Text(appState.isSearching ? l10n.text("No planned entries match the current search.") : l10n.text("No planned entries in the next 30 days."))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(filteredUpcomingPlanned, id: \.id) { entry in
                                            Button {
                                                appState.reveal(.planned(entry.id))
                                            } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text(entry.title)
                                                            .font(.headline)
                                                        Text(entry.dueOn.shortLabel(locale: l10n.locale))
                                                            .font(.callout)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    Text((entry.direction == .expense ? -entry.amount : entry.amount).currencyString)
                                                        .foregroundStyle(entry.direction == .income ? .green : .orange)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("overview-planned-\(entry.id.uuidString)")
                                        }
                                    }
                                }
                            }

                            HStack(alignment: .top, spacing: 18) {
                                overviewColumn(title: l10n.text("Today"), systemImage: "calendar") {
                                    if filteredTodayEvents.isEmpty {
                                        Text(appState.isSearching ? l10n.text("No calendar items match the current search.") : l10n.text("No events on the calendar today."))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(filteredTodayEvents, id: \.id) { item in
                                            Button {
                                                appState.reveal(.calendar(item.id))
                                            } label: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text(item.title)
                                                        .font(.headline)
                                                    Text(item.startDate.shortLabel(locale: l10n.locale))
                                                        .font(.callout)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("overview-calendar-\(item.id.uuidString)")
                                        }
                                    }
                                }

                                overviewColumn(title: l10n.text("Conflicts"), systemImage: "exclamationmark.triangle") {
                                    if filteredConflicts.isEmpty {
                                        Text(appState.isSearching ? l10n.text("No conflicts match the current search.") : l10n.text("No major conflicts right now."))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(filteredConflicts) { conflict in
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(conflict.title)
                                                    .font(.headline)
                                                Text(conflict.detail)
                                                    .font(.callout)
                                                    .foregroundStyle(.secondary)
                                                Text(conflict.action)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(12)
                                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 14) {
                                Text(l10n.text("Project Readiness"))
                                    .font(.title3.weight(.semibold))
                                ForEach(filteredProjectStatuses) { project in
                                    Button {
                                        appState.reveal(.project(project.id))
                                    } label: {
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(project.title)
                                                        .font(.headline)
                                                    Text(project.focus)
                                                        .font(.callout)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Text("\(project.readiness)%")
                                                    .font(.headline.monospacedDigit())
                                            }
                                            ProgressView(value: Double(project.readiness), total: 100)
                                            HStack {
                                                Text(l10n.format("Open tasks: %d", project.openTaskCount))
                                                Spacer()
                                                Text(project.deadline?.dayLabel(locale: l10n.locale) ?? l10n.text("No deadline"))
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }
                                        .padding(16)
                                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("overview-project-\(project.id.uuidString)")
                                }
                            }
                        }
                    }
                    .padding(24)
                }
        }
    }

    private var weekPlanPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                CommandSectionHeader(
                    title: l10n.text("This Week Battle Plan"),
                    detail: l10n.text("Generate an editable 7-day draft with up to 3 balanced focus items per day. Nothing is saved until you apply it."),
                    systemImage: "rectangle.3.group.bubble.left"
                )
                Spacer()
                HStack(spacing: 8) {
                    Button(l10n.text("Generate Week Plan")) {
                        generateWeekPlan()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("overview-week-plan-generate")

                    Button(l10n.text("Select All")) {
                        selectAllWeekPlanItems()
                    }
                    .buttonStyle(.bordered)
                    .disabled(weekPlanDraft == nil || weekPlanDraft?.focusCount == 0)
                    .accessibilityIdentifier("overview-week-plan-select-all")

                    Button(l10n.text("Clear All")) {
                        clearWeekPlanItems()
                    }
                    .buttonStyle(.bordered)
                    .disabled(weekPlanDraft == nil || weekPlanDraft?.focusCount == 0)
                    .accessibilityIdentifier("overview-week-plan-clear-all")

                    Button(l10n.text("Apply Selected")) {
                        applyWeekPlan()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(weekPlanDraft == nil || selectedWeekPlanItemIDs.isEmpty)
                    .accessibilityIdentifier("overview-week-plan-apply-selected")

                    Button(l10n.text("Dismiss Draft")) {
                        weekPlanDraft = nil
                        weekPlanApplyResult = nil
                        selectedWeekPlanItemIDs.removeAll()
                        timeBlockEnabledWeekPlanItemIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .disabled(weekPlanDraft == nil && weekPlanApplyResult == nil)
                    .accessibilityIdentifier("overview-week-plan-dismiss")
                }
            }

            if let weekPlanApplyResult {
                Text(weekPlanResultText(weekPlanApplyResult))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("overview-week-plan-result")
            }

            if let weekPlanDraft {
                if weekPlanDraft.focusCount == 0 {
                    Text(l10n.text("No eligible open tasks for this week's draft. Add tasks or install the personal plan template first."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(weekPlanDraft.days) { day in
                                weekPlanDayColumn(day)
                                    .frame(width: 340)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("overview-week-plan-scroll")
                }
            } else {
                Text(l10n.text("Use Generate Week Plan to preview a balanced plan across competitions, earning, travel, investment, and long-term work."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview-week-plan")
    }

    private func weekPlanDayColumn(_ day: WeekPlanDayDraft) -> some View {
        ReadableDayColumn(
            title: day.date.dayLabel(locale: l10n.locale),
            countTitle: l10n.format("Total Focus %d", day.items.count),
            statusTitle: l10n.text("All items shown")
        ) {
            if day.items.isEmpty {
                Text(l10n.text("No draft focus"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            } else {
                ForEach(day.items) { item in
                    weekPlanItemCard(item)
                }
            }
        }
        .accessibilityIdentifier("overview-week-plan-day-\(day.id)")
    }

    private func weekPlanItemCard(_ item: WeekPlanDraftItem) -> some View {
        let isFocusSelected = selectedWeekPlanItemIDs.contains(item.id)
        let hasSuggestedTime = item.suggestedStart != nil && item.suggestedEnd != nil
        let outcome = weekPlanOutcome(for: item)
        let actionColumns = [
            GridItem(.flexible(minimum: 128), spacing: 8),
            GridItem(.flexible(minimum: 128), spacing: 8)
        ]
        return ReadableTaskCard(
            title: item.task.title,
            statusTitle: item.line.localizedTitle(in: l10n.language),
            statusTone: weekPlanLineColor(item.line),
            accessibilityLabel: "\(item.task.title), \(item.line.localizedTitle(in: l10n.language))"
        ) {
            CommandMetadataRow(label: l10n.text("Draft day"), value: item.plannedDate.dayLabel(locale: l10n.locale), systemImage: "calendar")
            CommandMetadataRow(label: l10n.text("Source"), value: item.line.localizedTitle(in: l10n.language), systemImage: "point.3.connected.trianglepath.dotted")
            CommandMetadataRow(label: l10n.text("Reason"), value: item.reason, systemImage: "lightbulb")
            if let suggestedStart = item.suggestedStart, let suggestedEnd = item.suggestedEnd {
                CommandMetadataRow(label: l10n.text("Suggested time"), value: timeRangeText(start: suggestedStart, end: suggestedEnd), systemImage: "clock")
                if let outcome {
                    ReadableStatusPill(title: weekPlanOutcomeText(outcome), systemImage: "calendar.badge.checkmark", tone: weekPlanOutcomeColor(outcome))
                } else if item.timeBlockConflict && timeBlockEnabledWeekPlanItemIDs.contains(item.id) {
                    ReadableStatusPill(title: l10n.text("Will auto-find available slot"), systemImage: "arrow.triangle.2.circlepath", tone: .orange)
                } else if item.timeBlockConflict {
                    ReadableStatusPill(title: l10n.text("Conflict detected"), systemImage: "exclamationmark.triangle", tone: .orange)
                }
            } else if let outcome {
                ReadableStatusPill(title: weekPlanOutcomeText(outcome), systemImage: "calendar.badge.checkmark", tone: weekPlanOutcomeColor(outcome))
            }
            if let conflictTitle = item.conflictTitle {
                CommandMetadataRow(label: l10n.text("Conflict"), value: conflictTitle, systemImage: "exclamationmark.triangle")
            }
        } actions: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Toggle(l10n.text("Create Focus"), isOn: Binding(
                        get: { selectedWeekPlanItemIDs.contains(item.id) },
                        set: { toggleWeekPlanFocus(item.id, isOn: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("overview-week-plan-focus-toggle-\(item.id)")

                    Toggle(l10n.text("Create Time Block"), isOn: Binding(
                        get: { timeBlockEnabledWeekPlanItemIDs.contains(item.id) },
                        set: { toggleWeekPlanTimeBlock(item.id, isOn: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(isFocusSelected == false || hasSuggestedTime == false)
                    .accessibilityIdentifier("overview-week-plan-timeblock-toggle-\(item.id)")
                }

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                    ReadableActionButton(title: l10n.text("Move Previous Day")) {
                        moveWeekPlanItem(item.id, byDays: -1)
                    }
                    .disabled(weekPlanCanMove(item, byDays: -1) == false)
                    .accessibilityIdentifier("overview-week-plan-move-previous-\(item.id)")

                    ReadableActionButton(title: l10n.text("Move Next Day")) {
                        moveWeekPlanItem(item.id, byDays: 1)
                    }
                    .disabled(weekPlanCanMove(item, byDays: 1) == false)
                    .accessibilityIdentifier("overview-week-plan-move-next-\(item.id)")

                    Menu {
                        ForEach(0..<3, id: \.self) { slotIndex in
                            Button(weekPlanTimeSlotLabel(for: item, slotIndex: slotIndex)) {
                                updateWeekPlanItemTimeSlot(item.id, slotIndex: slotIndex)
                            }
                            .accessibilityIdentifier("overview-week-plan-time-slot-\(item.id)-\(slotIndex)")
                        }
                    } label: {
                        Text(l10n.text("Change Suggested Time"))
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .accessibilityIdentifier("overview-week-plan-time-menu-\(item.id)")

                    ReadableActionButton(title: l10n.text("Remove from Draft")) {
                        removeWeekPlanItem(item.id)
                    }
                    .accessibilityIdentifier("overview-week-plan-remove-\(item.id)")
                }
            }
        }
        .accessibilityIdentifier("overview-week-plan-item-\(item.task.id.uuidString)")
    }

    private func generateWeekPlan() {
        let draft = WeekPlanEngine.makeDraft(
            tasks: tasks,
            calendarItems: calendarItems,
            projects: projects,
            dailyPlanItems: dailyPlanItems,
            language: l10n.language
        )
        weekPlanDraft = draft
        setWeekPlanSelection(to: draft)
        weekPlanApplyResult = nil
    }

    private func applyWeekPlan() {
        guard let weekPlanDraft else { return }
        do {
            let request = WeekPlanApplyRequest(
                selectedDraftItemIDs: selectedWeekPlanItemIDs,
                timeBlockEnabledDraftItemIDs: timeBlockEnabledWeekPlanItemIDs
            )
            weekPlanApplyResult = try LifeOSRepository(context: modelContext).applyWeekPlanDraft(weekPlanDraft, request: request)
        } catch {
            weekPlanApplyResult = nil
        }
    }

    private func weekPlanResultText(_ result: WeekPlanApplyResult) -> String {
        l10n.format(
            "Week plan applied: %d focus added, %d existing focus, %d time blocks added, %d rescheduled, %d existing time blocks, %d conflict skipped, %d focus-only no slot.",
            result.focusCreated,
            result.focusSkippedExisting,
            result.timeBlocksCreated,
            result.timeBlocksRescheduled,
            result.timeBlocksSkippedExisting,
            result.timeBlocksSkippedForConflict,
            result.timeBlocksSkippedNoAvailableSlot
        )
    }

    private func setWeekPlanSelection(to draft: WeekPlanDraft) {
        let itemIDs = Set(draft.days.flatMap(\.items).map(\.id))
        selectedWeekPlanItemIDs = itemIDs
        timeBlockEnabledWeekPlanItemIDs = itemIDs
    }

    private func selectAllWeekPlanItems() {
        guard let weekPlanDraft else { return }
        setWeekPlanSelection(to: weekPlanDraft)
    }

    private func clearWeekPlanItems() {
        selectedWeekPlanItemIDs.removeAll()
        timeBlockEnabledWeekPlanItemIDs.removeAll()
    }

    private func moveWeekPlanItem(_ itemID: String, byDays offset: Int) {
        guard let draft = weekPlanDraft,
              let item = draft.days.flatMap(\.items).first(where: { $0.id == itemID }),
              let targetDate = Calendar.current.date(byAdding: .day, value: offset, to: item.plannedDate),
              draft.days.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: targetDate) })
        else {
            return
        }

        weekPlanDraft = WeekPlanEngine.moveDraftItem(
            draft,
            itemID: itemID,
            to: targetDate,
            calendarItems: calendarItems
        )
        weekPlanApplyResult = nil
    }

    private func removeWeekPlanItem(_ itemID: String) {
        guard let draft = weekPlanDraft else { return }
        weekPlanDraft = WeekPlanEngine.removeDraftItem(draft, itemID: itemID)
        selectedWeekPlanItemIDs.remove(itemID)
        timeBlockEnabledWeekPlanItemIDs.remove(itemID)
        weekPlanApplyResult = nil
    }

    private func updateWeekPlanItemTimeSlot(_ itemID: String, slotIndex: Int) {
        guard let draft = weekPlanDraft else { return }
        weekPlanDraft = WeekPlanEngine.updateDraftItemTimeSlot(
            draft,
            itemID: itemID,
            slotIndex: slotIndex,
            calendarItems: calendarItems
        )
        weekPlanApplyResult = nil
    }

    private func weekPlanCanMove(_ item: WeekPlanDraftItem, byDays offset: Int) -> Bool {
        guard let draft = weekPlanDraft,
              let targetDate = Calendar.current.date(byAdding: .day, value: offset, to: item.plannedDate)
        else {
            return false
        }
        return draft.days.contains { Calendar.current.isDate($0.date, inSameDayAs: targetDate) }
    }

    private func weekPlanTimeSlotLabel(for item: WeekPlanDraftItem, slotIndex: Int) -> String {
        guard let slot = WeekPlanEngine.suggestedTimeSlot(on: item.plannedDate, index: slotIndex) else {
            return l10n.text("No suggested time")
        }
        return timeRangeText(start: slot.start, end: slot.end)
    }

    private func toggleWeekPlanFocus(_ itemID: String, isOn: Bool) {
        if isOn {
            selectedWeekPlanItemIDs.insert(itemID)
            timeBlockEnabledWeekPlanItemIDs.insert(itemID)
        } else {
            selectedWeekPlanItemIDs.remove(itemID)
            timeBlockEnabledWeekPlanItemIDs.remove(itemID)
        }
    }

    private func toggleWeekPlanTimeBlock(_ itemID: String, isOn: Bool) {
        guard selectedWeekPlanItemIDs.contains(itemID) else {
            timeBlockEnabledWeekPlanItemIDs.remove(itemID)
            return
        }
        if isOn {
            timeBlockEnabledWeekPlanItemIDs.insert(itemID)
        } else {
            timeBlockEnabledWeekPlanItemIDs.remove(itemID)
        }
    }

    private func weekPlanOutcome(for item: WeekPlanDraftItem) -> WeekPlanTimeBlockApplyOutcome? {
        weekPlanApplyResult?.timeBlockOutcomes.first { $0.draftItemID == item.id }
    }

    private func weekPlanOutcomeText(_ outcome: WeekPlanTimeBlockApplyOutcome) -> String {
        switch outcome.status {
        case .created:
            if let start = outcome.scheduledStart, let end = outcome.scheduledEnd {
                return l10n.format("Created at %@", timeRangeText(start: start, end: end))
            }
            return l10n.text("Created")
        case .rescheduled:
            if let start = outcome.scheduledStart, let end = outcome.scheduledEnd {
                return l10n.format("Moved to %@", timeRangeText(start: start, end: end))
            }
            return l10n.text("Moved to available slot")
        case .skippedExisting:
            return l10n.text("Already planned")
        case .skippedConflict:
            return l10n.text("Skipped time block due to conflict")
        case .skippedNoAvailableSlot:
            return l10n.text("Focus only: no available slot")
        }
    }

    private func weekPlanOutcomeColor(_ outcome: WeekPlanTimeBlockApplyOutcome) -> Color {
        switch outcome.status {
        case .created:
            return .green
        case .rescheduled:
            return .blue
        case .skippedExisting:
            return .secondary
        case .skippedConflict, .skippedNoAvailableSlot:
            return .orange
        }
    }

    private func weekPlanLineColor(_ line: WeekPlanLine) -> Color {
        switch line {
        case .competition:
            return .orange
        case .earning:
            return .green
        case .travel:
            return .blue
        case .investment:
            return .mint
        case .snow:
            return .cyan
        case .academic:
            return .indigo
        case .general:
            return .secondary
        }
    }

    private func timeRangeText(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = l10n.locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }

    private func dateListText(_ dates: [Date]) -> String {
        dates
            .map { $0.dayLabel(locale: l10n.locale) }
            .joined(separator: " · ")
    }

    private func scheduleQualityReasonText(_ reason: ScheduleNeedsTimeBlockReason) -> String {
        switch reason {
        case .highPriority:
            return l10n.text("High priority focus")
        case .dueSoon:
            return l10n.text("Due within 7 days")
        case .projectDeadlineSoon:
            return l10n.text("Project deadline within 7 days")
        }
    }

    @ViewBuilder
    private var commandCenterPanel: some View {
        if let today = commandSnapshot.today {
            let quality = scheduleQuality
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 18) {
                    commandOverviewColumn(title: l10n.text("Today's Must Do"), detail: l10n.format("Total Focus %d", today.focusItems.count), systemImage: "target") {
                        if today.focusItems.isEmpty {
                            Text(l10n.text("No focus items for today."))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(today.focusItems) { item in
                                commandFocusCard(item, day: today, quality: quality, isCompact: false)
                            }
                        }
                    }

                    commandOverviewColumn(title: l10n.text("Today Time Blocks"), detail: l10n.format("Time blocks %d", today.timeBlocks.count), systemImage: "clock") {
                        if today.timeBlocks.isEmpty {
                            Text(l10n.text("No time blocks today."))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(today.timeBlocks, id: \.id) { item in
                                commandTimeBlockRow(item)
                            }
                        }
                    }

                    commandOverviewColumn(title: l10n.text("Deadline Risk"), detail: l10n.format("Risks %d", commandSnapshot.deadlineRisks.count), systemImage: "exclamationmark.triangle.fill") {
                        if commandSnapshot.deadlineRisks.isEmpty {
                            Text(l10n.text("No risky deadlines in the next 7 days."))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(commandSnapshot.deadlineRisks) { risk in
                                Button {
                                    appState.reveal(.project(risk.project.id))
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(risk.title)
                                                .font(.headline)
                                            Spacer()
                                            Text(risk.deadline.dayLabel(locale: l10n.locale))
                                                .font(.caption)
                                                .foregroundStyle(risk.severity == .high ? .orange : .secondary)
                                        }
                                        Text(risk.detail)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                        if let nextTask = risk.nextTask {
                                            Text(l10n.format("Next task: %@", nextTask.title))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("overview-command-risk-\(risk.project.id.uuidString)")
                            }
                        }
                    }
                }

                scheduleQualityPanel(quality)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        CommandSectionHeader(
                            title: l10n.text("7-Day Schedule Board"),
                            detail: l10n.text("Scroll horizontally to see all 7 days"),
                            systemImage: "calendar.day.timeline.leading"
                        )
                        Spacer()
                        Text(l10n.text("Drag tasks here or use the buttons on each card."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(commandSnapshot.days) { day in
                                commandDayBoard(day, quality: quality)
                                    .frame(width: 340)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("overview-command-board-scroll")
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func scheduleQualityPanel(_ quality: ScheduleQualitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CommandSectionHeader(
                    title: l10n.text("Schedule Quality"),
                    detail: l10n.text("Repeated schedules stay valid; this panel shows what needs attention."),
                    systemImage: "checkmark.seal"
                )
                Spacer()
                HStack(spacing: 8) {
                    ReadableStatusPill(title: l10n.format("Repeated %d", quality.repeatedTaskCount), systemImage: "arrow.triangle.2.circlepath", tone: quality.repeatedTaskCount > 0 ? .orange : .secondary)
                    ReadableStatusPill(title: l10n.format("Needs Time Block %d", quality.needsTimeBlockCount), systemImage: "clock.badge.exclamationmark", tone: quality.needsTimeBlockCount > 0 ? .red : .secondary)
                    ReadableStatusPill(title: l10n.format("Risk Days %d", quality.riskDayCount), systemImage: "calendar.badge.exclamationmark", tone: quality.riskDayCount > 0 ? .orange : .green)
                }
            }

            if quality.repeatedTasks.isEmpty && quality.needsTimeBlockItems.isEmpty {
                Text(l10n.text("Schedule quality looks executable."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(quality.repeatedTasks) { repeated in
                        scheduleQualityIssueCard(
                            title: repeated.task.title,
                            status: l10n.text("Repeated"),
                            statusTone: .orange,
                            detail: l10n.format("Scheduled on %d days", repeated.scheduledDates.count),
                            metadata: dateListText(repeated.scheduledDates),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .accessibilityIdentifier("overview-quality-repeated-\(repeated.task.id.uuidString)")
                    }

                    ForEach(quality.needsTimeBlockItems) { issue in
                        scheduleQualityIssueCard(
                            title: issue.task.title,
                            status: l10n.text("Needs Time Block"),
                            statusTone: .red,
                            detail: l10n.text("Important focus without time block"),
                            metadata: scheduleQualityReasonText(issue.reason),
                            systemImage: "clock.badge.exclamationmark"
                        )
                        .accessibilityIdentifier("overview-quality-timeblock-\(issue.id)")
                    }
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview-schedule-quality")
    }

    private func scheduleQualityIssueCard(title: String, status: String, statusTone: Color, detail: String, metadata: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Label(status, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTone)
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 8)
            }
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(metadata)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(statusTone.opacity(0.22))
        }
        .accessibilityElement(children: .combine)
    }

    private func commandDayBoard(_ day: CommandDaySnapshot, quality: ScheduleQualitySnapshot) -> some View {
        let dayQuality = quality.day(on: day.date) ?? ScheduleQualityDaySnapshot(
            id: day.id,
            date: day.date,
            repeatedFocusCount: 0,
            needsTimeBlockCount: 0,
            timeBlockCount: day.timeBlocks.count
        )

        return ReadableDayColumn(
            title: day.date.dayLabel(locale: l10n.locale),
            countTitle: l10n.format("Total Focus %d", day.focusItems.count),
            statusTitle: l10n.text("All items shown")
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                ReadableStatusPill(title: l10n.format("Repeated %d", dayQuality.repeatedFocusCount), systemImage: "arrow.triangle.2.circlepath", tone: dayQuality.repeatedFocusCount > 0 ? .orange : .secondary)
                ReadableStatusPill(title: l10n.format("Needs Time Block %d", dayQuality.needsTimeBlockCount), systemImage: "clock.badge.exclamationmark", tone: dayQuality.needsTimeBlockCount > 0 ? .red : .secondary)
                ReadableStatusPill(title: l10n.format("Scheduled Time Blocks %d", dayQuality.timeBlockCount), systemImage: "clock", tone: .secondary)
                ReadableStatusPill(title: l10n.format("Risks %d", day.deadlineRisks.count), systemImage: "exclamationmark.triangle", tone: day.deadlineRisks.isEmpty ? .secondary : .orange)
            }

            if day.focusItems.isEmpty {
                Text(l10n.text("Drop tasks here"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                ForEach(day.focusItems) { item in
                    commandFocusCard(item, day: day, quality: quality, isCompact: true)
                }
            }
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleScheduleDrop(providers, on: day.date)
        }
        .accessibilityIdentifier("overview-command-day-\(day.id)")
    }

    private func commandFocusCard(_ item: CommandFocusItem, day: CommandDaySnapshot, quality: ScheduleQualitySnapshot, isCompact: Bool) -> some View {
        let repeated = item.task.flatMap { quality.repeatedTask(for: $0.id) }
        let timeBlockIssue = item.task.flatMap { quality.needsTimeBlockIssue(for: $0.id, on: day.date) }
        let actionColumns = [
            GridItem(.flexible(minimum: 126), spacing: 8),
            GridItem(.flexible(minimum: 126), spacing: 8)
        ]

        return ReadableTaskCard(
            title: item.title,
            statusTitle: item.source == .manual ? l10n.text("Manual plan") : l10n.text("Suggested plan"),
            statusTone: item.source == .manual ? .blue : .secondary,
            accessibilityLabel: item.title
        ) {
                if let projectTitle = item.projectTitle, projectTitle.isEmpty == false {
                    CommandMetadataRow(label: l10n.text("Project"), value: projectTitle, systemImage: "folder")
                }
                if let dueDate = item.dueDate {
                    CommandMetadataRow(label: l10n.text("Due"), value: dueDate.shortLabel(locale: l10n.locale), systemImage: "calendar.badge.clock")
                }
                if let priority = item.priority {
                    CommandMetadataRow(label: l10n.text("Priority"), value: priority.localizedTitle(in: l10n.language), systemImage: "flag")
                }
                if item.projectTitle == nil, item.dueDate == nil, item.priority == nil, item.detail.isEmpty == false {
                    CommandMetadataRow(label: l10n.text("Source"), value: item.detail, systemImage: "info.circle")
                }
                if let repeated {
                    CommandMetadataRow(label: l10n.text("Repeated"), value: l10n.format("Scheduled on %d days", repeated.scheduledDates.count), systemImage: "arrow.triangle.2.circlepath")
                    CommandMetadataRow(label: l10n.text("Duplicate Dates"), value: dateListText(repeated.scheduledDates), systemImage: "calendar")
                }
                if let timeBlockIssue {
                    CommandMetadataRow(label: l10n.text("Needs Time Block"), value: scheduleQualityReasonText(timeBlockIssue.reason), systemImage: "clock.badge.exclamationmark")
                    Text(l10n.text("Important focus without time block"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isCompact == false, item.detail.isEmpty == false {
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } actions: {
            LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                if let task = item.task {
                    ReadableActionButton(title: l10n.text("Open Task")) {
                        appState.reveal(.task(task.id))
                    }
                    .accessibilityIdentifier("overview-command-open-\(task.id.uuidString)")

                    ReadableActionButton(title: l10n.text("Done")) {
                        _ = try? LifeOSRepository(context: modelContext).toggleTask(task)
                    }
                    .accessibilityIdentifier("overview-command-done-\(task.id.uuidString)")

                    ReadableActionButton(title: l10n.text("Create Time Block")) {
                        schedulingKind = .timeBlock
                        schedulingTask = task
                    }
                    .accessibilityIdentifier("overview-command-timeblock-task-\(task.id.uuidString)")

                    if let repeated {
                        Menu {
                            ForEach(repeated.scheduledDates, id: \.self) { date in
                                Text(date.dayLabel(locale: l10n.locale))
                            }
                        } label: {
                            Text(l10n.text("Duplicate Dates"))
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .menuStyle(.borderlessButton)
                        .controlSize(.small)
                        .accessibilityIdentifier("overview-command-duplicate-dates-\(task.id.uuidString)")
                    }
                }

                ReadableActionButton(title: l10n.text("Postpone Tomorrow")) {
                    postpone(item)
                }
                .accessibilityIdentifier("overview-command-postpone-\(item.id)")

                if let planItem = item.planItem {
                    ReadableActionButton(title: l10n.text("Unschedule")) {
                        _ = try? LifeOSRepository(context: modelContext).unscheduleDailyPlanItem(planItem)
                    }
                    .accessibilityIdentifier("overview-command-unschedule-\(planItem.id.uuidString)")

                    Menu(l10n.text("More")) {
                        Button(l10n.text("Move Up")) {
                            reorder(planItem, by: -1)
                        }
                        Button(l10n.text("Move Down")) {
                            reorder(planItem, by: 1)
                        }
                    }
                    .accessibilityIdentifier("overview-command-more-\(planItem.id.uuidString)")
                }
            }
        }
        .onDrag {
            NSItemProvider(object: (dragPayload(for: item) ?? "") as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleScheduleDrop(providers, on: day.date, before: item.planItem?.id)
        }
        .accessibilityElement(children: .contain)
    }

    private func commandTimeBlockRow(_ item: CommandTimeBlockItem) -> some View {
        ReadableTimeBlockCard(
            title: item.title,
            timeRange: timeRangeText(start: item.calendarItem.startDate, end: item.calendarItem.endDate),
            projectLabel: l10n.text("Project"),
            projectTitle: item.calendarItem.project?.title,
            sourceTitle: item.isTaskSchedule ? l10n.text("Task time block") : l10n.text("Calendar event"),
            sourceTone: item.isTaskSchedule ? .blue : .secondary
        ) {
            HStack(spacing: 8) {
                ReadableActionButton(title: l10n.text("Open")) {
                    appState.reveal(.calendar(item.calendarItem.id))
                }
                .accessibilityIdentifier("overview-command-open-timeblock-\(item.calendarItem.id.uuidString)")

                if let planItem = item.planItem {
                    ReadableActionButton(title: l10n.text("Unschedule Task Only")) {
                        _ = try? LifeOSRepository(context: modelContext).unscheduleDailyPlanItem(planItem)
                    }
                    .accessibilityIdentifier("overview-command-unschedule-timeblock-\(planItem.id.uuidString)")
                }
            }
        }
        .accessibilityIdentifier("overview-command-timeblock-\(item.calendarItem.id.uuidString)")
    }

    private func dragPayload(for item: CommandFocusItem) -> String? {
        if let planItem = item.planItem {
            return ScheduleDragPayload.dailyPlanPayload(planItem.id)
        }
        if let task = item.task {
            return ScheduleDragPayload.taskPayload(task.id)
        }
        return nil
    }

    private func handleScheduleDrop(_ providers: [NSItemProvider], on date: Date, before targetID: UUID? = nil) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            let rawValue = (object as? String) ?? (object as? NSString).map(String.init)
            guard let rawValue else { return }
            Task { @MainActor in
                applySchedulePayload(rawValue, on: date, before: targetID)
            }
        }
        return true
    }

    private func applySchedulePayload(_ rawValue: String, on date: Date, before targetID: UUID? = nil) {
        guard let payload = ScheduleDragPayload(rawValue) else { return }
        let repository = LifeOSRepository(context: modelContext)
        switch payload {
        case .task(let id):
            guard let task = tasks.first(where: { $0.id == id }) else { return }
            _ = try? repository.scheduleTask(task, kind: .focus, plannedDate: date)
        case .dailyPlan(let id):
            guard let planItem = dailyPlanItems.first(where: { $0.id == id }) else { return }
            let target = targetID.flatMap { id in dailyPlanItems.first(where: { $0.id == id }) }
            _ = try? repository.moveDailyPlanItem(planItem, to: date, before: target)
        }
    }

    private func postpone(_ item: CommandFocusItem) {
        let repository = LifeOSRepository(context: modelContext)
        if let planItem = item.planItem {
            _ = try? repository.postponeDailyPlanItem(planItem)
        } else if let task = item.task,
                  let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date.now) {
            _ = try? repository.scheduleTask(task, kind: .focus, plannedDate: tomorrow)
        }
    }

    private func reorder(_ planItem: DailyPlanItem, by offset: Int) {
        let sameDay = dailyPlanItems
            .filter { $0.kind == planItem.kind && Calendar.current.isDate($0.plannedDate, inSameDayAs: planItem.plannedDate) }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
        guard let index = sameDay.firstIndex(where: { $0.id == planItem.id }) else { return }
        _ = try? LifeOSRepository(context: modelContext).reorderDailyPlanItem(planItem, toIndex: index + offset)
    }

    private func overviewColumn<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func commandOverviewColumn<Content: View>(title: String, detail: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CommandSectionHeader(title: title, detail: detail, systemImage: systemImage)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }

    private func moneySignalRow(label: String, value: String, tone: Color) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tone)
        }
    }
}

private struct CommandSectionHeader: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

private struct ReadableDayColumn<Content: View>: View {
    let title: String
    let countTitle: String
    let statusTitle: String
    let content: Content

    init(
        title: String,
        countTitle: String,
        statusTitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.countTitle = countTitle
        self.statusTitle = statusTitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ReadableStatusPill(title: countTitle, systemImage: "checklist", tone: .blue)
                    ReadableStatusPill(title: statusTitle, systemImage: "checkmark.circle", tone: .green)
                }
            }

            Divider()

            content
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(countTitle), \(statusTitle)")
    }
}

private struct ReadableTaskCard<Metadata: View, Actions: View>: View {
    let title: String
    let statusTitle: String
    let statusTone: Color
    let accessibilityLabel: String
    let metadata: Metadata
    let actions: Actions

    init(
        title: String,
        statusTitle: String,
        statusTone: Color,
        accessibilityLabel: String,
        @ViewBuilder metadata: () -> Metadata,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.statusTitle = statusTitle
        self.statusTone = statusTone
        self.accessibilityLabel = accessibilityLabel
        self.metadata = metadata()
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                ReadableStatusPill(title: statusTitle, systemImage: nil, tone: statusTone)
            }

            VStack(alignment: .leading, spacing: 6) {
                metadata
            }

            Divider()

            actions
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ReadableTimeBlockCard<Actions: View>: View {
    let title: String
    let timeRange: String
    let projectLabel: String
    let projectTitle: String?
    let sourceTitle: String
    let sourceTone: Color
    let actions: Actions

    init(
        title: String,
        timeRange: String,
        projectLabel: String,
        projectTitle: String?,
        sourceTitle: String,
        sourceTone: Color,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.timeRange = timeRange
        self.projectLabel = projectLabel
        self.projectTitle = projectTitle
        self.sourceTitle = sourceTitle
        self.sourceTone = sourceTone
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ReadableStatusPill(title: timeRange, systemImage: "clock", tone: .blue)
                        ReadableStatusPill(title: sourceTitle, systemImage: "calendar", tone: sourceTone)
                    }
                }
                Spacer(minLength: 8)
            }

            if let projectTitle, projectTitle.isEmpty == false {
                CommandMetadataRow(label: projectLabel, value: projectTitle, systemImage: "folder")
            }

            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel([title, timeRange, projectTitle, sourceTitle].compactMap { $0 }.joined(separator: ", "))
    }
}

private struct ReadableStatusPill: View {
    let title: String
    let systemImage: String?
    let tone: Color

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(tone)
        .background(tone.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tone.opacity(0.24))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

private struct CommandMetadataRow: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
                .accessibilityHidden(true)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct ReadableActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.horizontal, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(title)
    }
}

struct LedgerWorkspaceView: View {
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\LedgerEntry.occurredOn, order: .reverse)]) private var ledgerEntries: [LedgerEntry]

    private var filteredEntries: [LedgerEntry] {
        ledgerEntries.filter {
            workspaceSearchMatches(appState.trimmedSearchText, fields: [$0.title, $0.note, $0.account?.name, $0.category?.name, $0.project?.title])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: l10n.text("Ledger"), detail: workspaceDetailText(base: l10n.text("Actual cash movement only. Use this when money already moved."), query: appState.trimmedSearchText, resultCount: filteredEntries.count, itemNoun: l10n.text("ledger entries"), language: l10n.language), buttonTitle: l10n.text("New Ledger Entry"), action: {
                    appState.open(.ledger)
                }, accessibilityID: "section-ledger-header")
                .accessibilityIdentifier("section-ledger-header")

                if appState.isSearching {
                    WorkspaceSearchBanner(query: appState.trimmedSearchText, resultCount: filteredEntries.count, itemNoun: l10n.text("ledger entries")) {
                        appState.clearSearch()
                    }
                }

                if ledgerEntries.isEmpty {
                    EmptyStateView(title: l10n.text("No ledger entries yet"), detail: l10n.text("Use the toolbar or this section to record actual income and expense."), buttonTitle: l10n.text("New Ledger Entry")) {
                        appState.open(.ledger)
                    }
                    .frame(height: 300)
                } else if filteredEntries.isEmpty {
                    EmptyStateView(title: l10n.text("No ledger entries matched"), detail: l10n.text("Try a different keyword or clear the current search."), buttonTitle: l10n.text("Clear Search"), action: appState.clearSearch)
                        .frame(height: 300)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredEntries, id: \.id) { entry in
                            Button {
                                appState.reveal(.ledger(entry.id))
                            } label: {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(entry.title)
                                            .font(.headline)
                                        Text([entry.account?.name, entry.category?.name, entry.project?.title, entry.occurredOn.dayLabel(locale: l10n.locale)].compactMap { $0 }.joined(separator: " · "))
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text((entry.direction == .expense ? -entry.amount : entry.amount).currencyString)
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(entry.direction == .income ? .green : .red)
                                }
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ledger-row-\(entry.id.uuidString)")
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

struct PlannedWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\PlannedEntry.dueOn, order: .forward)]) private var plannedEntries: [PlannedEntry]

    private var filteredEntries: [PlannedEntry] {
        plannedEntries.filter {
            workspaceSearchMatches(appState.trimmedSearchText, fields: [$0.title, $0.note, $0.account?.name, $0.category?.name, $0.project?.title])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: l10n.text("Planned"), detail: workspaceDetailText(base: l10n.text("Future money that has not happened yet."), query: appState.trimmedSearchText, resultCount: filteredEntries.count, itemNoun: l10n.text("planned entries"), language: l10n.language), buttonTitle: l10n.text("New Planned Entry"), action: {
                    appState.open(.planned)
                }, accessibilityID: "section-planned-header")

                if appState.isSearching {
                    WorkspaceSearchBanner(query: appState.trimmedSearchText, resultCount: filteredEntries.count, itemNoun: l10n.text("planned entries")) {
                        appState.clearSearch()
                    }
                }

                if plannedEntries.isEmpty {
                    EmptyStateView(title: l10n.text("No planned entries yet"), detail: l10n.text("Planned entries become your next 30 day forecast."), buttonTitle: l10n.text("New Planned Entry")) {
                        appState.open(.planned)
                    }
                    .frame(height: 300)
                } else if filteredEntries.isEmpty {
                    EmptyStateView(title: l10n.text("No planned entries matched"), detail: l10n.text("Try a different keyword or clear the current search."), buttonTitle: l10n.text("Clear Search"), action: appState.clearSearch)
                        .frame(height: 300)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredEntries, id: \.id) { entry in
                            HStack(spacing: 16) {
                                Button {
                                    appState.reveal(.planned(entry.id))
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(entry.title)
                                            .font(.headline)
                                        Text([entry.account?.name, entry.category?.name, entry.project?.title, entry.dueOn.shortLabel(locale: l10n.locale)].compactMap { $0 }.joined(separator: " · "))
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("planned-row-\(entry.id.uuidString)")

                                Text((entry.direction == .expense ? -entry.amount : entry.amount).currencyString)
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(entry.direction == .income ? .green : .orange)

                                Button(l10n.text("Settle")) {
                                    _ = try? LifeOSRepository(context: modelContext).settle(entry)
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("planned-settle-\(entry.id.uuidString)")
                            }
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

struct AssetsWorkspaceView: View {
    @State private var showingForm = false
    @Environment(LifeOSAppState.self) private var appState
    @Environment(MarketQuoteStore.self) private var marketQuoteStore
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\AssetSnapshot.capturedOn, order: .reverse)]) private var snapshots: [AssetSnapshot]
    private let quoteRefreshTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    private var filteredSnapshots: [AssetSnapshot] {
        snapshots.filter {
            workspaceSearchMatches(appState.trimmedSearchText, fields: [$0.title, $0.note, $0.account?.name, $0.category?.name])
        }
    }

    private var trackedSnapshots: [AssetSnapshot] {
        filteredSnapshots.filter(\.usesLiveMarketQuote)
    }

    private var marketSummary: MarketQuoteSummary {
        marketQuoteStore.marketSummary(for: filteredSnapshots)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: l10n.text("Assets"), detail: workspaceDetailText(base: l10n.text("Track the latest snapshot for positions you care about."), query: appState.trimmedSearchText, resultCount: filteredSnapshots.count, itemNoun: l10n.text("asset snapshots"), language: l10n.language), buttonTitle: l10n.text("New Asset Snapshot"), action: {
                    showingForm = true
                }, accessibilityID: "section-assets-header")

                if appState.isSearching {
                    WorkspaceSearchBanner(query: appState.trimmedSearchText, resultCount: filteredSnapshots.count, itemNoun: l10n.text("asset snapshots")) {
                        appState.clearSearch()
                    }
                }

                if trackedSnapshots.isEmpty == false {
                    liveQuoteStatusPanel
                }

                if snapshots.isEmpty {
                    EmptyStateView(title: l10n.text("No asset snapshots yet"), detail: l10n.text("Create a snapshot when you want to track current balance or investment value."), buttonTitle: l10n.text("New Asset Snapshot")) {
                        showingForm = true
                    }
                    .frame(height: 300)
                } else if filteredSnapshots.isEmpty {
                    EmptyStateView(title: l10n.text("No asset snapshots matched"), detail: l10n.text("Try a different keyword or clear the current search."), buttonTitle: l10n.text("Clear Search"), action: appState.clearSearch)
                        .frame(height: 300)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredSnapshots, id: \.id) { snapshot in
                            Button {
                                appState.reveal(.asset(snapshot.id))
                            } label: {
                                assetSnapshotRow(snapshot)
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("asset-row-\(snapshot.id.uuidString)")
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingForm) {
            AssetSnapshotFormSheet()
                .environment(appState)
        }
        .task(id: trackedSnapshots.map { "\($0.id.uuidString):\($0.normalizedQuoteSymbol ?? "-"):\($0.units?.plainNumberString ?? "-")" }.joined(separator: "|")) {
            await marketQuoteStore.refresh(for: trackedSnapshots)
        }
        .onReceive(quoteRefreshTimer) { _ in
            guard appState.activeSection == .assets, trackedSnapshots.isEmpty == false else { return }
            Task { await marketQuoteStore.refresh(for: trackedSnapshots) }
        }
    }

    private var liveQuoteStatusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.text("Taiwan Live Quotes"))
                        .font(.title3.weight(.semibold))
                    Text(l10n.text("Public TWSE quote refresh for tracked holdings such as 2330."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if marketSummary.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(l10n.text("Refresh Now")) {
                    Task { await marketQuoteStore.refresh(for: trackedSnapshots, force: true) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("assets-refresh-live-quotes")
            }

            HStack {
                metricPill(label: l10n.text("Tracked"), value: "\(marketSummary.trackedCount)")
                metricPill(label: l10n.text("Live Value"), value: marketSummary.liveValue.currencyString)
                metricPill(label: l10n.text("Unrealized"), value: marketSummary.unrealizedProfit.currencyString, tone: marketSummary.unrealizedProfit >= 0 ? .green : .red)
                metricPill(label: l10n.text("Day Change"), value: marketSummary.dayChangeValue.signedCurrencyString, tone: marketSummary.dayChangeValue >= 0 ? .green : .red)
            }

            if let lastRefreshAt = marketSummary.lastRefreshAt {
                Text(l10n.format("Last refresh: %@", lastRefreshAt.formatted(date: .omitted, time: .standard)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let lastError = marketSummary.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func assetSnapshotRow(_ snapshot: AssetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.title)
                    .font(.headline)
                Text([snapshot.account?.name, snapshot.category?.name, snapshot.capturedOn.dayLabel(locale: l10n.locale)].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let symbol = snapshot.normalizedQuoteSymbol {
                    Text(symbol + (snapshot.trackedUnits.map { " · \($0.plainNumberString) \(l10n.text("shares"))" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(marketQuoteStore.displayValue(for: snapshot).currencyString)
                    .font(.headline.monospacedDigit())
                if let quote = marketQuoteStore.quote(for: snapshot), let units = snapshot.trackedUnits {
                    Text("\(quote.lastPrice.quotePriceString) × \(units.plainNumberString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let dayChangeValue = marketQuoteStore.positionDayChangeValue(for: snapshot) {
                        Text(l10n.format("Day %@", dayChangeValue.signedCurrencyString) + (marketQuoteStore.dayChangePercent(for: snapshot).map { " · \($0.signedPercentDisplayString)" } ?? ""))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(dayChangeValue >= 0 ? .green : .red)
                    }
                    if let profit = marketQuoteStore.unrealizedProfit(for: snapshot) {
                        Text(profit.currencyString + (marketQuoteStore.unrealizedReturn(for: snapshot).map { " · \($0.percentDisplayString)" } ?? ""))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(profit >= 0 ? .green : .red)
                    }
                } else {
                    Text(l10n.text("Snapshot value"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metricPill(label: String, value: String, tone: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tone)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TasksWorkspaceView: View {
    @State private var schedulingTask: TaskItem?
    @State private var schedulingKind: DailyPlanItemKind = .focus
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n
    @Query private var tasks: [TaskItem]

    private var sortedTasks: [TaskItem] {
        tasks.sorted {
            if $0.status != $1.status {
                return $0.status != .done
            }
            if $0.priority.rank != $1.priority.rank {
                return $0.priority.rank < $1.priority.rank
            }
            return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }

    private var filteredTasks: [TaskItem] {
        sortedTasks.filter {
            workspaceSearchMatches(appState.trimmedSearchText, fields: [$0.title, $0.note, $0.priority.rawValue, $0.status.rawValue, $0.project?.title])
        }
    }

    private var groupedFilteredTasks: [(title: String, tasks: [TaskItem])] {
        Dictionary(grouping: filteredTasks) { task in
            task.project?.title ?? l10n.text("No linked project")
        }
        .map { (title: $0.key, tasks: $0.value) }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: l10n.text("Tasks"), detail: workspaceDetailText(base: l10n.text("Use tasks for next actions, not vague intentions."), query: appState.trimmedSearchText, resultCount: filteredTasks.count, itemNoun: l10n.text("tasks"), language: l10n.language), buttonTitle: l10n.text("New Task"), action: {
                    appState.open(.task)
                }, accessibilityID: "section-tasks-header")

                if appState.isSearching {
                    WorkspaceSearchBanner(query: appState.trimmedSearchText, resultCount: filteredTasks.count, itemNoun: l10n.text("tasks")) {
                        appState.clearSearch()
                    }
                }

                if tasks.isEmpty {
                    EmptyStateView(title: l10n.text("No tasks yet"), detail: l10n.text("Tasks power readiness, conflicts, and today focus."), buttonTitle: l10n.text("New Task")) {
                        appState.open(.task)
                    }
                    .frame(height: 300)
                } else if filteredTasks.isEmpty {
                    EmptyStateView(title: l10n.text("No tasks matched"), detail: l10n.text("Try a different keyword or clear the current search."), buttonTitle: l10n.text("Clear Search"), action: appState.clearSearch)
                        .frame(height: 300)
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groupedFilteredTasks, id: \.title) { group in
                            Text(l10n.format("Project: %@", group.title))
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            ForEach(group.tasks, id: \.id) { task in
                                HStack(spacing: 12) {
                                    Button {
                                        appState.reveal(.task(task.id))
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(task.title)
                                                .font(.headline)
                                            Text([task.dueDate?.shortLabel(locale: l10n.locale), task.priority.localizedTitle(in: l10n.language)].compactMap { $0 }.joined(separator: " · "))
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("task-row-\(task.id.uuidString)")

                                    Button(l10n.text("Plan Focus")) {
                                        schedulingKind = .focus
                                        schedulingTask = task
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("task-plan-focus-\(task.id.uuidString)")

                                    Button(l10n.text("Time Block")) {
                                        schedulingKind = .timeBlock
                                        schedulingTask = task
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("task-plan-timeblock-\(task.id.uuidString)")

                                    Button(task.status == .done ? l10n.text("Reopen") : l10n.text("Done")) {
                                        _ = try? LifeOSRepository(context: modelContext).toggleTask(task)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("task-toggle-\(task.id.uuidString)")
                                }
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .onDrag {
                                    NSItemProvider(object: ScheduleDragPayload.taskPayload(task.id) as NSString)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: Binding(
            get: { schedulingTask != nil },
            set: { isPresented in
                if isPresented == false {
                    schedulingTask = nil
                }
            }
        )) {
            if let schedulingTask {
                TaskScheduleSheet(task: schedulingTask, initialKind: schedulingKind)
                    .environment(appState)
            }
        }
    }
}

struct CalendarWorkspaceView: View {
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\CalendarItem.startDate, order: .forward)]) private var items: [CalendarItem]

    private var filteredItems: [CalendarItem] {
        items.filter {
            workspaceSearchMatches(appState.trimmedSearchText, fields: [$0.title, $0.location, $0.note, $0.project?.title])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: l10n.text("Calendar"), detail: workspaceDetailText(base: l10n.text("Events create hard time blocks and conflict signals."), query: appState.trimmedSearchText, resultCount: filteredItems.count, itemNoun: l10n.text("calendar items"), language: l10n.language), buttonTitle: l10n.text("New Calendar Item"), action: {
                    appState.open(.calendar)
                }, accessibilityID: "section-calendar-header")

                if appState.isSearching {
                    WorkspaceSearchBanner(query: appState.trimmedSearchText, resultCount: filteredItems.count, itemNoun: l10n.text("calendar items")) {
                        appState.clearSearch()
                    }
                }

                if items.isEmpty {
                    EmptyStateView(title: l10n.text("No calendar items yet"), detail: l10n.text("Create events when time must be reserved, not just remembered."), buttonTitle: l10n.text("New Calendar Item")) {
                        appState.open(.calendar)
                    }
                    .frame(height: 300)
                } else if filteredItems.isEmpty {
                    EmptyStateView(title: l10n.text("No calendar items matched"), detail: l10n.text("Try a different keyword or clear the current search."), buttonTitle: l10n.text("Clear Search"), action: appState.clearSearch)
                        .frame(height: 300)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredItems, id: \.id) { item in
                            Button {
                                appState.reveal(.calendar(item.id))
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text([item.project?.title, item.startDate.shortLabel(locale: l10n.locale), item.location.isEmpty ? nil : item.location].compactMap { $0 }.joined(separator: " · "))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("calendar-row-\(item.id.uuidString)")
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

struct GoalsWorkspaceView: View {
    @State private var showingForm = false
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\Goal.createdAt, order: .forward)]) private var goals: [Goal]

    private var filteredGoals: [Goal] {
        goals.filter {
            workspaceSearchMatches(appState.trimmedSearchText, fields: [$0.title, $0.summary, $0.state.rawValue])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: l10n.text("Goals"), detail: workspaceDetailText(base: l10n.text("Goals define where the system is trying to take you."), query: appState.trimmedSearchText, resultCount: filteredGoals.count, itemNoun: l10n.text("goals"), language: l10n.language), buttonTitle: l10n.text("New Goal"), action: {
                    showingForm = true
                }, accessibilityID: "section-goals-header")

                if appState.isSearching {
                    WorkspaceSearchBanner(query: appState.trimmedSearchText, resultCount: filteredGoals.count, itemNoun: l10n.text("goals")) {
                        appState.clearSearch()
                    }
                }

                if goals.isEmpty {
                    EmptyStateView(title: l10n.text("No goals yet"), detail: l10n.text("Create a goal before you create too many disconnected projects."), buttonTitle: l10n.text("New Goal")) {
                        showingForm = true
                    }
                    .frame(height: 300)
                } else if filteredGoals.isEmpty {
                    EmptyStateView(title: l10n.text("No goals matched"), detail: l10n.text("Try a different keyword or clear the current search."), buttonTitle: l10n.text("Clear Search"), action: appState.clearSearch)
                        .frame(height: 300)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredGoals, id: \.id) { goal in
                            Button {
                                appState.reveal(.goal(goal.id))
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(goal.title)
                                        .font(.headline)
                                    Text(goal.summary)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                    Text(goal.targetDate?.dayLabel(locale: l10n.locale) ?? l10n.text("No target date"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("goal-row-\(goal.id.uuidString)")
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingForm) {
            GoalFormSheet()
                .environment(appState)
        }
    }
}

struct ProjectsWorkspaceView: View {
    @State private var showingForm = false
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n
    @Query private var projects: [Project]
    @Query private var tasks: [TaskItem]

    private var filteredProjects: [Project] {
        projects.filter {
            workspaceSearchMatches(appState.trimmedSearchText, fields: [$0.title, $0.summary, $0.note, $0.state.rawValue, $0.goal?.title])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: l10n.text("Projects"), detail: workspaceDetailText(base: l10n.text("Projects connect money, tasks, and calendar blocks into a working line."), query: appState.trimmedSearchText, resultCount: filteredProjects.count, itemNoun: l10n.text("projects"), language: l10n.language), buttonTitle: l10n.text("New Project"), action: {
                    showingForm = true
                }, accessibilityID: "section-projects-header")

                if appState.isSearching {
                    WorkspaceSearchBanner(query: appState.trimmedSearchText, resultCount: filteredProjects.count, itemNoun: l10n.text("projects")) {
                        appState.clearSearch()
                    }
                }

                if projects.isEmpty {
                    EmptyStateView(title: l10n.text("No projects yet"), detail: l10n.text("Projects are where goals become something the week can actually carry."), buttonTitle: l10n.text("New Project")) {
                        showingForm = true
                    }
                    .frame(height: 300)
                } else if filteredProjects.isEmpty {
                    EmptyStateView(title: l10n.text("No projects matched"), detail: l10n.text("Try a different keyword or clear the current search."), buttonTitle: l10n.text("Clear Search"), action: appState.clearSearch)
                        .frame(height: 300)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredProjects, id: \.id) { project in
                            let projectTasks = tasks.filter { $0.project?.id == project.id }
                            let openTasks = projectTasks.filter { $0.status != .done }
                            let openTaskCount = openTasks.count
                            let completedTaskCount = projectTasks.count - openTaskCount
                            let readiness = projectTasks.isEmpty ? 0 : Int((Double(completedTaskCount) / Double(projectTasks.count)) * 100)
                            let nextOpenTask = openTasks.sorted {
                                if $0.priority.rank != $1.priority.rank {
                                    return $0.priority.rank < $1.priority.rank
                                }
                                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
                            }.first
                            Button {
                                appState.reveal(.project(project.id))
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(project.title)
                                                .font(.headline)
                                            Text(project.summary)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                            Text(nextOpenTask.map { l10n.format("Next task: %@", $0.title) } ?? l10n.text("No open tasks"))
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        Text("\(readiness)%")
                                            .font(.headline.monospacedDigit())
                                    }
                                    ProgressView(value: Double(readiness), total: 100)
                                    HStack {
                                        Text([project.goal?.title, project.deadline?.dayLabel(locale: l10n.locale) ?? l10n.text("No deadline")].compactMap { $0 }.joined(separator: " · "))
                                        Spacer()
                                        Text(l10n.format("Open tasks: %d", openTaskCount))
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("project-row-\(project.id.uuidString)")
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingForm) {
            ProjectFormSheet()
                .environment(appState)
        }
    }
}

struct SettingsWorkspaceView: View {
    @State private var showingAccountForm = false
    @State private var showingCategoryForm = false
    @State private var personalPlanInstallSummary: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(LocalizationStore.self) private var l10n
    @Query(sort: [SortDescriptor(\Account.createdAt, order: .forward)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\LifeOSCore.Category.createdAt, order: .forward)]) private var categories: [LifeOSCore.Category]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeader(title: l10n.text("Settings"), detail: l10n.text("Manage supporting entities and starter template tools."), buttonTitle: nil, action: nil, accessibilityID: "section-settings-header")

                VStack(alignment: .leading, spacing: 12) {
                    Text(l10n.text("Starter Template"))
                        .font(.title3.weight(.semibold))
                    Text(l10n.text("Install a small local template if you want accounts, categories, a goal, and a couple of starter records."))
                        .foregroundStyle(.secondary)
                    Button(l10n.text("Install Starter Template")) {
                        _ = try? StarterTemplateService.installIfPossible(context: modelContext, language: l10n.language)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("settings-install-template")
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text(l10n.text("Personal Plan Template"))
                        .font(.title3.weight(.semibold))
                    Text(l10n.text("Install goals, projects, tasks, and calendar blocks for competitions, Demo Trip travel, earning, 2330, Skill Certification L1, Seasonal work, and the academic path."))
                        .foregroundStyle(.secondary)
                    Button(l10n.text("Install Personal Plan Template")) {
                        installPersonalPlanTemplate()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("settings-install-personal-plan-template")

                    if let personalPlanInstallSummary {
                        Text(personalPlanInstallSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings-personal-plan-template-result")
                    }
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text(l10n.text("Language"))
                        .font(.title3.weight(.semibold))
                    Text(l10n.text("Switch between English and Traditional Chinese without restarting the app."))
                        .foregroundStyle(.secondary)
                    Picker(l10n.text("Language"), selection: Binding(
                        get: { l10n.language },
                        set: { l10n.language = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeDisplayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings-language-picker")
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(alignment: .top, spacing: 18) {
                    settingsColumn(title: l10n.text("Accounts"), buttonTitle: l10n.text("New Account")) {
                        showingAccountForm = true
                    } content: {
                        if accounts.isEmpty {
                            Text(l10n.text("No accounts yet."))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(accounts, id: \.id) { account in
                                Text("\(account.name) · \(account.kind.localizedTitle(in: l10n.language))")
                            }
                        }
                    }

                    settingsColumn(title: l10n.text("Categories"), buttonTitle: l10n.text("New Category")) {
                        showingCategoryForm = true
                    } content: {
                        if categories.isEmpty {
                            Text(l10n.text("No categories yet."))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(categories, id: \.id) { category in
                                Text("\(category.name) · \(category.scope.localizedTitle(in: l10n.language))")
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingAccountForm) {
            AccountFormSheet()
        }
        .sheet(isPresented: $showingCategoryForm) {
            CategoryFormSheet()
        }
    }

    private func settingsColumn<Content: View>(title: String, buttonTitle: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func installPersonalPlanTemplate() {
        do {
            let result = try PersonalPlanTemplateService.installIfPossible(context: modelContext)
            personalPlanInstallSummary = l10n.format("Personal plan template updated: %d added, %d skipped.", result.totalAdded, result.totalSkipped)
        } catch {
            personalPlanInstallSummary = l10n.text("Personal plan template failed. Check logs and try again.")
        }
    }
}
