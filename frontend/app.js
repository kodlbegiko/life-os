const navItems = [
  { id: "overview", label: "總覽", icon: "▦" },
  { id: "ledger", label: "記帳", icon: "▤" },
  { id: "planned", label: "預計收支", icon: "▣" },
  { id: "assets", label: "資產", icon: "⌁" },
  { id: "tasks", label: "任務", icon: "☷" },
  { id: "calendar", label: "行事曆", icon: "▦" },
  { id: "goals", label: "目標", icon: "◆" },
  { id: "projects", label: "專案", icon: "▰" },
  { id: "settings", label: "設定", icon: "⚙" },
];

const state = {
  section: "overview",
  dashboard: null,
  replan: null,
  selected: null,
  search: "",
};

const sidebarNav = document.getElementById("sidebarNav");
const workspace = document.getElementById("workspace");
const inspector = document.getElementById("inspector");
const demoBanner = document.getElementById("demoBanner");
const searchInput = document.getElementById("workspaceSearch");

function escapeHTML(value = "") {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatDate(value) {
  if (!value) return "未設定";
  const date = new Date(value.includes("T") ? value : `${value}T00:00:00`);
  return new Intl.DateTimeFormat("zh-TW", {
    year: "numeric",
    month: "numeric",
    day: "numeric",
  }).format(date);
}

function formatDateTime(value) {
  if (!value) return "未設定";
  return new Intl.DateTimeFormat("zh-TW", {
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(value));
}

function formatCurrency(value = 0) {
  return new Intl.NumberFormat("zh-TW", {
    style: "currency",
    currency: "TWD",
    maximumFractionDigits: 0,
  }).format(value);
}

function projectName(projectId) {
  return state.dashboard?.projects?.find((project) => project.id === projectId)?.title || "未指定專案";
}

function allTasks() {
  return state.dashboard?.tasks || [];
}

function allEvents() {
  return state.dashboard?.events || [];
}

function filtered(items, fields = ["title"]) {
  const term = state.search.trim().toLowerCase();
  if (!term) return items;
  return items.filter((item) => fields.some((field) => String(item[field] || "").toLowerCase().includes(term)));
}

function priorityLabel(priority) {
  const map = { critical: "最高", high: "高", medium: "中", low: "低" };
  return map[priority] || priority || "未設定";
}

function severityChip(value) {
  if (["critical", "high"].includes(value)) return "red";
  if (value === "medium") return "blue";
  return "green";
}

function renderNav() {
  sidebarNav.innerHTML = navItems
    .map(
      (item) => `
        <button class="nav-item ${state.section === item.id ? "is-active" : ""}" type="button" data-nav="${item.id}">
          <span class="nav-icon">${item.icon}</span>
          <span>${item.label}</span>
        </button>
      `,
    )
    .join("");
}

function pageHeading(title, subtitle) {
  return `
    <header class="page-heading">
      <h1>${escapeHTML(title)}</h1>
      <p>${escapeHTML(subtitle)}</p>
    </header>
  `;
}

function taskCard(task, options = {}) {
  const cls = task.priority === "critical" ? "is-critical" : task.priority === "high" ? "is-high" : "";
  return `
    <article class="task-card ${cls}" data-select="task" data-id="${escapeHTML(task.id || task.title)}">
      <p class="task-title">${escapeHTML(task.title)}</p>
      <div class="meta-line">
        <span>專案 ${escapeHTML(projectName(task.project_id))}</span>
        <span>截止 ${escapeHTML(formatDateTime(task.due_at))}</span>
        <span>優先級 ${escapeHTML(priorityLabel(task.priority))}</span>
        ${task.estimate_minutes ? `<span>${task.estimate_minutes} 分鐘</span>` : ""}
      </div>
      <div class="card-actions">
        <button class="card-button" type="button" data-select-button="task" data-id="${escapeHTML(task.id || task.title)}">開啟任務</button>
        <button class="card-button" type="button" data-write-action disabled>完成</button>
        <button class="card-button" type="button" data-write-action disabled>建立時間區塊</button>
        ${options.showUnschedule ? `<button class="card-button" type="button" data-write-action disabled>解除排程</button>` : ""}
      </div>
    </article>
  `;
}

function planItemCard(item, index) {
  return `
    <article class="task-card" data-select="plan" data-id="${index}">
      <p class="task-title">${escapeHTML(item.title || "未命名任務")}</p>
      <div class="meta-line">
        <span>${escapeHTML(item.time || "未排時間")}</span>
        <span>${escapeHTML(item.kind || "task")}</span>
      </div>
      <div class="card-actions">
        <button class="card-button" type="button" data-select-button="plan" data-id="${index}">開啟任務</button>
        <button class="card-button" type="button" data-write-action disabled>完成</button>
        <button class="card-button" type="button" data-write-action disabled>建立時間區塊</button>
        <button class="card-button" type="button" data-write-action disabled>解除排程</button>
      </div>
    </article>
  `;
}

function rowCard(item, kind, meta = []) {
  return `
    <article class="row-card" data-select="${kind}" data-id="${escapeHTML(item.id || item.title)}">
      <p class="row-title">${escapeHTML(item.title || "未命名")}</p>
      <div class="meta-line">${meta.map((entry) => `<span>${escapeHTML(entry)}</span>`).join("")}</div>
    </article>
  `;
}

function computeQuality() {
  const days = state.replan?.plan_days || [];
  const taskDates = new Map();
  days.forEach((day) => {
    (day.items || []).forEach((item) => {
      const dates = taskDates.get(item.title) || [];
      dates.push(day.date);
      taskDates.set(item.title, dates);
    });
  });
  const repeated = [...taskDates.values()].filter((dates) => dates.length > 1).length;
  const needsTime = (state.replan?.must_do || []).length;
  const riskDays = days.filter((day) => (day.items || []).length >= 2).length;
  const timeBlocks = allEvents().length;
  return { repeated, needsTime, riskDays, timeBlocks };
}

function renderOverview() {
  const dashboard = state.dashboard;
  const replan = state.replan;
  const todayTasks = filtered(dashboard.today?.tasks || [], ["title", "priority"]);
  const todayEvents = filtered(dashboard.today?.events || [], ["title"]);
  const conflicts = filtered(dashboard.conflicts || [], ["title", "detail", "action"]);
  const quality = computeQuality();
  const days = replan?.plan_days || [];

  workspace.innerHTML = `
    ${pageHeading("今日作戰中心", "查看今天必做、時間區塊、截止風險與未來 7 天推進。")}

    <section class="panel panel-muted week-draft">
      <div>
        <div class="section-title">
          <span class="section-symbol">▣</span>
          <h2>本週作戰草案</h2>
        </div>
        <p class="section-copy">產生可編輯的 7 天草案，每天最多 3 個均衡焦點。公開展示版不會寫入資料。</p>
        <p class="section-copy">${escapeHTML(replan?.summary || "使用「產生本週計畫」預覽橫跨比賽、賺錢、旅遊、投資與長期工作的均衡安排。")}</p>
      </div>
      <div class="action-row">
        <button id="generatePlanButton" class="action-button" type="button">產生本週計畫</button>
        <button class="action-button" type="button" disabled>全選</button>
        <button class="action-button" type="button" disabled>清除選取</button>
        <button class="action-button primary" type="button" data-write-action disabled>套用已選</button>
        <button class="action-button" type="button">關閉草案</button>
      </div>
    </section>

    <section class="summary-grid">
      <article class="panel summary-card">
        <div class="section-title"><span class="section-symbol">◎</span><h2 class="card-title">今日必做</h2></div>
        <strong class="summary-count">共 ${todayTasks.length} 項焦點</strong>
        ${todayTasks.length ? todayTasks.slice(0, 3).map((task) => `<p class="muted-text">${escapeHTML(task.title)}</p>`).join("") : `<p class="empty-note">今天還沒有焦點任務。</p>`}
      </article>
      <article class="panel summary-card">
        <div class="section-title"><span class="section-symbol">◴</span><h2 class="card-title">今日時間區塊</h2></div>
        <strong class="summary-count">時間區塊 ${todayEvents.length}</strong>
        ${todayEvents.length ? todayEvents.map((event) => `<p class="muted-text">${escapeHTML(event.title)}</p>`).join("") : `<p class="empty-note">今天沒有時間區塊。</p>`}
      </article>
      <article class="panel summary-card">
        <div class="section-title"><span class="section-symbol">▲</span><h2 class="card-title">截止風險</h2></div>
        <strong class="summary-count">風險 ${conflicts.length}</strong>
        ${conflicts.length ? conflicts.slice(0, 2).map((item) => `<p class="muted-text">${escapeHTML(item.title)}</p>`).join("") : `<p class="empty-note">未來 7 天沒有高風險截止日。</p>`}
      </article>
    </section>

    <section class="panel quality-panel">
      <div class="quality-top">
        <div>
          <div class="section-title"><span class="section-symbol">✿</span><h2>排程品質</h2></div>
          <p class="section-copy">重複安排仍然有效，這裡只標示需要注意的地方。</p>
        </div>
        <div class="chip-row">
          <span class="chip">重複 ${quality.repeated}</span>
          <span class="chip">需補時段 ${quality.needsTime}</span>
          <span class="chip green">風險日 ${quality.riskDays}</span>
        </div>
      </div>
      <p class="muted-text">${quality.needsTime ? "重要焦點建議補上同日時間區塊，否則容易只停留在待辦清單。" : "排程品質目前看起來可執行。"}</p>
    </section>

    <section class="panel board-panel">
      <div class="board-head">
        <div>
          <div class="section-title"><span class="section-symbol">☷</span><h2>7 天排程板</h2></div>
          <p class="section-copy">水平捲動可查看完整 7 天</p>
        </div>
        <p class="muted-text">把任務拖到這裡，或使用每張卡片上的按鈕。</p>
      </div>
      <div class="board-scroll">
        <div class="day-track">
          ${days
            .map((day, dayIndex) => {
              const items = day.items || [];
              return `
                <section class="day-column">
                  <h3>${escapeHTML(formatDate(day.date))}</h3>
                  <div class="chip-row">
                    <span class="chip blue">共 ${items.length} 項焦點</span>
                    <span class="chip green">已顯示全部項目</span>
                  </div>
                  <div class="day-separator"></div>
                  <div class="chip-row">
                    <span class="chip">重複 0</span>
                    <span class="chip">需補時段 ${items.length}</span>
                    <span class="chip">已排時段 0</span>
                    <span class="chip">風險 ${items.length ? 1 : 0}</span>
                  </div>
                  ${items.length ? items.map((item, itemIndex) => planItemCard(item, `${dayIndex}-${itemIndex}`)).join("") : `<p class="empty-note">把任務拖到這裡</p>`}
                </section>
              `;
            })
            .join("")}
        </div>
      </div>
    </section>
  `;
}

function renderTasks() {
  const tasks = filtered(allTasks(), ["title", "priority", "project_id"]);
  workspace.innerHTML = `
    ${pageHeading("任務", "管理待辦、優先級、截止日與專案連結。")}
    <section class="panel list-panel">
      ${tasks.length ? tasks.map((task) => taskCard(task, { showUnschedule: true })).join("") : `<p class="empty-note">目前沒有任務。</p>`}
    </section>
  `;
}

function renderProjects() {
  const projects = filtered(state.dashboard.projects || [], ["title", "summary", "priority"]);
  workspace.innerHTML = `
    ${pageHeading("專案", "查看每條工作線的 readiness、deadline 與下一個缺口。")}
    <section class="data-grid">
      ${projects
        .map((project) => rowCard(project, "project", [
          `Readiness ${project.readiness ?? 0}%`,
          `Deadline ${formatDate(project.deadline)}`,
          `Open tasks ${project.open_tasks ?? 0}`,
          `Risk ${project.risk || "normal"}`,
        ]))
        .join("")}
    </section>
  `;
}

function renderGoals() {
  const goals = filtered(state.dashboard.goals || [], ["title", "why", "priority"]);
  workspace.innerHTML = `
    ${pageHeading("目標", "長期方向、成功定義與目前優先順序。")}
    <section class="data-grid">
      ${goals.map((goal) => rowCard(goal, "goal", [`${goal.horizon || "未設定"}`, `Target ${formatDate(goal.target_date)}`, `Priority ${priorityLabel(goal.priority)}`])).join("")}
    </section>
  `;
}

function renderCalendar() {
  const events = filtered(allEvents(), ["title", "location"]);
  workspace.innerHTML = `
    ${pageHeading("行事曆", "本機 Life OS 事件與時間區塊。")}
    <section class="panel list-panel">
      ${events.length ? events.map((event) => rowCard(event, "event", [`${formatDateTime(event.start_at)}`, event.location || "無地點"])).join("") : `<p class="empty-note">目前沒有事件。公開展示版不連 Apple Calendar。</p>`}
    </section>
  `;
}

function renderCashflow(kind) {
  const cashflow = state.dashboard.cashflow || {};
  const summary = cashflow.summary || {};
  const recent = cashflow.recent || [];
  const upcoming = cashflow.upcoming || [];
  const assets = cashflow.asset_positions || [];
  const pageMap = {
    ledger: ["記帳", "實際收入、支出與最近流水帳。"],
    planned: ["預計收支", "未來 30 天預計收入與支出。"],
    assets: ["資產", "資產快照與投資部位。"],
  };
  const items = kind === "ledger" ? recent : kind === "planned" ? upcoming : assets;
  workspace.innerHTML = `
    ${pageHeading(pageMap[kind][0], pageMap[kind][1])}
    <section class="metric-grid">
      <div class="metric-card"><span>本月收入</span><strong>${formatCurrency(summary.month_income || 0)}</strong></div>
      <div class="metric-card"><span>本月支出</span><strong>${formatCurrency(summary.month_expense || 0)}</strong></div>
      <div class="metric-card"><span>本月淨流</span><strong>${formatCurrency(summary.month_net || 0)}</strong></div>
      <div class="metric-card"><span>資產總額</span><strong>${formatCurrency(summary.asset_total || 0)}</strong></div>
    </section>
    <section class="panel list-panel">
      ${items.length ? items.map((item) => rowCard(item, kind, [item.kind || item.category || "demo", formatCurrency(item.amount || 0), formatDate(item.date || item.due_at)])).join("") : `<p class="empty-note">公開展示資料目前沒有${pageMap[kind][0]}項目。</p>`}
    </section>
  `;
}

function renderSettings() {
  workspace.innerHTML = `
    ${pageHeading("設定", "公開展示版設定與資料狀態。")}
    <section class="panel list-panel">
      <div class="section-title"><span class="section-symbol">⚙</span><h2>Public Demo</h2></div>
      <p class="muted-text">目前模式：唯讀。所有新增、刪除、同步、匯入操作都已停用。</p>
      <p class="muted-text">資料來源：sanitized demo data，不包含私人 SwiftData store、本機備份或 Apple Calendar 資料。</p>
    </section>
  `;
}

function renderWorkspace() {
  if (!state.dashboard) {
    workspace.innerHTML = `${pageHeading("Life OS", "載入中...")}`;
    return;
  }

  renderNav();
  if (demoBanner) {
    demoBanner.hidden = !state.dashboard.app_mode?.publicDemo;
  }
  document.body.classList.toggle("is-read-only", Boolean(state.dashboard.app_mode?.readOnly));

  if (state.section === "overview") renderOverview();
  if (state.section === "tasks") renderTasks();
  if (state.section === "projects") renderProjects();
  if (state.section === "goals") renderGoals();
  if (state.section === "calendar") renderCalendar();
  if (["ledger", "planned", "assets"].includes(state.section)) renderCashflow(state.section);
  if (state.section === "settings") renderSettings();

  renderInspector();
}

function findSelected(kind, id) {
  if (!kind || !id) return null;
  if (kind === "task") return allTasks().find((item) => item.id === id);
  if (kind === "project") return state.dashboard.projects?.find((item) => item.id === id);
  if (kind === "goal") return state.dashboard.goals?.find((item) => item.id === id);
  if (kind === "event") return allEvents().find((item) => item.id === id);
  if (["ledger", "planned", "assets"].includes(kind)) {
    const cashflow = state.dashboard.cashflow || {};
    const pool = [...(cashflow.recent || []), ...(cashflow.upcoming || []), ...(cashflow.asset_positions || [])];
    return pool.find((item) => item.id === id || item.title === id);
  }
  if (kind === "plan") {
    const [dayIndex, itemIndex] = String(id).split("-").map(Number);
    return state.replan?.plan_days?.[dayIndex]?.items?.[itemIndex];
  }
  return null;
}

function renderInspector() {
  const selected = state.selected ? findSelected(state.selected.kind, state.selected.id) : null;
  if (!selected) {
    inspector.className = "inspector";
    inspector.innerHTML = `
      <div class="inspector-empty-icon" aria-hidden="true"></div>
      <h2>檢查面板</h2>
      <p>選一筆資料來檢視或編輯。</p>
    `;
    return;
  }

  inspector.className = "inspector is-filled";
  const title = selected.title || "選取項目";
  const fields = [
    ["類型", state.selected.kind],
    ["專案", selected.project_id ? projectName(selected.project_id) : "未指定"],
    ["優先級", priorityLabel(selected.priority)],
    ["截止", formatDateTime(selected.due_at || selected.deadline || selected.target_date)],
    ["狀態", selected.status || selected.stage || "demo"],
    ["摘要", selected.summary || selected.why || selected.reason || selected.time || "公開展示版僅供檢視"],
  ];

  inspector.innerHTML = `
    <article class="inspector-card">
      <h2>${escapeHTML(title)}</h2>
      <div class="inspector-fields">
        ${fields
          .map(
            ([label, value]) => `
              <div class="field-row">
                <span>${escapeHTML(label)}</span>
                <span>${escapeHTML(value)}</span>
              </div>
            `,
          )
          .join("")}
      </div>
      <div class="action-row">
        <button class="action-button primary" type="button" disabled>Save</button>
        <button class="action-button" type="button" disabled>Delete</button>
      </div>
      <p class="muted-text">Public Demo 是唯讀模式，這裡展示 inspector 結構，不寫入資料。</p>
    </article>
  `;
}

async function loadDashboard() {
  const response = await fetch("/api/dashboard");
  if (!response.ok) throw new Error(`Dashboard failed: ${response.status}`);
  state.dashboard = await response.json();
}

async function loadReplan() {
  const response = await fetch("/api/replan-week");
  if (!response.ok) throw new Error(`Replan failed: ${response.status}`);
  state.replan = await response.json();
}

async function init() {
  renderNav();
  renderInspector();
  workspace.innerHTML = `${pageHeading("Life OS", "載入中...")}`;
  try {
    await Promise.all([loadDashboard(), loadReplan()]);
    renderWorkspace();
  } catch (error) {
    workspace.innerHTML = `${pageHeading("Life OS", "載入失敗")}
      <section class="panel list-panel"><p class="empty-note">${escapeHTML(error.message)}</p></section>`;
  }
}

sidebarNav.addEventListener("click", (event) => {
  const button = event.target.closest("[data-nav]");
  if (!button) return;
  state.section = button.dataset.nav;
  state.selected = null;
  renderWorkspace();
});

workspace.addEventListener("click", async (event) => {
  const generate = event.target.closest("#generatePlanButton");
  if (generate) {
    generate.textContent = "產生中...";
    await loadReplan();
    renderWorkspace();
    return;
  }

  const selectButton = event.target.closest("[data-select-button]");
  const card = event.target.closest("[data-select]");
  const target = selectButton || card;
  if (!target) return;
  state.selected = { kind: target.dataset.selectButton || target.dataset.select, id: target.dataset.id };
  renderInspector();
});

searchInput.addEventListener("input", (event) => {
  state.search = event.target.value;
  renderWorkspace();
});

document.querySelectorAll("[data-disabled-action]").forEach((button) => {
  button.addEventListener("click", () => {
    state.selected = null;
    renderInspector();
  });
});

init();
