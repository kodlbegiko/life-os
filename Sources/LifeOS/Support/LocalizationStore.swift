import Foundation
import Observation
import LifeOSCore

@Observable
@MainActor
final class LocalizationStore {
    private static let storageKey = "lifeos.selectedLanguage"

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.storageKey),
           let language = AppLanguage(rawValue: stored) {
            self.language = language
        } else if Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true {
            self.language = .traditionalChinese
        } else {
            self.language = .english
        }
    }

    var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    func text(_ english: String) -> String {
        switch language {
        case .english:
            return english
        case .traditionalChinese:
            return zhHantTranslations[english] ?? english
        }
    }

    func format(_ english: String, _ arguments: CVarArg...) -> String {
        String(format: text(english), locale: locale, arguments: arguments)
    }

    private let zhHantTranslations: [String: String] = [
        "Life OS": "Life OS",
        "Search current workspace": "搜尋目前工作區",
        "New Ledger Entry": "新增記帳項目",
        "New Planned Entry": "新增預計收支",
        "New Task": "新增任務",
        "New Calendar Item": "新增行程事件",
        "Toggle Inspector": "切換檢查面板",
        "Clear Search": "清除搜尋",
        "Hide Inspector": "隱藏檢查面板",
        "Show Inspector": "顯示檢查面板",
        "Search Active": "搜尋中",
        "Clear": "清除",
        "Start with a clean Life OS": "從乾淨的 Life OS 開始",
        "This app starts with an empty local database. Install the starter template if you want a quick structure to edit.": "這個 app 會從空白的本機資料庫開始。如果你想快速上手，可以先安裝起始模板。",
        "Install Starter Template": "安裝起始模板",
        "Overview": "總覽",
        "See cashflow, urgent work, and the projects most likely to drift.": "查看現金流、緊急工作，以及最可能失速的專案。",
        "Daily Command Center": "今日作戰中心",
        "See today's must-do work, time blocks, deadline risk, and the next 7 days.": "查看今天必做、時間區塊、截止風險與未來 7 天推進。",
        "Today's Must Do": "今日必做",
        "No focus items for today.": "今天還沒有焦點任務。",
        "Today Time Blocks": "今日時間區塊",
        "No time blocks today.": "今天沒有時間區塊。",
        "Deadline Risk": "截止風險",
        "No risky deadlines in the next 7 days.": "未來 7 天沒有高風險截止日。",
        "Next 7 Days": "未來 7 天",
        "7-Day Schedule Board": "7 天排程板",
        "Drag tasks here or use the buttons on each card.": "把任務拖到這裡，或使用每張卡片上的按鈕。",
        "Scroll horizontally to see all 7 days": "水平捲動可查看完整 7 天",
        "Focus %d": "焦點 %d",
        "Total Focus %d": "共 %d 項焦點",
        "Time blocks %d": "時間區塊 %d",
        "Risks %d": "風險 %d",
        "All items shown": "已顯示全部項目",
        "Drop tasks here": "把任務拖到這裡",
        "No suggested focus": "沒有建議焦點",
        "Manual": "手動",
        "Suggested": "建議",
        "Manual plan": "手動排程",
        "Suggested plan": "系統建議",
        "Create Focus": "建立焦點",
        "Create Time Block": "建立時間區塊",
        "Open": "開啟",
        "Open Task": "開啟任務",
        "Postpone Tomorrow": "延後明天",
        "Unschedule": "解除排程",
        "Unschedule Task Only": "只解除任務排程",
        "Move Up": "上移",
        "Move Down": "下移",
        "More": "更多",
        "Task time block": "任務時間區塊",
        "Calendar event": "行程事件",
        "This Week Battle Plan": "本週作戰草案",
        "Generate a 7-day draft with up to 3 balanced focus items per day. Nothing is saved until you apply it.": "產生 7 天草案，每天最多 3 個均衡焦點。按下套用前不會寫入資料。",
        "Generate an editable 7-day draft with up to 3 balanced focus items per day. Nothing is saved until you apply it.": "產生可編輯的 7 天草案，每天最多 3 個均衡焦點。按下套用前不會寫入資料。",
        "Generate Week Plan": "產生本週計畫",
        "Apply Week Plan": "套用本週計畫",
        "Apply Selected": "套用已選",
        "Select All": "全選",
        "Clear All": "清除選取",
        "Dismiss Draft": "關閉草案",
        "No eligible open tasks for this week's draft. Add tasks or install the personal plan template first.": "目前沒有可排入本週草案的未完成任務。先新增任務或安裝個人計畫模板。",
        "Use Generate Week Plan to preview a balanced plan across competitions, earning, travel, investment, and long-term work.": "使用「產生本週計畫」預覽橫跨比賽、賺錢、旅遊、投資與長期工作的均衡安排。",
        "No draft focus": "沒有草案焦點",
        "Draft day": "草案日期",
        "Reason": "原因",
        "Suggested time": "建議時間",
        "Change Suggested Time": "更改建議時間",
        "Move Previous Day": "移到前一天",
        "Move Next Day": "移到後一天",
        "Remove from Draft": "從草案移除",
        "Conflict": "衝突",
        "Skipped time block due to conflict": "因時間衝突略過時間區塊",
        "Will auto-find available slot": "會自動尋找可用空檔",
        "Conflict detected": "偵測到衝突",
        "Conflict: %@": "衝突：%@",
        "Week plan applied: %d focus added, %d time blocks added, %d existing skipped, %d conflicts skipped.": "本週計畫已套用：新增 %d 個焦點、%d 個時間區塊，略過 %d 個既有項目、%d 個衝突。",
        "Week plan applied: %d focus added, %d existing focus, %d time blocks added, %d rescheduled, %d existing time blocks, %d conflict skipped, %d focus-only no slot.": "本週計畫已套用：新增 %d 個焦點、%d 個既有焦點、%d 個時間區塊、%d 個自動改排、%d 個既有時間區塊、%d 個衝突略過、%d 個只建立焦點。",
        "Created at %@": "已建立於 %@",
        "Created": "已建立",
        "Moved to %@": "已改排到 %@",
        "Moved to available slot": "已改排到可用空檔",
        "Already planned": "已存在",
        "Focus only: no available slot": "只建立焦點：沒有可用空檔",
        "Schedule Quality": "排程品質",
        "Repeated schedules stay valid; this panel shows what needs attention.": "重複安排仍然有效；這裡只標示需要注意的地方。",
        "Schedule quality looks executable.": "排程品質目前看起來可執行。",
        "Repeated %d": "重複 %d",
        "Needs Time Block %d": "需補時段 %d",
        "Scheduled Time Blocks %d": "已排時段 %d",
        "Risk Days %d": "風險日 %d",
        "Repeated": "重複安排",
        "Needs Time Block": "需要補時間區塊",
        "Important focus without time block": "重要焦點尚未安排時間區塊",
        "Scheduled on %d days": "已排在 %d 天",
        "Duplicate Dates": "查看重複日期",
        "High priority focus": "高優先級焦點",
        "Due within 7 days": "7 天內到期",
        "Project deadline within 7 days": "專案 7 天內截止",
        "signals": "訊號",
        "Total Wealth": "總資產",
        "Liquid cash plus non-liquid assets": "可動用現金加上非流動資產",
        "Callable Now": "現在可動用",
        "Current cash, bank, and digital balances": "目前的現金、銀行與數位帳戶餘額",
        "Invested": "投資中",
        "Latest non-liquid asset snapshots": "最新的非流動資產快照",
        "Includes live Taiwan quotes": "包含台股即時公開報價",
        "Reserved 30D": "30天預留",
        "Planned outgoing commitments": "未來 30 天預計支出承諾",
        "Free Cash": "自由現金",
        "Callable now minus planned expense": "可動用現金扣掉預計支出",
        "30D Outlook": "30天展望",
        "Callable now plus planned net": "可動用現金加上未來 30 天淨流入",
        "Money Accounts": "資金帳戶",
        "Add ledger entries to show live callable balances by account.": "先新增記帳項目，才會顯示各帳戶的可動用餘額。",
        "Money Signals": "資金訊號",
        "Callable now": "現在可動用",
        "Reserved next 30 days": "未來 30 天預留",
        "Free after reserve": "扣除預留後",
        "Live investments": "即時投資資產",
        "This Month Income": "本月收入",
        "Actual posted income": "已入帳收入",
        "This Month Expense": "本月支出",
        "Actual posted expense": "已入帳支出",
        "This Month Net": "本月淨額",
        "Income minus expense": "收入減去支出",
        "Next 30 Days": "未來 30 天",
        "Planned net movement": "預計淨現金流",
        "Latest snapshot total": "最新快照總額",
        "Assets": "資產",
        "No overview signals matched": "沒有符合的總覽訊號",
        "Try a broader keyword or clear the current search.": "換一個更寬鬆的關鍵字，或直接清除目前搜尋。",
        "Urgent Tasks": "緊急任務",
        "No urgent tasks match the current search.": "目前搜尋下沒有符合的緊急任務。",
        "No urgent tasks.": "目前沒有緊急任務。",
        "No due date": "沒有截止日",
        "Upcoming Planned": "即將到來的預計收支",
        "No planned entries match the current search.": "目前搜尋下沒有符合的預計收支。",
        "No planned entries in the next 30 days.": "未來 30 天沒有預計收支。",
        "Today": "今天",
        "No calendar items match the current search.": "目前搜尋下沒有符合的行程。",
        "No events on the calendar today.": "今天沒有已排定的事件。",
        "Conflicts": "衝突",
        "No conflicts match the current search.": "目前搜尋下沒有符合的衝突。",
        "No major conflicts right now.": "目前沒有明顯衝突。",
        "Project Readiness": "專案就緒度",
        "Open tasks: %d": "未完成任務：%d",
        "No deadline": "沒有截止日",
        "Ledger": "記帳",
        "Actual cash movement only. Use this when money already moved.": "只記錄實際已發生的現金流。錢真的動了才記在這裡。",
        "ledger entries": "記帳項目",
        "No ledger entries yet": "還沒有記帳項目",
        "Use the toolbar or this section to record actual income and expense.": "用工具列或這個區塊，記錄實際收入與支出。",
        "No ledger entries matched": "沒有符合的記帳項目",
        "Try a different keyword or clear the current search.": "換一個關鍵字，或清除目前搜尋。",
        "Planned": "預計收支",
        "Future money that has not happened yet.": "尚未發生的未來現金流。",
        "planned entries": "預計收支",
        "No planned entries yet": "還沒有預計收支",
        "Planned entries become your next 30 day forecast.": "預計收支會組成你未來 30 天的現金流預測。",
        "No planned entries matched": "沒有符合的預計收支",
        "Settle": "轉為已入帳",
        "Track the latest snapshot for positions you care about.": "追蹤你在意部位的最新資產快照。",
        "asset snapshots": "資產快照",
        "New Asset Snapshot": "新增資產快照",
        "No asset snapshots yet": "還沒有資產快照",
        "Create a snapshot when you want to track current balance or investment value.": "想追蹤目前餘額或投資市值時，就新增一筆資產快照。",
        "No asset snapshots matched": "沒有符合的資產快照",
        "Taiwan Live Quotes": "台股即時公開報價",
        "Public TWSE quote refresh for tracked holdings such as 2330.": "對已追蹤持股（例如 2330）刷新證交所公開報價。",
        "Refresh Now": "立即刷新",
        "Tracked": "追蹤中",
        "Live Value": "即時市值",
        "Unrealized": "未實現損益",
        "Day Change": "當日漲跌",
        "Last refresh: %@": "上次刷新：%@",
        "shares": "股",
        "Day %@": "當日 %@",
        "Snapshot value": "快照金額",
        "Tasks": "任務",
        "Use tasks for next actions, not vague intentions.": "任務是下一步行動，不是模糊想法。",
        "tasks": "任務",
        "No tasks yet": "還沒有任務",
        "Tasks power readiness, conflicts, and today focus.": "任務會驅動就緒度、衝突判斷與今天重點。",
        "No tasks matched": "沒有符合的任務",
        "Reopen": "重新開啟",
        "Done": "完成",
        "Plan Focus": "排進每日焦點",
        "Time Block": "建立時間區塊",
        "Schedule Task": "安排任務",
        "Save Schedule": "儲存排程",
        "Schedule Mode": "排程模式",
        "Planned Date": "排定日期",
        "Start Time": "開始時間",
        "End Time": "結束時間",
        "Focus": "每日焦點",
        "Calendar": "行事曆",
        "Events create hard time blocks and conflict signals.": "事件會形成硬時間區塊，也會產生衝突訊號。",
        "calendar items": "行程事件",
        "No calendar items yet": "還沒有行程事件",
        "Create events when time must be reserved, not just remembered.": "當一段時間必須被保留時，才把它建立成事件。",
        "No calendar items matched": "沒有符合的行程事件",
        "Goals": "目標",
        "Goals define where the system is trying to take you.": "目標定義了這個系統要把你帶去哪裡。",
        "goals": "目標",
        "No goals yet": "還沒有目標",
        "Create a goal before you create too many disconnected projects.": "先建立目標，再開始建立太多彼此脫節的專案。",
        "No goals matched": "沒有符合的目標",
        "No target date": "沒有目標日期",
        "Projects": "專案",
        "Projects connect money, tasks, and calendar blocks into a working line.": "專案把金錢、任務與行程串成一條真正能執行的工作線。",
        "projects": "專案",
        "No projects yet": "還沒有專案",
        "Projects are where goals become something the week can actually carry.": "專案會把目標變成這週真的能承載的工作。",
        "No projects matched": "沒有符合的專案",
        "Settings": "設定",
        "Manage supporting entities and starter template tools.": "管理基礎資料與起始模板工具。",
        "Starter Template": "起始模板",
        "Install a small local template if you want accounts, categories, a goal, and a couple of starter records.": "如果你想快速得到帳戶、分類、目標與幾筆起始資料，可以安裝一份小型本地模板。",
        "Personal Plan Template": "個人計畫模板",
        "Install goals, projects, tasks, and calendar blocks for competitions, Demo Trip travel, earning, 2330, Skill Certification L1, Seasonal work, and the academic path.": "安裝競賽、Demo Trip、賺錢、2330、Skill Certification L1、Seasonal Work與Academic Roadmap的目標、專案、任務與行程區塊。",
        "Install Personal Plan Template": "安裝個人計畫模板",
        "Personal plan template updated: %d added, %d skipped.": "個人計畫模板已更新：新增 %d 項，略過 %d 項。",
        "Personal plan template failed. Check logs and try again.": "個人計畫模板安裝失敗。請檢查紀錄後再試一次。",
        "Next task: %@": "下一步：%@",
        "No open tasks": "沒有未完成任務",
        "Project: %@": "專案：%@",
        "Accounts": "帳戶",
        "New Account": "新增帳戶",
        "No accounts yet.": "還沒有帳戶。",
        "Categories": "分類",
        "New Category": "新增分類",
        "No categories yet.": "還沒有分類。",
        "Language": "語言",
        "Switch between English and Traditional Chinese without restarting the app.": "不用重新啟動 app，就能在英文與繁體中文之間切換。",
        "Inspector": "檢查面板",
        "Select a record to inspect or edit it.": "選一筆資料來檢視或編輯。",
        "Ledger Entry": "記帳項目",
        "Direction": "方向",
        "Title": "標題",
        "Amount": "金額",
        "Occurred On": "發生日",
        "Note": "備註",
        "Planned Entry": "預計收支",
        "Due On": "到期日",
        "Convert To Ledger": "轉成已入帳",
        "Asset Snapshot": "資產快照",
        "Reference Amount": "參考金額",
        "Captured On": "記錄日",
        "Taiwan Live Quote": "台股即時報價",
        "Ticker": "代號",
        "Units / Shares": "持有股數",
        "Cost Basis (optional)": "成本（可選）",
        "Live market value: %@": "即時市值：%@",
        "Quote: %@ · Updated %@ %@": "報價：%@ · 更新於 %@ %@",
        "Day change: %@": "當日漲跌：%@",
        "Unrealized P/L: %@": "未實現損益：%@",
        "No live quote loaded yet. Open Assets and refresh quotes.": "目前還沒有載入即時報價。先到 Assets 頁面刷新報價。",
        "Task": "任務",
        "Status": "狀態",
        "Priority": "優先級",
        "Due": "截止",
        "Source": "來源",
        "Due Date": "截止日",
        "No linked project": "沒有連結的專案",
        "Calendar Item": "行程事件",
        "Start": "開始",
        "End": "結束",
        "All Day": "全天",
        "Location": "地點",
        "Goal": "目標",
        "State": "狀態",
        "Target Date": "目標日期",
        "Summary": "摘要",
        "Project": "專案",
        "Deadline": "截止日",
        "No linked goal": "沒有連結的目標",
        "Account": "帳戶",
        "Name": "名稱",
        "Kind": "類型",
        "Category": "分類",
        "Scope": "範圍",
        "Delete": "刪除",
        "Save": "儲存",
        "New Goal": "新增目標",
        "Save Goal": "儲存目標",
        "Has Due Date": "有截止日",
        "Save Task": "儲存任務",
        "Save Calendar Item": "儲存行程事件",
        "New Project": "新增專案",
        "Save Project": "儲存專案",
        "Has Target Date": "有目標日期",
        "Has Deadline": "有截止日",
        "Save Account": "儲存帳戶",
        "Save Category": "儲存分類",
        "Save Asset Snapshot": "儲存資產快照",
        "Save Planned Entry": "儲存預計收支",
        "Save Ledger Entry": "儲存記帳項目",
        "None": "無",
        "Cancel": "取消",
        "Ticker (example: 2330)": "代號（例如：2330）"
    ]
}

