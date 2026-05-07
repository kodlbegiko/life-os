import Foundation
import SwiftData

@MainActor
public enum StarterTemplateService {
    public static func installIfPossible(context: ModelContext, language: AppLanguage = .english) throws {
        let existingAccounts = try context.fetch(FetchDescriptor<Account>())
        if !existingAccounts.isEmpty {
            return
        }

        let copy = templateCopy(for: language)
        let repository = LifeOSRepository(context: context)

        let cash = try repository.createAccount(name: copy.cashAccount, kind: .cash)
        let bank = try repository.createAccount(name: copy.mainBankAccount, kind: .bank)
        let investment = try repository.createAccount(name: copy.investmentAccount, kind: .investment)

        let partTime = try repository.createCategory(name: copy.partTimeCategory, scope: .income)
        let living = try repository.createCategory(name: copy.livingCategory, scope: .expense)
        let travel = try repository.createCategory(name: copy.travelCategory, scope: .expense)
        let investmentCategory = try repository.createCategory(name: copy.investmentsCategory, scope: .asset)

        let incomeGoal = try repository.createGoal(
            title: copy.incomeGoalTitle,
            summary: copy.incomeGoalSummary,
            targetDate: Calendar.current.date(byAdding: .month, value: 6, to: .now)
        )
        let travelGoal = try repository.createGoal(
            title: copy.travelGoalTitle,
            summary: copy.travelGoalSummary,
            targetDate: Calendar.current.date(byAdding: .month, value: 2, to: .now),
            state: .planned
        )

        let partTimeProject = try repository.createProject(
            title: copy.partTimeProjectTitle,
            summary: copy.partTimeProjectSummary,
            deadline: Calendar.current.date(byAdding: .month, value: 1, to: .now),
            goal: incomeGoal
        )
        let demoTripProject = try repository.createProject(
            title: copy.demoTripProjectTitle,
            summary: copy.demoTripProjectSummary,
            deadline: Calendar.current.date(byAdding: .month, value: 1, to: .now),
            goal: travelGoal
        )

        _ = try repository.createTask(
            title: copy.partTimeTaskTitle,
            dueDate: Calendar.current.date(byAdding: .day, value: 3, to: .now),
            priority: .high,
            project: partTimeProject
        )
        _ = try repository.createTask(
            title: copy.travelTaskTitle,
            dueDate: Calendar.current.date(byAdding: .day, value: 7, to: .now),
            priority: .medium,
            project: demoTripProject
        )
        _ = try repository.createCalendarItem(
            title: copy.weeklyReviewTitle,
            startDate: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now,
            endDate: Calendar.current.date(byAdding: .day, value: 1, to: .now.addingTimeInterval(60 * 60)) ?? .now.addingTimeInterval(60 * 60),
            allDay: false,
            location: copy.weeklyReviewLocation,
            note: copy.weeklyReviewNote,
            project: partTimeProject
        )
        _ = try repository.createLedgerEntry(
            title: copy.sampleIncomeTitle,
            direction: .income,
            amount: 1200,
            occurredOn: .now,
            account: cash,
            category: partTime,
            project: partTimeProject,
            note: copy.sampleIncomeNote
        )
        _ = try repository.createPlannedEntry(
            title: copy.airfareTitle,
            direction: .expense,
            amount: 7500,
            dueOn: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
            account: bank,
            category: travel,
            project: demoTripProject,
            note: copy.airfareNote
        )
        _ = try repository.createAssetSnapshot(
            title: copy.assetTitle,
            amount: 55579,
            capturedOn: .now,
            account: investment,
            category: investmentCategory,
            quoteSymbol: "2330",
            units: 120,
            costBasis: 10000,
            note: copy.assetNote
        )
        _ = living
    }

