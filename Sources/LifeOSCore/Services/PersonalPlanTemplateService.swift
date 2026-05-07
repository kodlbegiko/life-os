import Foundation
import SwiftData

public struct PersonalPlanTemplateInstallResult: Equatable {
    public var addedGoals = 0
    public var skippedGoals = 0
    public var addedProjects = 0
    public var skippedProjects = 0
    public var addedTasks = 0
    public var skippedTasks = 0
    public var addedCalendarItems = 0
    public var skippedCalendarItems = 0

    public var totalAdded: Int {
        addedGoals + addedProjects + addedTasks + addedCalendarItems
    }

    public var totalSkipped: Int {
        skippedGoals + skippedProjects + skippedTasks + skippedCalendarItems
    }
}

@MainActor
public enum PersonalPlanTemplateService {
    public static func installIfPossible(context: ModelContext) throws -> PersonalPlanTemplateInstallResult {
        let repository = LifeOSRepository(context: context)
        var result = PersonalPlanTemplateInstallResult()

        var goalsByTitle = try firstByTitle(context.fetch(FetchDescriptor<Goal>()))
        var projectsByTitle = try firstByTitle(context.fetch(FetchDescriptor<Project>()))
        var tasksByTitle = try firstByTitle(context.fetch(FetchDescriptor<TaskItem>()))
        var calendarItemsByTitle = try firstByTitle(context.fetch(FetchDescriptor<CalendarItem>()))

        func goal(_ title: String, _ summary: String, targetDate: Date?, state: GoalState = .active) throws -> Goal {
            if let existing = goalsByTitle[title] {
                result.skippedGoals += 1
                return existing
            }

            let created = try repository.createGoal(title: title, summary: summary, targetDate: targetDate, state: state)
            goalsByTitle[title] = created
            result.addedGoals += 1
            return created
        }

        func project(_ title: String, _ summary: String, deadline: Date?, goal linkedGoal: Goal, state: ProjectState = .active, note: String = "") throws -> Project {
            if let existing = projectsByTitle[title] {
                result.skippedProjects += 1
                return existing
            }

            let created = try repository.createProject(title: title, summary: summary, deadline: deadline, goal: linkedGoal, state: state, note: note)
            projectsByTitle[title] = created
            result.addedProjects += 1
            return created
        }

        func task(_ title: String, dueDate: Date?, priority: TaskPriority, project linkedProject: Project, note: String = "") throws {
            if tasksByTitle[title] != nil {
                result.skippedTasks += 1
                return
            }

            let created = try repository.createTask(title: title, dueDate: dueDate, priority: priority, project: linkedProject, note: note)
            tasksByTitle[title] = created
            result.addedTasks += 1
        }

        func calendarItem(_ title: String, startDate: Date, endDate: Date, allDay: Bool = false, location: String = "", note: String = "", project linkedProject: Project) throws {
            if calendarItemsByTitle[title] != nil {
                result.skippedCalendarItems += 1
                return
            }

            let created = try repository.createCalendarItem(title: title, startDate: startDate, endDate: endDate, allDay: allDay, location: location, note: note, project: linkedProject)
            calendarItemsByTitle[title] = created
            result.addedCalendarItems += 1
        }

        let competitionGoal = try goal(
            "完成 2026 競賽送件",
            "把 Product Challenge 與Research Fair拆成可執行任務，先完成 1-2 份初稿再送件。",
            targetDate: date(2026, 5, 20, 15, 0)
        )
        let demoTripGoal = try goal(
            "完成Demo Trip準備",
            "在 2026/06/08 出發前完成預算、付款、行李與行程確認。",
            targetDate: date(2026, 6, 8, 0, 0),
            state: .planned
        )
        let earningGoal = try goal(
            "建立短期現金流",
            "穩定記錄Part-time收入，並在可騎車後準備Gig Platform任務接案。",
            targetDate: date(2026, 6, 30, 23, 59)
        )
        let investmentGoal = try goal(
            "追蹤 2330 長期投資",
            "每月更新 2330 市值、成本與損益，讓總資產與可動用現金分開看清楚。",
            targetDate: date(2026, 12, 31, 23, 59)
        )
        let snowGoal = try goal(
            "取得 Skill Certification L1 與Seasonal Work Prep",
            "先建立中級滑行能力、Skill Certification L1 預算與remoteseasonal workplaceseasonal work路線。",
            targetDate: date(2027, 3, 31, 23, 59),
            state: .planned
        )
        let academicGoal = try goal(
            "Academic Roadmap",
            "累積研究能力、作品集、競賽成果與升學規劃，逐步靠近學術長期目標。",
            targetDate: date(2038, 12, 31, 23, 59),
            state: .planned
        )

        let productChallenge = try project(
            "Product Challenge 初賽",
            "完成題目、解法、影響力與初賽送件。",
            deadline: date(2026, 5, 18, 23, 59),
            goal: competitionGoal,
            note: "官方初賽報名截止：2026/05/18 23:59。"
        )
        let mxic = try project(
            "Research Fair送件",
            "完成研究題目、假設、方法與報名資料。",
            deadline: date(2026, 5, 20, 15, 0),
            goal: competitionGoal,
            note: "報名截止：2026/05/20 15:00。"
        )
        let demoTripTrip = try project(
            "Demo Trip 2026/06/08-06/12",
            "把旅遊支出、付款、行李與每日安排先整理清楚。",
            deadline: date(2026, 6, 8, 0, 0),
            goal: demoTripGoal
        )
        let earning = try project(
            "短期賺錢與Gig Platform",
            "維持每週Part-time收入，並準備通勤工具可用後的空檔接案。",
            deadline: date(2026, 6, 30, 23, 59),
            goal: earningGoal
        )
        let investment = try project(
            "2330 投資追蹤",
            "用 Life OS 追蹤 2330 股數、成本、即時市值與每月損益。",
            deadline: date(2026, 5, 31, 23, 59),
            goal: investmentGoal
        )
        let casi = try project(
            "Skill Certification Level 1 準備",
            "整理報名條件、訓練地點、預算與中級滑行訓練節奏。",
            deadline: date(2027, 3, 31, 23, 59),
            goal: snowGoal
        )
        let seasonalWork = try project(
            "Seasonal Work Prep",
            "追蹤簽證、seasonal workplace職缺、教練資格與履歷作品集。",
            deadline: date(2027, 8, 31, 23, 59),
            goal: snowGoal,
            state: .planned
        )
        let academic = try project(
            "Academic Roadmap",
            "建立研究主題、作品集、升學與長期學術能力路線。",
            deadline: date(2038, 12, 31, 23, 59),
            goal: academicGoal,
            state: .planned
        )

        try task("完成 Product Challenge 問題定義初稿", dueDate: date(2026, 5, 3, 23, 59), priority: .critical, project: productChallenge)
        try task("完成 Product Challenge 解法與影響力初稿", dueDate: date(2026, 5, 8, 23, 59), priority: .high, project: productChallenge)
        try task("送出 Product Challenge 初賽報名", dueDate: date(2026, 5, 18, 20, 0), priority: .critical, project: productChallenge)

        try task("整理Research Fair研究題目與假設", dueDate: date(2026, 5, 4, 23, 59), priority: .critical, project: mxic)
        try task("完成Research Fair研究計畫初稿", dueDate: date(2026, 5, 10, 23, 59), priority: .high, project: mxic)
        try task("送出Research Fair報名資料", dueDate: date(2026, 5, 20, 12, 0), priority: .critical, project: mxic)

        try task("列Demo Trip每日預算", dueDate: date(2026, 5, 15, 23, 59), priority: .high, project: demoTripTrip)
        try task("確認Demo Trip機票住宿與付款狀態", dueDate: date(2026, 5, 20, 23, 59), priority: .high, project: demoTripTrip)
        try task("完成Demo Trip行李清單", dueDate: date(2026, 6, 5, 23, 59), priority: .medium, project: demoTripTrip)

        try task("每週記錄Part-time收入 1,200", dueDate: date(2026, 5, 3, 23, 59), priority: .high, project: earning)
        try task("整理Gig Platform可接任務類型", dueDate: date(2026, 5, 10, 23, 59), priority: .medium, project: earning)
        try task("規劃機可接案時段", dueDate: date(2026, 5, 12, 23, 59), priority: .medium, project: earning)

        try task("每月更新 2330 市值與損益", dueDate: date(2026, 5, 23, 23, 59), priority: .medium, project: investment)
        try task("檢查投資帳戶現金與 2330 成本", dueDate: date(2026, 5, 25, 23, 59), priority: .medium, project: investment)

        try task("整理 Skill Certification L1 報名條件與課程地點", dueDate: date(2026, 5, 12, 23, 59), priority: .medium, project: casi)
        try task("排定中級滑行自練週期", dueDate: date(2026, 5, 18, 23, 59), priority: .medium, project: casi)
        try task("估算 Skill Certification L1 與seasonal training總預算", dueDate: date(2026, 5, 24, 23, 59), priority: .medium, project: casi)

        try task("研究seasonal work資格與seasonal workplace職缺", dueDate: date(2026, 6, 30, 23, 59), priority: .medium, project: seasonalWork)
        try task("整理seasonal instructor履歷與證照缺口", dueDate: date(2026, 7, 31, 23, 59), priority: .medium, project: seasonalWork)

        try task("建立研究與作品集主題清單", dueDate: date(2026, 6, 30, 23, 59), priority: .medium, project: academic)
        try task("規劃學習領域與研究能力路線", dueDate: date(2026, 7, 31, 23, 59), priority: .medium, project: academic)
        try task("把比賽成果整理成作品集素材", dueDate: date(2026, 8, 31, 23, 59), priority: .medium, project: academic)

        try calendarItem(
            "Product Challenge 初賽截止",
            startDate: date(2026, 5, 18, 21, 0),
            endDate: date(2026, 5, 18, 23, 59),
            note: "最後檢查並送出報名。",
            project: productChallenge
        )
        try calendarItem(
            "Research Fair報名截止",
            startDate: date(2026, 5, 20, 12, 0),
            endDate: date(2026, 5, 20, 15, 0),
            note: "截止前確認報名資料與附件。",
            project: mxic
        )
        try calendarItem(
            "Demo Trip",
            startDate: date(2026, 6, 8, 0, 0),
            endDate: date(2026, 6, 12, 23, 59),
            allDay: true,
            location: "Demo Trip",
            note: "2026/06/08-06/12 Demo Trip。",
            project: demoTripTrip
        )
        try calendarItem(
            "每週收入與任務回顧",
            startDate: date(2026, 5, 3, 20, 0),
            endDate: date(2026, 5, 3, 21, 0),
            location: "Life OS",
            note: "檢查Part-time收入、比賽進度、下週接案空檔。",
            project: earning
        )

        return result
    }

    private static func firstByTitle<Model: PersistentModel>(_ models: [Model]) throws -> [String: Model] {
        var result: [String: Model] = [:]
        for model in models {
            if let goal = model as? Goal {
                result[goal.title] = result[goal.title] ?? model
            } else if let project = model as? Project {
                result[project.title] = result[project.title] ?? model
            } else if let task = model as? TaskItem {
                result[task.title] = result[task.title] ?? model
            } else if let item = model as? CalendarItem {
                result[item.title] = result[item.title] ?? model
            }
        }
        return result
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
    }
}