extension AppLanguage {
    var nativeDisplayName: String {
        switch self {
        case .english:
            "English"
        case .traditionalChinese:
            "繁體中文"
        }
    }
}

extension EntryDirection {
    func localizedTitle(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.income, .english): "Income"
        case (.income, .traditionalChinese): "收入"
        case (.expense, .english): "Expense"
        case (.expense, .traditionalChinese): "支出"
        }
    }
}

extension CategoryScope {
    func localizedTitle(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.income, .english): "Income"
        case (.income, .traditionalChinese): "收入"
        case (.expense, .english): "Expense"
        case (.expense, .traditionalChinese): "支出"
        case (.asset, .english): "Asset"
        case (.asset, .traditionalChinese): "資產"
        }
    }
}

extension AccountKind {
    func localizedTitle(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.cash, .english): "Cash"
        case (.cash, .traditionalChinese): "現金"
        case (.bank, .english): "Bank"
        case (.bank, .traditionalChinese): "銀行"
        case (.digital, .english): "Digital"
        case (.digital, .traditionalChinese): "數位帳戶"
        case (.investment, .english): "Investment"
        case (.investment, .traditionalChinese): "投資"
        }
    }
}

extension GoalState {
    func localizedTitle(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.active, .english): "Active"
        case (.active, .traditionalChinese): "進行中"
        case (.planned, .english): "Planned"
        case (.planned, .traditionalChinese): "規劃中"
        case (.paused, .english): "Paused"
        case (.paused, .traditionalChinese): "暫停"
        case (.done, .english): "Done"
        case (.done, .traditionalChinese): "完成"
        }
    }
}