    public static func refreshLocalizedContentIfPossible(context: ModelContext, language: AppLanguage) throws {
        let english = templateCopy(for: .english)
        let zhHant = templateCopy(for: .traditionalChinese)
        let legacyEnglish = legacyEnglishAliases()
        let target = templateCopy(for: language)

        var changed = false

        let accounts = try context.fetch(FetchDescriptor<Account>())
        for account in accounts {
            changed = sync(&account.name, sources: [english.cashAccount, zhHant.cashAccount, legacyEnglish.cashAccount], target: target.cashAccount) || changed
            changed = sync(&account.name, sources: [english.mainBankAccount, zhHant.mainBankAccount, legacyEnglish.mainBankAccount], target: target.mainBankAccount) || changed
            changed = sync(&account.name, sources: [english.investmentAccount, zhHant.investmentAccount, legacyEnglish.investmentAccount], target: target.investmentAccount) || changed
        }

        let categories = try context.fetch(FetchDescriptor<Category>())
        for category in categories {
            changed = sync(&category.name, sources: [english.partTimeCategory, zhHant.partTimeCategory, legacyEnglish.partTimeCategory], target: target.partTimeCategory) || changed
            changed = sync(&category.name, sources: [english.livingCategory, zhHant.livingCategory, legacyEnglish.livingCategory], target: target.livingCategory) || changed
            changed = sync(&category.name, sources: [english.travelCategory, zhHant.travelCategory, legacyEnglish.travelCategory], target: target.travelCategory) || changed
            changed = sync(&category.name, sources: [english.investmentsCategory, zhHant.investmentsCategory, legacyEnglish.investmentsCategory], target: target.investmentsCategory) || changed
        }

        let goals = try context.fetch(FetchDescriptor<Goal>())
        for goal in goals {
            changed = sync(&goal.title, sources: [english.incomeGoalTitle, zhHant.incomeGoalTitle, legacyEnglish.incomeGoalTitle], target: target.incomeGoalTitle) || changed
            changed = sync(&goal.summary, sources: [english.incomeGoalSummary, zhHant.incomeGoalSummary, legacyEnglish.incomeGoalSummary], target: target.incomeGoalSummary) || changed
            changed = sync(&goal.title, sources: [english.travelGoalTitle, zhHant.travelGoalTitle, legacyEnglish.travelGoalTitle], target: target.travelGoalTitle) || changed
            changed = sync(&goal.summary, sources: [english.travelGoalSummary, zhHant.travelGoalSummary, legacyEnglish.travelGoalSummary], target: target.travelGoalSummary) || changed
        }

        let projects = try context.fetch(FetchDescriptor<Project>())
        for project in projects {
            changed = sync(&project.title, sources: [english.partTimeProjectTitle, zhHant.partTimeProjectTitle, legacyEnglish.partTimeProjectTitle], target: target.partTimeProjectTitle) || changed
            changed = sync(&project.summary, sources: [english.partTimeProjectSummary, zhHant.partTimeProjectSummary, legacyEnglish.partTimeProjectSummary], target: target.partTimeProjectSummary) || changed
            changed = sync(&project.title, sources: [english.demoTripProjectTitle, zhHant.demoTripProjectTitle, legacyEnglish.demoTripProjectTitle], target: target.demoTripProjectTitle) || changed
            changed = sync(&project.summary, sources: [english.demoTripProjectSummary, zhHant.demoTripProjectSummary, legacyEnglish.demoTripProjectSummary], target: target.demoTripProjectSummary) || changed
        }

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        for task in tasks {
            changed = sync(&task.title, sources: [english.partTimeTaskTitle, zhHant.partTimeTaskTitle, legacyEnglish.partTimeTaskTitle], target: target.partTimeTaskTitle) || changed
            changed = sync(&task.title, sources: [english.travelTaskTitle, zhHant.travelTaskTitle, legacyEnglish.travelTaskTitle], target: target.travelTaskTitle) || changed
        }

        let calendarItems = try context.fetch(FetchDescriptor<CalendarItem>())
        for item in calendarItems {
            changed = sync(&item.title, sources: [english.weeklyReviewTitle, zhHant.weeklyReviewTitle, legacyEnglish.weeklyReviewTitle], target: target.weeklyReviewTitle) || changed
            changed = sync(&item.location, sources: [english.weeklyReviewLocation, zhHant.weeklyReviewLocation, legacyEnglish.weeklyReviewLocation], target: target.weeklyReviewLocation) || changed
            changed = sync(&item.note, sources: [english.weeklyReviewNote, zhHant.weeklyReviewNote, legacyEnglish.weeklyReviewNote], target: target.weeklyReviewNote) || changed
        }

        let ledgerEntries = try context.fetch(FetchDescriptor<LedgerEntry>())
        for entry in ledgerEntries {
            changed = sync(&entry.title, sources: [english.sampleIncomeTitle, zhHant.sampleIncomeTitle, legacyEnglish.sampleIncomeTitle], target: target.sampleIncomeTitle) || changed
            changed = sync(&entry.note, sources: [english.sampleIncomeNote, zhHant.sampleIncomeNote, legacyEnglish.sampleIncomeNote], target: target.sampleIncomeNote) || changed
        }

        let plannedEntries = try context.fetch(FetchDescriptor<PlannedEntry>())
        for entry in plannedEntries {
            changed = sync(&entry.title, sources: [english.airfareTitle, zhHant.airfareTitle, legacyEnglish.airfareTitle], target: target.airfareTitle) || changed
            changed = sync(&entry.note, sources: [english.airfareNote, zhHant.airfareNote, legacyEnglish.airfareNote], target: target.airfareNote) || changed
        }

        let assetSnapshots = try context.fetch(FetchDescriptor<AssetSnapshot>())
        for snapshot in assetSnapshots {
            changed = sync(&snapshot.title, sources: [english.assetTitle, zhHant.assetTitle, legacyEnglish.assetTitle], target: target.assetTitle) || changed
            changed = sync(&snapshot.note, sources: [english.assetNote, zhHant.assetNote, legacyEnglish.assetNote, "Live 2330 position"], target: target.assetNote) || changed
        }

        if changed {
            try LifeOSRepository(context: context).save()
        }
    }

