import SwiftData
import XCTest
@testable import LifeOSCore

@MainActor
final class LifeOSCoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repository: LifeOSRepository!

    override func setUpWithError() throws {
        container = try LifeOSModelContainer.shared(inMemoryOnly: true)
        context = ModelContext(container)
        repository = LifeOSRepository(context: context)
    }

    override func tearDownWithError() throws {
        repository = nil
        context = nil
        container = nil
    }

    func testLedgerPlannedAndAssetCrud() throws {
        let account = try repository.createAccount(name: "Cash", kind: .cash)
        let incomeCategory = try repository.createCategory(name: "Part-time Work", scope: .income)
        let expenseCategory = try repository.createCategory(name: "Travel", scope: .expense)
        let assetCategory = try repository.createCategory(name: "Investments", scope: .asset)

        let ledger = try repository.createLedgerEntry(
            title: "Part-time Work",
            direction: .income,
            amount: 1200,
            occurredOn: .now,
            account: account,
            category: incomeCategory,
            project: nil
        )
        let planned = try repository.createPlannedEntry(
            title: "Demo Trip flight",
            direction: .expense,
            amount: 7500,
            dueOn: .now.addingTimeInterval(60 * 60 * 24 * 7),
            account: account,
            category: expenseCategory,
            project: nil
        )
        let asset = try repository.createAssetSnapshot(
            title: "2330",
            amount: 12345,
            capturedOn: .now,
            account: account,
            category: assetCategory
        )

        XCTAssertEqual(ledger.title, "Part-time Work")
        XCTAssertEqual(planned.direction, .expense)
        XCTAssertEqual(asset.amount, 12345)

        try repository.delete(asset)
        let assets = try context.fetch(FetchDescriptor<AssetSnapshot>())
        XCTAssertTrue(assets.isEmpty)
    }

    func testSettlingPlannedEntryCreatesLedgerEntry() throws {
        let account = try repository.createAccount(name: "Bank", kind: .bank)
        let category = try repository.createCategory(name: "Trip", scope: .expense)
        let planned = try repository.createPlannedEntry(
            title: "Hotel",
            direction: .expense,
            amount: 4200,
            dueOn: .now,
            account: account,
            category: category,
            project: nil
        )

        _ = try repository.settle(planned)

        let plannedAfter = try context.fetch(FetchDescriptor<PlannedEntry>())
        let ledgerAfter = try context.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertTrue(plannedAfter.isEmpty)
        XCTAssertEqual(ledgerAfter.count, 1)
        XCTAssertEqual(ledgerAfter.first?.title, "Hotel")
    }

    func testOverviewSnapshotAggregatesCashflowAndConflicts() throws {
        let goal = try repository.createGoal(title: "Stabilize cashflow", summary: "Keep income and spend visible.", targetDate: .now)
        let project = try repository.createProject(title: "Part-time Work line", summary: "Weekly partTime work.", deadline: .now.addingTimeInterval(60 * 60 * 24 * 5), goal: goal)
        let account = try repository.createAccount(name: "Cash", kind: .cash)
        let investmentAccount = try repository.createAccount(name: "Brokerage", kind: .investment)
        let incomeCategory = try repository.createCategory(name: "Part-time Work", scope: .income)
        let expenseCategory = try repository.createCategory(name: "Travel", scope: .expense)
        let assetCategory = try repository.createCategory(name: "Investments", scope: .asset)

        _ = try repository.createLedgerEntry(title: "Lesson", direction: .income, amount: 1200, occurredOn: .now, account: account, category: incomeCategory, project: project)
        _ = try repository.createLedgerEntry(title: "Train", direction: .expense, amount: 150, occurredOn: .now, account: account, category: expenseCategory, project: project)
        _ = try repository.createPlannedEntry(title: "Demo Trip trip", direction: .expense, amount: 5000, dueOn: .now.addingTimeInterval(60 * 60 * 24 * 3), account: account, category: expenseCategory, project: project)
        _ = try repository.createAssetSnapshot(title: "2330", amount: 12345, capturedOn: .now, account: investmentAccount, category: assetCategory)
        _ = try repository.createTask(title: "Prepare proposal", dueDate: .now.addingTimeInterval(60 * 60 * 12), priority: .high, project: project)
        _ = try repository.createCalendarItem(title: "Focus block", startDate: .now, endDate: .now.addingTimeInterval(60 * 60), allDay: false, location: "Home", note: "", project: project)
        _ = try repository.createCalendarItem(title: "Overlap block", startDate: .now.addingTimeInterval(60 * 30), endDate: .now.addingTimeInterval(60 * 90), allDay: false, location: "Home", note: "", project: project)

        let snapshot = DashboardEngine.makeOverview(
            accounts: try context.fetch(FetchDescriptor<Account>()),
            ledgerEntries: try context.fetch(FetchDescriptor<LedgerEntry>()),
            plannedEntries: try context.fetch(FetchDescriptor<PlannedEntry>()),
            assetSnapshots: try context.fetch(FetchDescriptor<AssetSnapshot>()),
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: try context.fetch(FetchDescriptor<CalendarItem>()),
            projects: try context.fetch(FetchDescriptor<Project>()),
            referenceDate: .now
        )

        XCTAssertEqual(snapshot.monthIncome, 1200)
        XCTAssertEqual(snapshot.monthExpense, 150)
        XCTAssertEqual(snapshot.monthNet, 1050)
        XCTAssertEqual(snapshot.plannedExpense30Days, 5000)
        XCTAssertEqual(snapshot.assetTotal, 12345)
        XCTAssertEqual(snapshot.liquidBalance, 1050)
        XCTAssertEqual(snapshot.investableAssetTotal, 12345)
        XCTAssertEqual(snapshot.totalWealthSnapshot, 13395)
        XCTAssertEqual(snapshot.freeCashAfterPlanned30Days, -3950)
        XCTAssertEqual(snapshot.projectedLiquidAfter30Days, -3950)
        XCTAssertEqual(snapshot.accountBalances.count, 2)
        XCTAssertFalse(snapshot.conflicts.isEmpty)
        XCTAssertEqual(snapshot.projectStatuses.first?.title, "Part-time Work line")
    }

    func testTaiwanQuoteEnvelopeParses2330Quote() throws {
        let payload = """
        {
          "msgArray": [
            {
              "c": "2330",
              "n": "Demo Equity",
              "z": "85.4000",
              "y": "86.3500",
              "o": "87.6500",
              "h": "88.8000",
              "l": "85.3500",
              "d": "20260423",
              "t": "11:20:44"
            }
          ],
          "rtcode": "0000",
          "rtmessage": "OK"
        }
        """.data(using: .utf8)!

        let envelope = try TaiwanMarketQuoteService.decodeEnvelope(from: payload)

        XCTAssertEqual(envelope.rtcode, "0000")
        XCTAssertEqual(envelope.msgArray.first?.c, "2330")
        XCTAssertEqual(TaiwanMarketQuoteService.decimal(fromMIS: envelope.msgArray.first?.z), Decimal(string: "85.4000"))
        XCTAssertEqual(TaiwanMarketQuoteService.normalizeSymbol(" 2330 "), "2330")
    }

    func testAssetSnapshotSupportsLiveQuoteFields() throws {
        let account = try repository.createAccount(name: "Investment", kind: .investment)
        let assetCategory = try repository.createCategory(name: "ETF", scope: .asset)

        let snapshot = try repository.createAssetSnapshot(
            title: "Demo Equity",
            amount: 12345,
            capturedOn: .now,
            account: account,
            category: assetCategory,
            quoteSymbol: "2330",
            units: 120,
            costBasis: 10000,
            note: "Long-term holding"
        )

        XCTAssertEqual(snapshot.normalizedQuoteSymbol, "2330")
        XCTAssertEqual(snapshot.trackedUnits, 120)
        XCTAssertEqual(snapshot.referenceCostBasis, 10000)
        XCTAssertTrue(snapshot.usesLiveMarketQuote)
    }

    func testPersonalPlanTemplateInstallsCompletePlanAndIsIdempotent() throws {
        let first = try PersonalPlanTemplateService.installIfPossible(context: context)

        XCTAssertEqual(first.addedGoals, 6)
        XCTAssertEqual(first.addedProjects, 8)
        XCTAssertEqual(first.addedTasks, 22)
        XCTAssertEqual(first.addedCalendarItems, 4)
        XCTAssertEqual(first.totalSkipped, 0)

        let goals = try context.fetch(FetchDescriptor<Goal>())
        let projects = try context.fetch(FetchDescriptor<Project>())
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let calendarItems = try context.fetch(FetchDescriptor<CalendarItem>())

        XCTAssertEqual(goals.count, 6)
        XCTAssertEqual(projects.count, 8)
        XCTAssertEqual(tasks.count, 22)
        XCTAssertEqual(calendarItems.count, 4)
        XCTAssertNotNil(projects.first(where: { $0.title == "Product Challenge 初賽" })?.goal)
        XCTAssertTrue(tasks.allSatisfy { $0.project != nil })
        XCTAssertTrue(calendarItems.allSatisfy { $0.project != nil })

        let second = try PersonalPlanTemplateService.installIfPossible(context: context)

        XCTAssertEqual(second.totalAdded, 0)
        XCTAssertEqual(second.addedGoals, 0)
        XCTAssertEqual(second.addedProjects, 0)
        XCTAssertEqual(second.addedTasks, 0)
        XCTAssertEqual(second.addedCalendarItems, 0)
        XCTAssertEqual(second.skippedGoals, 6)
        XCTAssertEqual(second.skippedProjects, 8)
        XCTAssertEqual(second.skippedTasks, 22)
        XCTAssertEqual(second.skippedCalendarItems, 4)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Goal>()).count, 6)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Project>()).count, 8)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).count, 22)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CalendarItem>()).count, 4)
    }

    func testProjectReadinessUsesLinkedTasks() throws {
        try PersonalPlanTemplateService.installIfPossible(context: context)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let productChallengeTasks = tasks.filter { $0.project?.title == "Product Challenge 初賽" }
        XCTAssertEqual(productChallengeTasks.count, 3)

        try repository.toggleTask(productChallengeTasks[0])

        let productChallengeProject = try XCTUnwrap(try context.fetch(FetchDescriptor<Project>()).first { $0.title == "Product Challenge 初賽" })
        let snapshot = DashboardEngine.makeOverview(
            accounts: try context.fetch(FetchDescriptor<Account>()),
            ledgerEntries: try context.fetch(FetchDescriptor<LedgerEntry>()),
            plannedEntries: try context.fetch(FetchDescriptor<PlannedEntry>()),
            assetSnapshots: try context.fetch(FetchDescriptor<AssetSnapshot>()),
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: try context.fetch(FetchDescriptor<CalendarItem>()),
            projects: [productChallengeProject],
            referenceDate: Date(timeIntervalSince1970: 0)
        )

        let productChallengeStatus = snapshot.projectStatuses.first { $0.title == "Product Challenge 初賽" }
        XCTAssertEqual(productChallengeStatus?.openTaskCount, 2)
        XCTAssertEqual(productChallengeStatus?.readiness, 33)
    }

    func testCommandCenterSuggestsSevenDayFocusFromPriorityDueDateAndProjectDeadline() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 4, 29, 9, 0, calendar: calendar)
        let goal = try repository.createGoal(title: "Competitions", summary: "", targetDate: nil)
        let productChallenge = try repository.createProject(
            title: "Product Challenge 初賽",
            summary: "",
            deadline: testDate(2026, 5, 2, 23, 59, calendar: calendar),
            goal: goal
        )
        let dueToday = try repository.createTask(
            title: "完成 Product Challenge 問題定義初稿",
            dueDate: testDate(2026, 4, 29, 20, 0, calendar: calendar),
            priority: .critical,
            project: productChallenge
        )
        _ = try repository.createTask(
            title: "完成 Product Challenge 解法與影響力初稿",
            dueDate: testDate(2026, 5, 1, 20, 0, calendar: calendar),
            priority: .high,
            project: productChallenge
        )

        let snapshot = CommandCenterEngine.makeSnapshot(
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: try context.fetch(FetchDescriptor<CalendarItem>()),
            projects: try context.fetch(FetchDescriptor<Project>()),
            dailyPlanItems: try context.fetch(FetchDescriptor<DailyPlanItem>()),
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.days.count, 7)
        XCTAssertTrue(snapshot.today?.focusItems.contains(where: { $0.task?.id == dueToday.id }) == true)
        XCTAssertTrue(snapshot.deadlineRisks.contains(where: { $0.project.id == productChallenge.id }))
        XCTAssertTrue(snapshot.days.flatMap(\.focusItems).contains { $0.title == "完成 Product Challenge 解法與影響力初稿" })
    }

    func testManualDailyFocusIsIdempotentAndTakesPriority() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 4, 29, 9, 0, calendar: calendar)
        let project = try repository.createProject(title: "Research Fair送件", summary: "", deadline: nil, goal: nil)
        let task = try repository.createTask(
            title: "整理Research Fair研究題目與假設",
            dueDate: testDate(2026, 5, 1, 20, 0, calendar: calendar),
            priority: .critical,
            project: project
        )

        let first = try repository.scheduleTask(task, kind: .focus, plannedDate: referenceDate, calendar: calendar)
        let second = try repository.scheduleTask(task, kind: .focus, plannedDate: referenceDate, calendar: calendar)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyPlanItem>()).count, 1)

        let snapshot = CommandCenterEngine.makeSnapshot(
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: try context.fetch(FetchDescriptor<CalendarItem>()),
            projects: try context.fetch(FetchDescriptor<Project>()),
            dailyPlanItems: try context.fetch(FetchDescriptor<DailyPlanItem>()),
            referenceDate: referenceDate,
            calendar: calendar
        )

        let focus = try XCTUnwrap(snapshot.today?.focusItems.first)
        XCTAssertEqual(focus.source, .manual)
        XCTAssertEqual(focus.task?.id, task.id)
    }

    func testTimeBlockCreatesCalendarItemAndCanConflict() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 4, 29, 9, 0, calendar: calendar)
        let project = try repository.createProject(title: "短期賺錢與Gig Platform", summary: "", deadline: nil, goal: nil)
        let task = try repository.createTask(title: "規劃機可接案時段", dueDate: nil, priority: .high, project: project)
        let start = testDate(2026, 4, 29, 14, 0, calendar: calendar)
        let end = testDate(2026, 4, 29, 15, 0, calendar: calendar)
        _ = try repository.createCalendarItem(
            title: "Existing focus block",
            startDate: testDate(2026, 4, 29, 14, 30, calendar: calendar),
            endDate: testDate(2026, 4, 29, 15, 30, calendar: calendar),
            allDay: false,
            location: "",
            note: "",
            project: project
        )

        let planItem = try repository.scheduleTask(task, kind: .timeBlock, plannedDate: referenceDate, startDate: start, endDate: end, calendar: calendar)

        XCTAssertNotNil(planItem.calendarItem)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CalendarItem>()).count, 2)

        let command = CommandCenterEngine.makeSnapshot(
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: try context.fetch(FetchDescriptor<CalendarItem>()),
            projects: try context.fetch(FetchDescriptor<Project>()),
            dailyPlanItems: try context.fetch(FetchDescriptor<DailyPlanItem>()),
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(command.today?.timeBlocks.count, 2)
        XCTAssertTrue(command.today?.timeBlocks.contains(where: { $0.planItem?.id == planItem.id && $0.task?.id == task.id }) == true)

        let overview = DashboardEngine.makeOverview(
            accounts: [],
            ledgerEntries: [],
            plannedEntries: [],
            assetSnapshots: [],
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: try context.fetch(FetchDescriptor<CalendarItem>()),
            projects: try context.fetch(FetchDescriptor<Project>()),
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertTrue(overview.conflicts.contains { $0.title == "Calendar overlap" })
    }

    func testDailyPlanItemCanMoveAcrossDaysWithoutCopying() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 4, 29, 9, 0, calendar: calendar)
        let nextDay = testDate(2026, 4, 30, 9, 0, calendar: calendar)
        let task = try repository.createTask(title: "移動排程測試", dueDate: nil, priority: .high, project: nil)
        let item = try repository.scheduleTask(task, kind: .focus, plannedDate: referenceDate, calendar: calendar)

        let moved = try repository.moveDailyPlanItem(item, to: nextDay, calendar: calendar)
        let items = try context.fetch(FetchDescriptor<DailyPlanItem>())

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(moved.id, item.id)
        XCTAssertTrue(calendar.isDate(moved.plannedDate, inSameDayAs: nextDay))
    }

    func testDailyPlanItemReorderIsStableWithinSameDay() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 4, 29, 9, 0, calendar: calendar)
        let firstTask = try repository.createTask(title: "第一個", dueDate: nil, priority: .medium, project: nil)
        let secondTask = try repository.createTask(title: "第二個", dueDate: nil, priority: .medium, project: nil)
        let thirdTask = try repository.createTask(title: "第三個", dueDate: nil, priority: .medium, project: nil)
        _ = try repository.scheduleTask(firstTask, kind: .focus, plannedDate: referenceDate, calendar: calendar)
        _ = try repository.scheduleTask(secondTask, kind: .focus, plannedDate: referenceDate, calendar: calendar)
        let third = try repository.scheduleTask(thirdTask, kind: .focus, plannedDate: referenceDate, calendar: calendar)

        try repository.reorderDailyPlanItem(third, toIndex: 0, calendar: calendar)

        let snapshot = CommandCenterEngine.makeSnapshot(
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: [],
            projects: [],
            dailyPlanItems: try context.fetch(FetchDescriptor<DailyPlanItem>()),
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.today?.focusItems.map(\.title), ["第三個", "第一個", "第二個"])
    }

    func testDailyPlanItemPostponeMovesToTomorrow() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 4, 29, 9, 0, calendar: calendar)
        let task = try repository.createTask(title: "延後測試", dueDate: nil, priority: .high, project: nil)
        let item = try repository.scheduleTask(task, kind: .focus, plannedDate: referenceDate, calendar: calendar)

        let postponed = try repository.postponeDailyPlanItem(item, calendar: calendar)

        XCTAssertTrue(calendar.isDate(postponed.plannedDate, inSameDayAs: testDate(2026, 4, 30, calendar: calendar)))
        XCTAssertEqual(postponed.task?.id, task.id)
    }

    func testUnschedulingTimeBlockKeepsLinkedCalendarItem() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 4, 29, 9, 0, calendar: calendar)
        let start = testDate(2026, 4, 29, 14, 0, calendar: calendar)
        let end = testDate(2026, 4, 29, 15, 0, calendar: calendar)
        let task = try repository.createTask(title: "保留行程測試", dueDate: nil, priority: .high, project: nil)
        let item = try repository.scheduleTask(task, kind: .timeBlock, plannedDate: referenceDate, startDate: start, endDate: end, calendar: calendar)
        let linkedCalendarID = try XCTUnwrap(item.calendarItem?.id)

        try repository.unscheduleDailyPlanItem(item, calendar: calendar)

        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyPlanItem>()).count, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CalendarItem>()).contains { $0.id == linkedCalendarID })
    }

    func testCompletedTaskIsRemovedFromCommandCenter() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 4, 29, 9, 0, calendar: calendar)
        let task = try repository.createTask(
            title: "完成後不應顯示",
            dueDate: testDate(2026, 4, 29, 12, 0, calendar: calendar),
            priority: .critical,
            project: nil
        )

        try repository.toggleTask(task)

        let snapshot = CommandCenterEngine.makeSnapshot(
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: [],
            projects: [],
            dailyPlanItems: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertFalse(snapshot.today?.focusItems.contains(where: { $0.task?.id == task.id }) == true)
    }

    func testScheduleQualityMarksRepeatedFocusWithoutDeletingItems() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 5, 5, 9, 0, calendar: calendar)
        let tomorrow = testDate(2026, 5, 6, 9, 0, calendar: calendar)
        let task = try repository.createTask(title: "跨日重複焦點", dueDate: nil, priority: .medium, project: nil)
        try repository.scheduleTask(task, kind: .focus, plannedDate: referenceDate, calendar: calendar)
        try repository.scheduleTask(task, kind: .focus, plannedDate: tomorrow, calendar: calendar)

        let snapshot = ScheduleQualityEngine.makeSnapshot(
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: [],
            projects: [],
            dailyPlanItems: try context.fetch(FetchDescriptor<DailyPlanItem>()),
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.repeatedTasks.count, 1)
        XCTAssertEqual(snapshot.repeatedTasks.first?.task.id, task.id)
        XCTAssertEqual(snapshot.repeatedTasks.first?.scheduledDates.count, 2)
        XCTAssertEqual(snapshot.days.first?.repeatedFocusCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyPlanItem>()).filter { $0.kind == .focus }.count, 2)
    }

    func testScheduleQualityMarksImportantFocusWithoutSameDayTimeBlock() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 5, 5, 9, 0, calendar: calendar)
        let start = testDate(2026, 5, 5, 20, 0, calendar: calendar)
        let end = testDate(2026, 5, 5, 21, 0, calendar: calendar)
        let task = try repository.createTask(title: "高優先級缺時間區塊", dueDate: nil, priority: .high, project: nil)
        try repository.scheduleTask(task, kind: .focus, plannedDate: referenceDate, calendar: calendar)

        let snapshotBefore = ScheduleQualityEngine.makeSnapshot(
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: [],
            projects: [],
            dailyPlanItems: try context.fetch(FetchDescriptor<DailyPlanItem>()),
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(snapshotBefore.needsTimeBlockItems.count, 1)
        XCTAssertEqual(snapshotBefore.needsTimeBlockItems.first?.task.id, task.id)
        XCTAssertEqual(snapshotBefore.days.first?.needsTimeBlockCount, 1)

        try repository.scheduleTask(task, kind: .timeBlock, plannedDate: referenceDate, startDate: start, endDate: end, calendar: calendar)
        let snapshotAfter = ScheduleQualityEngine.makeSnapshot(
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: try context.fetch(FetchDescriptor<CalendarItem>()),
            projects: [],
            dailyPlanItems: try context.fetch(FetchDescriptor<DailyPlanItem>()),
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertTrue(snapshotAfter.needsTimeBlockItems.isEmpty)
        XCTAssertEqual(snapshotAfter.days.first?.needsTimeBlockCount, 0)
    }

    func testScheduleQualityUsesDueDatesProjectDeadlinesAndIgnoresCompletedTasks() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 5, 5, 9, 0, calendar: calendar)
        let deadlineProject = try repository.createProject(
            title: "七天內截止專案",
            summary: "",
            deadline: testDate(2026, 5, 10, 23, 59, calendar: calendar),
            goal: nil
        )
        let dueSoon = try repository.createTask(
            title: "七天內到期任務",
            dueDate: testDate(2026, 5, 8, 12, 0, calendar: calendar),
            priority: .medium,
            project: nil
        )
        let projectDeadlineSoon = try repository.createTask(
            title: "專案截止前任務",
            dueDate: nil,
            priority: .medium,
            project: deadlineProject
        )
        let completed = try repository.createTask(
            title: "完成任務不警告",
            dueDate: testDate(2026, 5, 7, 12, 0, calendar: calendar),
            priority: .critical,
            project: deadlineProject
        )
        try repository.scheduleTask(dueSoon, kind: .focus, plannedDate: referenceDate, calendar: calendar)
        try repository.scheduleTask(projectDeadlineSoon, kind: .focus, plannedDate: referenceDate, calendar: calendar)
        try repository.scheduleTask(completed, kind: .focus, plannedDate: referenceDate, calendar: calendar)
        try repository.toggleTask(completed)

        let snapshot = ScheduleQualityEngine.makeSnapshot(
            tasks: try context.fetch(FetchDescriptor<TaskItem>()),
            calendarItems: [],
            projects: try context.fetch(FetchDescriptor<Project>()),
            dailyPlanItems: try context.fetch(FetchDescriptor<DailyPlanItem>()),
            referenceDate: referenceDate,
            calendar: calendar
        )
        let issueTaskIDs = Set(snapshot.needsTimeBlockItems.map { $0.task.id })

        XCTAssertTrue(issueTaskIDs.contains(dueSoon.id))
        XCTAssertTrue(issueTaskIDs.contains(projectDeadlineSoon.id))
        XCTAssertFalse(issueTaskIDs.contains(completed.id))
        XCTAssertEqual(snapshot.needsTimeBlockItems.count, 2)
    }

    func testWeekPlanEngineExcludesTasksAlreadyFocusedAnywhereInSevenDayWindow() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 5, 5, 9, 0, calendar: calendar)
        let scheduledDay = testDate(2026, 5, 7, 9, 0, calendar: calendar)
        let project = try repository.createProject(title: "排程品質測試", summary: "", deadline: nil, goal: nil)
        let alreadyFocused = try repository.createTask(title: "已在七天內排過", dueDate: nil, priority: .critical, project: project)
        let open = try repository.createTask(title: "尚未排程任務", dueDate: nil, priority: .high, project: project)
        try repository.scheduleTask(alreadyFocused, kind: .focus, plannedDate: scheduledDay, calendar: calendar)

        let draft = WeekPlanEngine.makeDraft(
            tasks: [alreadyFocused, open],
            calendarItems: [],
            projects: [project],
            dailyPlanItems: try context.fetch(FetchDescriptor<DailyPlanItem>()),
            referenceDate: referenceDate,
            calendar: calendar
        )
        let draftTaskIDs = Set(draft.days.flatMap(\.items).map { $0.task.id })

        XCTAssertFalse(draftTaskIDs.contains(alreadyFocused.id))
        XCTAssertTrue(draftTaskIDs.contains(open.id))
    }

    func testWeekPlanDraftEditingMovesItemToAnotherDay() throws {
        let calendar = testCalendar
        let firstDay = testDate(2026, 5, 5, calendar: calendar)
        let targetDay = testDate(2026, 5, 6, calendar: calendar)
        let task = try repository.createTask(title: "可移動草案任務", dueDate: nil, priority: .high, project: nil)
        let draft = makeWeekPlanDraft(days: [firstDay, targetDay], calendar: calendar, dayTasks: [[task], []])
        let itemID = try XCTUnwrap(draft.days.first?.items.first?.id)

        let edited = WeekPlanEngine.moveDraftItem(draft, itemID: itemID, to: targetDay, calendarItems: [], calendar: calendar)

        XCTAssertEqual(edited.focusCount, 1)
        XCTAssertTrue(edited.days[0].items.isEmpty)
        XCTAssertEqual(edited.days[1].items.first?.id, itemID)
        XCTAssertEqual(edited.days[1].items.first?.plannedDate, calendar.startOfDay(for: targetDay))
        XCTAssertEqual(edited.days[1].items.first?.suggestedStart, testDate(2026, 5, 6, 19, 0, calendar: calendar))
    }

    func testWeekPlanDraftEditingRemovesItem() throws {
        let calendar = testCalendar
        let day = testDate(2026, 5, 5, calendar: calendar)
        let first = try repository.createTask(title: "保留草案任務", dueDate: nil, priority: .high, project: nil)
        let second = try repository.createTask(title: "移除草案任務", dueDate: nil, priority: .high, project: nil)
        let draft = makeWeekPlanDraft(day: day, calendar: calendar, tasks: [first, second])
        let removedID = try XCTUnwrap(draft.days.first?.items.last?.id)

        let edited = WeekPlanEngine.removeDraftItem(draft, itemID: removedID)

        XCTAssertEqual(edited.focusCount, 1)
        XCTAssertEqual(edited.days.first?.items.first?.task.id, first.id)
        XCTAssertFalse(edited.days.flatMap(\.items).contains { $0.id == removedID })
    }

    func testWeekPlanDraftEditingChangesSuggestedTimeSlot() throws {
        let calendar = testCalendar
        let day = testDate(2026, 5, 5, calendar: calendar)
        let task = try repository.createTask(title: "改時間草案任務", dueDate: nil, priority: .high, project: nil)
        let draft = makeWeekPlanDraft(day: day, calendar: calendar, tasks: [task])
        let itemID = try XCTUnwrap(draft.days.first?.items.first?.id)

        let edited = WeekPlanEngine.updateDraftItemTimeSlot(draft, itemID: itemID, slotIndex: 2, calendarItems: [], calendar: calendar)
        let item = try XCTUnwrap(edited.days.first?.items.first)

        XCTAssertEqual(item.id, itemID)
        XCTAssertEqual(item.suggestedStart, testDate(2026, 5, 5, 21, 20, calendar: calendar))
        XCTAssertEqual(item.suggestedEnd, testDate(2026, 5, 5, 22, 20, calendar: calendar))
    }

    func testWeekPlanEngineCreatesSevenDayDraftWithBalancedDailyFocus() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 5, 1, 9, 0, calendar: calendar)
        let competition = try repository.createProject(title: "Product Challenge 初賽", summary: "", deadline: testDate(2026, 5, 18, 23, 59, calendar: calendar), goal: nil)
        let earning = try repository.createProject(title: "短期賺錢與Gig Platform", summary: "", deadline: nil, goal: nil)
        let travel = try repository.createProject(title: "Demo Trip準備", summary: "", deadline: testDate(2026, 6, 8, calendar: calendar), goal: nil)
        let investment = try repository.createProject(title: "2330 投資追蹤", summary: "", deadline: nil, goal: nil)
        let academic = try repository.createProject(title: "學術研究路線", summary: "", deadline: testDate(2038, 12, 31, calendar: calendar), goal: nil)

        let tasks = [
            try repository.createTask(title: "完成 Product Challenge 初稿", dueDate: testDate(2026, 5, 3, calendar: calendar), priority: .critical, project: competition),
            try repository.createTask(title: "找Gig Platform任務清單", dueDate: nil, priority: .high, project: earning),
            try repository.createTask(title: "確認Demo Trip預算", dueDate: nil, priority: .high, project: travel),
            try repository.createTask(title: "更新 2330 月度快照", dueDate: nil, priority: .medium, project: investment),
            try repository.createTask(title: "整理研究作品集題目", dueDate: nil, priority: .medium, project: academic)
        ]

        let draft = WeekPlanEngine.makeDraft(
            tasks: tasks,
            calendarItems: [],
            projects: try context.fetch(FetchDescriptor<Project>()),
            dailyPlanItems: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(draft.days.count, 7)
        XCTAssertTrue(draft.days.allSatisfy { $0.items.count <= 3 })
        XCTAssertGreaterThanOrEqual(Set(draft.days.first?.items.map(\.line) ?? []).count, 3)
        XCTAssertTrue(draft.days.flatMap(\.items).contains { $0.line == .competition })
        XCTAssertTrue(draft.days.flatMap(\.items).contains { $0.line == .earning })
        XCTAssertTrue(draft.days.flatMap(\.items).contains { $0.line == .travel })
    }

    func testWeekPlanEngineExcludesCompletedAndAlreadyFocusedSameDayTasks() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 5, 1, 9, 0, calendar: calendar)
        let project = try repository.createProject(title: "Research Fair送件", summary: "", deadline: testDate(2026, 5, 20, 15, 0, calendar: calendar), goal: nil)
        let scheduled = try repository.createTask(title: "已排同日焦點", dueDate: nil, priority: .critical, project: project)
        let completed = try repository.createTask(title: "已完成不進草案", dueDate: nil, priority: .critical, project: project)
        let open = try repository.createTask(title: "可被排入草案", dueDate: nil, priority: .high, project: project)
        try repository.scheduleTask(scheduled, kind: .focus, plannedDate: referenceDate, calendar: calendar)
        try repository.toggleTask(completed)

        let draft = WeekPlanEngine.makeDraft(
            tasks: [scheduled, completed, open],
            calendarItems: [],
            projects: [project],
            dailyPlanItems: try context.fetch(FetchDescriptor<DailyPlanItem>()),
            referenceDate: referenceDate,
            calendar: calendar
        )

        let todayTaskIDs = Set(draft.days.first?.items.map { $0.task.id } ?? [])
        XCTAssertFalse(todayTaskIDs.contains(scheduled.id))
        XCTAssertFalse(draft.days.flatMap(\.items).contains { $0.task.id == completed.id })
        XCTAssertTrue(draft.days.flatMap(\.items).contains { $0.task.id == open.id })
    }

    func testApplyWeekPlanCreatesFocusAndLinkedTimeBlocks() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 5, 1, 9, 0, calendar: calendar)
        let project = try repository.createProject(title: "Demo Trip準備", summary: "", deadline: nil, goal: nil)
        let task = try repository.createTask(title: "確認Demo Destination住宿付款", dueDate: nil, priority: .high, project: project)
        let draft = WeekPlanEngine.makeDraft(
            tasks: [task],
            calendarItems: [],
            projects: [project],
            dailyPlanItems: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        let itemID = try XCTUnwrap(draft.days.first?.items.first?.id)
        let result = try repository.applyWeekPlanDraft(
            draft,
            request: WeekPlanApplyRequest(
                selectedDraftItemIDs: [itemID],
                timeBlockEnabledDraftItemIDs: [itemID],
                options: .init(conflictResolution: .skip)
            ),
            calendar: calendar
        )
        let dailyItems = try context.fetch(FetchDescriptor<DailyPlanItem>())
        let calendarItems = try context.fetch(FetchDescriptor<CalendarItem>())

        XCTAssertEqual(result.focusCreated, 1)
        XCTAssertEqual(result.timeBlocksCreated, 1)
        XCTAssertEqual(dailyItems.filter { $0.kind == .focus }.count, 1)
        XCTAssertEqual(dailyItems.filter { $0.kind == .timeBlock && $0.calendarItem != nil }.count, 1)
        XCTAssertEqual(calendarItems.count, 1)
        XCTAssertEqual(calendarItems.first?.project?.id, project.id)
    }

    func testApplyWeekPlanSkipsConflictingTimeBlockButKeepsFocus() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 5, 1, 9, 0, calendar: calendar)
        let project = try repository.createProject(title: "Product Challenge 初賽", summary: "", deadline: nil, goal: nil)
        let task = try repository.createTask(title: "完成 Product Challenge Demo 草稿", dueDate: nil, priority: .critical, project: project)
        _ = try repository.createCalendarItem(
            title: "Existing evening block",
            startDate: testDate(2026, 5, 1, 19, 30, calendar: calendar),
            endDate: testDate(2026, 5, 1, 20, 30, calendar: calendar),
            allDay: false,
            location: "",
            note: "",
            project: project
        )
        let draft = WeekPlanEngine.makeDraft(
            tasks: [task],
            calendarItems: try context.fetch(FetchDescriptor<CalendarItem>()),
            projects: [project],
            dailyPlanItems: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(draft.conflictCount, 1)

        let itemID = try XCTUnwrap(draft.days.first?.items.first?.id)
        let result = try repository.applyWeekPlanDraft(
            draft,
            request: WeekPlanApplyRequest(
                selectedDraftItemIDs: [itemID],
                timeBlockEnabledDraftItemIDs: [itemID],
                options: .init(conflictResolution: .skip)
            ),
            calendar: calendar
        )
        let dailyItems = try context.fetch(FetchDescriptor<DailyPlanItem>())

        XCTAssertEqual(result.focusCreated, 1)
        XCTAssertEqual(result.timeBlocksCreated, 0)
        XCTAssertEqual(result.timeBlocksSkippedForConflict, 1)
        XCTAssertEqual(dailyItems.filter { $0.kind == .focus }.count, 1)
        XCTAssertEqual(dailyItems.filter { $0.kind == .timeBlock }.count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CalendarItem>()).count, 1)
    }

    func testApplyWeekPlanIsIdempotent() throws {
        let calendar = testCalendar
        let referenceDate = testDate(2026, 5, 1, 9, 0, calendar: calendar)
        let project = try repository.createProject(title: "2330 投資追蹤", summary: "", deadline: nil, goal: nil)
        let task = try repository.createTask(title: "更新 2330 快照", dueDate: nil, priority: .high, project: project)
        let draft = WeekPlanEngine.makeDraft(
            tasks: [task],
            calendarItems: [],
            projects: [project],
            dailyPlanItems: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        let first = try repository.applyWeekPlanDraft(draft, calendar: calendar)
        let second = try repository.applyWeekPlanDraft(draft, calendar: calendar)

        XCTAssertEqual(first.focusCreated, 1)
        XCTAssertEqual(first.timeBlocksCreated, 1)
        XCTAssertEqual(second.focusCreated, 0)
        XCTAssertEqual(second.focusSkippedExisting, 1)
        XCTAssertEqual(second.timeBlocksCreated, 0)
        XCTAssertEqual(second.timeBlocksSkippedExisting, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyPlanItem>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CalendarItem>()).count, 1)
    }

    func testApplyWeekPlanOnlyAppliesSelectedDraftItems() throws {
        let calendar = testCalendar
        let day = testDate(2026, 5, 1, calendar: calendar)
        let first = try repository.createTask(title: "第一個草案任務", dueDate: nil, priority: .high, project: nil)
        let second = try repository.createTask(title: "第二個草案任務", dueDate: nil, priority: .high, project: nil)
        let draft = makeWeekPlanDraft(day: day, calendar: calendar, tasks: [first, second])
        let selectedID = try XCTUnwrap(draft.days.first?.items.first?.id)
        let request = WeekPlanApplyRequest(
            selectedDraftItemIDs: [selectedID],
            timeBlockEnabledDraftItemIDs: [selectedID]
        )

        let result = try repository.applyWeekPlanDraft(draft, request: request, calendar: calendar)

        XCTAssertEqual(result.focusCreated, 1)
        XCTAssertEqual(result.timeBlocksCreated, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyPlanItem>()).count, 2)
        XCTAssertFalse(try context.fetch(FetchDescriptor<DailyPlanItem>()).contains { $0.task?.id == second.id })
    }

    func testApplyWeekPlanDoesNotCreateTimeBlockWhenFocusIsNotSelected() throws {
        let calendar = testCalendar
        let day = testDate(2026, 5, 1, calendar: calendar)
        let task = try repository.createTask(title: "未勾選焦點任務", dueDate: nil, priority: .high, project: nil)
        let draft = makeWeekPlanDraft(day: day, calendar: calendar, tasks: [task])
        let itemID = try XCTUnwrap(draft.days.first?.items.first?.id)
        let request = WeekPlanApplyRequest(
            selectedDraftItemIDs: [],
            timeBlockEnabledDraftItemIDs: [itemID]
        )

        let result = try repository.applyWeekPlanDraft(draft, request: request, calendar: calendar)

        XCTAssertEqual(result.focusCreated, 0)
        XCTAssertEqual(result.timeBlocksCreated, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyPlanItem>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CalendarItem>()).count, 0)
    }

    func testApplyWeekPlanFindsAvailableSlotWhenSuggestedTimeConflicts() throws {
        let calendar = testCalendar
        let day = testDate(2026, 5, 1, calendar: calendar)
        let task = try repository.createTask(title: "自動改排測試", dueDate: nil, priority: .high, project: nil)
        _ = try repository.createCalendarItem(
            title: "Existing 19 block",
            startDate: testDate(2026, 5, 1, 19, 0, calendar: calendar),
            endDate: testDate(2026, 5, 1, 20, 0, calendar: calendar),
            allDay: false,
            location: "",
            note: "",
            project: nil
        )
        let draft = makeWeekPlanDraft(day: day, calendar: calendar, tasks: [task])
        let itemID = try XCTUnwrap(draft.days.first?.items.first?.id)
        let request = WeekPlanApplyRequest(
            selectedDraftItemIDs: [itemID],
            timeBlockEnabledDraftItemIDs: [itemID],
            options: .init(conflictResolution: .findAvailableSlot)
        )

        let result = try repository.applyWeekPlanDraft(draft, request: request, calendar: calendar)
        let createdBlock = try XCTUnwrap(try context.fetch(FetchDescriptor<CalendarItem>()).first { $0.title == "自動改排測試" })

        XCTAssertEqual(result.timeBlocksCreated, 1)
        XCTAssertEqual(result.timeBlocksRescheduled, 1)
        XCTAssertEqual(createdBlock.startDate, testDate(2026, 5, 1, 20, 0, calendar: calendar))
        XCTAssertEqual(createdBlock.endDate, testDate(2026, 5, 1, 21, 0, calendar: calendar))
    }

    func testApplyWeekPlanCreatesFocusOnlyWhenNoAvailableSlotExists() throws {
        let calendar = testCalendar
        let day = testDate(2026, 5, 1, calendar: calendar)
        let task = try repository.createTask(title: "沒有空檔測試", dueDate: nil, priority: .high, project: nil)
        _ = try repository.createCalendarItem(
            title: "Full day busy",
            startDate: testDate(2026, 5, 1, 8, 0, calendar: calendar),
            endDate: testDate(2026, 5, 1, 22, 30, calendar: calendar),
            allDay: false,
            location: "",
            note: "",
            project: nil
        )
        let draft = makeWeekPlanDraft(day: day, calendar: calendar, tasks: [task])
        let itemID = try XCTUnwrap(draft.days.first?.items.first?.id)
        let request = WeekPlanApplyRequest(
            selectedDraftItemIDs: [itemID],
            timeBlockEnabledDraftItemIDs: [itemID],
            options: .init(conflictResolution: .findAvailableSlot)
        )

        let result = try repository.applyWeekPlanDraft(draft, request: request, calendar: calendar)

        XCTAssertEqual(result.focusCreated, 1)
        XCTAssertEqual(result.timeBlocksCreated, 0)
        XCTAssertEqual(result.timeBlocksSkippedNoAvailableSlot, 1)
        XCTAssertEqual(result.timeBlockOutcomes.first?.status, .skippedNoAvailableSlot)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyPlanItem>()).filter { $0.kind == .focus }.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyPlanItem>()).filter { $0.kind == .timeBlock }.count, 0)
    }

    func testApplyWeekPlanNewTimeBlocksDoNotOverlapEachOther() throws {
        let calendar = testCalendar
        let day = testDate(2026, 5, 1, calendar: calendar)
        let first = try repository.createTask(title: "第一個時間區塊", dueDate: nil, priority: .high, project: nil)
        let second = try repository.createTask(title: "第二個時間區塊", dueDate: nil, priority: .high, project: nil)
        _ = try repository.createCalendarItem(
            title: "Existing 19 block",
            startDate: testDate(2026, 5, 1, 19, 0, calendar: calendar),
            endDate: testDate(2026, 5, 1, 20, 0, calendar: calendar),
            allDay: false,
            location: "",
            note: "",
            project: nil
        )
        let draft = makeWeekPlanDraft(day: day, calendar: calendar, tasks: [first, second])
        let itemIDs = Set(draft.days.flatMap(\.items).map(\.id))
        let request = WeekPlanApplyRequest(
            selectedDraftItemIDs: itemIDs,
            timeBlockEnabledDraftItemIDs: itemIDs,
            options: .init(conflictResolution: .findAvailableSlot)
        )

        let result = try repository.applyWeekPlanDraft(draft, request: request, calendar: calendar)
        let createdBlocks = try context.fetch(FetchDescriptor<CalendarItem>())
            .filter { $0.title == "第一個時間區塊" || $0.title == "第二個時間區塊" }
            .sorted { $0.startDate < $1.startDate }

        XCTAssertEqual(result.timeBlocksCreated, 2)
        XCTAssertEqual(createdBlocks.count, 2)
        XCTAssertFalse(createdBlocks[0].endDate > createdBlocks[1].startDate)
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func testDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeWeekPlanDraft(day: Date, calendar: Calendar, tasks: [TaskItem]) -> WeekPlanDraft {
        makeWeekPlanDraft(days: [day], calendar: calendar, dayTasks: [tasks])
    }

    private func makeWeekPlanDraft(days: [Date], calendar: Calendar, dayTasks: [[TaskItem]]) -> WeekPlanDraft {
        let dayDrafts = zip(days, dayTasks).map { rawDay, tasks in
            let dayStart = calendar.startOfDay(for: rawDay)
            let items = tasks.enumerated().map { index, task in
                let slot = WeekPlanEngine.suggestedTimeSlot(on: dayStart, index: index, calendar: calendar)
                return WeekPlanDraftItem(
                    id: "test-\(index)-\(task.id.uuidString)",
                    task: task,
                    line: .general,
                    reason: "Test",
                    plannedDate: dayStart,
                    suggestedStart: slot?.start,
                    suggestedEnd: slot?.end,
                    timeBlockConflict: false,
                    conflictTitle: nil
                )
            }
            return WeekPlanDayDraft(id: dayKey(dayStart, calendar: calendar), date: dayStart, items: items)
        }
        return WeekPlanDraft(generatedAt: calendar.startOfDay(for: days.first ?? .now), days: dayDrafts)
    }

    private func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