extension ProjectState {
    func localizedTitle(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.active, .english): "Active"
        case (.active, .traditionalChinese): "進行中"
        case (.planned, .english): "Planned"
        case (.planned, .traditionalChinese): "規劃中"
        case (.paused, .english): "Paused"
        case (.paused, .traditionalChinese): "暫停"
        case (.done, .english): "Done"
        case (.done, .traditionalChinese): "完成"
        }
    }
}

extension TaskState {
    func localizedTitle(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.todo, .english): "To Do"
        case (.todo, .traditionalChinese): "待辦"
        case (.doing, .english): "Doing"
        case (.doing, .traditionalChinese): "進行中"
        case (.done, .english): "Done"
        case (.done, .traditionalChinese): "完成"
        }
    }
}

extension TaskPriority {
    func localizedTitle(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.low, .english): "Low"
        case (.low, .traditionalChinese): "低"
        case (.medium, .english): "Medium"
        case (.medium, .traditionalChinese): "中"
        case (.high, .english): "High"
        case (.high, .traditionalChinese): "高"
        case (.critical, .english): "Critical"
        case (.critical, .traditionalChinese): "關鍵"
        }
    }
}

extension DailyPlanItemKind {
    func localizedTitle(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.focus, .english): "Focus"
        case (.focus, .traditionalChinese): "每日焦點"
        case (.timeBlock, .english): "Time Block"
        case (.timeBlock, .traditionalChinese): "時間區塊"
        }
    }
}