    private static func sync(_ value: inout String, sources: [String], target: String) -> Bool {
        guard sources.contains(value) else { return false }
        guard value != target else { return false }
        value = target
        return true
    }

    private static func legacyEnglishAliases() -> StarterTemplateCopy {
        StarterTemplateCopy(
            cashAccount: "Cash",
            mainBankAccount: "Main Bank",
            investmentAccount: "Investment",
            partTimeCategory: "Part-time Work",
            livingCategory: "Living",
            travelCategory: "Travel",
            investmentsCategory: "Investments",
            incomeGoalTitle: "Build stable personal cashflow",
            incomeGoalSummary: "Keep income, future cashflow, and asset positions visible in one place.",
            travelGoalTitle: "Keep upcoming travel financially clear",
            travelGoalSummary: "Know the budget before the trip instead of after.",
            partTimeProjectTitle: "Part-time Work income line",
            partTimeProjectSummary: "Track fixed weekly partTime income and related tasks.",
            demoTripProjectTitle: "Demo Trip trip budget",
            demoTripProjectSummary: "Break airfare, stay, and day-by-day spend into planned entries.",
            partTimeTaskTitle: "Record this week's partTime income",
            travelTaskTitle: "Draft Demo Trip trip cost buckets",
            weeklyReviewTitle: "Weekly review",
            weeklyReviewLocation: "Home",
            weeklyReviewNote: "Review cashflow and upcoming tasks.",
            sampleIncomeTitle: "Sample partTime income",
            sampleIncomeNote: "Starter template sample entry.",
            airfareTitle: "Demo Trip airfare",
            airfareNote: "Starter template planned expense.",
            assetTitle: "ETF position",
            assetNote: "Starter template asset snapshot."
        )
    }