extension WeekPlanLine {
    func localizedTitle(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.competition, .english): "Competition"
        case (.competition, .traditionalChinese): "比賽"
        case (.earning, .english): "Earning"
        case (.earning, .traditionalChinese): "賺錢"
        case (.travel, .english): "Travel"
        case (.travel, .traditionalChinese): "旅遊"
        case (.investment, .english): "Investment"
        case (.investment, .traditionalChinese): "投資"
        case (.snow, .english): "Snow"
        case (.snow, .traditionalChinese): "seasonal training"
        case (.academic, .english): "Academic"
        case (.academic, .traditionalChinese): "學術"
        case (.general, .english): "General"
        case (.general, .traditionalChinese): "一般"
        }
    }
}

extension SidebarSection {
    func localizedTitle(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.overview, .english): "Overview"
        case (.overview, .traditionalChinese): "總覽"
        case (.ledger, .english): "Ledger"
        case (.ledger, .traditionalChinese): "記帳"
        case (.planned, .english): "Planned"
        case (.planned, .traditionalChinese): "預計收支"
        case (.assets, .english): "Assets"
        case (.assets, .traditionalChinese): "資產"
        case (.tasks, .english): "Tasks"
        case (.tasks, .traditionalChinese): "任務"
        case (.calendar, .english): "Calendar"
        case (.calendar, .traditionalChinese): "行事曆"
        case (.goals, .english): "Goals"
        case (.goals, .traditionalChinese): "目標"
        case (.projects, .english): "Projects"
        case (.projects, .traditionalChinese): "專案"
        case (.settings, .english): "Settings"
        case (.settings, .traditionalChinese): "設定"
        }
    }
}