    private static func templateCopy(for language: AppLanguage) -> StarterTemplateCopy {
        switch language {
        case .english:
            return StarterTemplateCopy(
                cashAccount: "Cash",
                mainBankAccount: "Main Bank",
                investmentAccount: "Investment",
                partTimeCategory: "Part-time Work",
                livingCategory: "Living",
                travelCategory: "Travel",
                investmentsCategory: "Investments",
                incomeGoalTitle: "Build stable personal cashflow",
                incomeGoalSummary: "Keep income, future cashflow, and asset positions visible in one place.",
                travelGoalTitle: "Keep upcoming travel financially clear",
                travelGoalSummary: "Know the budget before the trip instead of after.",
                partTimeProjectTitle: "Part-time Work income line",
                partTimeProjectSummary: "Track fixed weekly partTime income and related tasks.",
                demoTripProjectTitle: "Demo Trip trip budget",
                demoTripProjectSummary: "Break airfare, stay, and day-by-day spend into planned entries.",
                partTimeTaskTitle: "Record this week's partTime income",
                travelTaskTitle: "Draft Demo Trip trip cost buckets",
                weeklyReviewTitle: "Weekly review",
                weeklyReviewLocation: "Home",
                weeklyReviewNote: "Review cashflow and upcoming tasks.",
                sampleIncomeTitle: "Sample partTime income",
                sampleIncomeNote: "Starter template sample entry.",
                airfareTitle: "Demo Trip airfare",
                airfareNote: "Starter template planned expense.",
                assetTitle: "Demo Equity",
                assetNote: "Starter template 2330 position."
            )
        case .traditionalChinese:
            return StarterTemplateCopy(
                cashAccount: "現金",
                mainBankAccount: "主力銀行",
                investmentAccount: "投資帳戶",
                partTimeCategory: "Part-time",
                livingCategory: "生活",
                travelCategory: "旅行",
                investmentsCategory: "投資資產",
                incomeGoalTitle: "建立穩定的個人現金流",
                incomeGoalSummary: "把收入、未來現金流與資產部位集中在同一個地方看清楚。",
                travelGoalTitle: "讓近期旅遊預算保持清楚",
                travelGoalSummary: "在出發前就知道預算，而不是回來後才結算。",
                partTimeProjectTitle: "Part-time收入線",
                partTimeProjectSummary: "追蹤每週固定的Part-time收入與相關任務。",
                demoTripProjectTitle: "Demo Trip預算",
                demoTripProjectSummary: "把機票、住宿與每天花費拆成預計收支。",
                partTimeTaskTitle: "記下這週的Part-time收入",
                travelTaskTitle: "先列出Demo Trip的費用分類",
                weeklyReviewTitle: "每週回顧",
                weeklyReviewLocation: "家",
                weeklyReviewNote: "檢查現金流與接下來的任務。",
                sampleIncomeTitle: "Part-time收入示例",
                sampleIncomeNote: "起始模板的示範記帳。",
                airfareTitle: "Demo Destination機票",
                airfareNote: "起始模板的預計支出。",
                assetTitle: "Demo Equity",
                assetNote: "起始模板的 2330 持股。"
            )
        }
    }
}

private struct StarterTemplateCopy {
    let cashAccount: String
    let mainBankAccount: String
    let investmentAccount: String
    let partTimeCategory: String
    let livingCategory: String
    let travelCategory: String
    let investmentsCategory: String
    let incomeGoalTitle: String
    let incomeGoalSummary: String
    let travelGoalTitle: String
    let travelGoalSummary: String
    let partTimeProjectTitle: String
    let partTimeProjectSummary: String
    let demoTripProjectTitle: String
    let demoTripProjectSummary: String
    let partTimeTaskTitle: String
    let travelTaskTitle: String
    let weeklyReviewTitle: String
    let weeklyReviewLocation: String
    let weeklyReviewNote: String
    let sampleIncomeTitle: String
    let sampleIncomeNote: String
    let airfareTitle: String
    let airfareNote: String
    let assetTitle: String
    let assetNote: String
}
