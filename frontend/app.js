const heroTheme = document.getElementById("heroTheme");
const snapshotGrid = document.getElementById("snapshotGrid");
const todaySummary = document.getElementById("todaySummary");
const todayTaskList = document.getElementById("todayTaskList");
const todayEventList = document.getElementById("todayEventList");
const employeeHeadline = document.getElementById("employeeHeadline");
const employeeSummary = document.getElementById("employeeSummary");
const employeeActions = document.getElementById("employeeActions");
const goalGrid = document.getElementById("goalGrid");
const taskList = document.getElementById("taskList");
const cashflowSummaryGrid = document.getElementById("cashflowSummaryGrid");
const cashflowUpcomingList = document.getElementById("cashflowUpcomingList");
const cashflowAssetList = document.getElementById("cashflowAssetList");
const cashflowCategoryList = document.getElementById("cashflowCategoryList");
const cashflowLedger = document.getElementById("cashflowLedger");
const projectGrid = document.getElementById("projectGrid");
const eventList = document.getElementById("eventList");
const conflictList = document.getElementById("conflictList");
const replanView = document.getElementById("replanView");
const captureForm = document.getElementById("captureForm");
const taskForm = document.getElementById("taskForm");
const eventForm = document.getElementById("eventForm");
const cashflowForm = document.getElementById("cashflowForm");
const taskProject = document.getElementById("taskProject");
const eventProject = document.getElementById("eventProject");
const cashflowProject = document.getElementById("cashflowProject");
const calendarSelect = document.getElementById("calendarSelect");
const importCalendarButton = document.getElementById("importCalendarButton");
const replanButton = document.getElementById("replanButton");
const statusLine = document.getElementById("statusLine");
const demoBanner = document.getElementById("demoBanner");
const paneButtons = Array.from(document.querySelectorAll("[data-pane-button]"));
const panes = Array.from(document.querySelectorAll("[data-pane]"));

const priorityClass = {
  critical: "priority-critical",
  high: "priority-high",
  medium: "priority-medium",
  low: "priority-low",
};

const cashflowKindClass = {
  income: "pill-good",
  expense: "pill-alert",
  asset: "priority-high",
};

let dashboard = null;
let appMode = { publicDemo: false, readOnly: false };

function setStatus(message, tone = "neutral") {
  statusLine.textContent = message;
  statusLine.dataset.tone = tone;
}

function badge(label, className = "") {
  return `<span class="pill ${className}">${label}</span>`;
}

function formatDateTime(value, allDay = false) {
  const date = new Date(value);
  if (allDay) {
    return new Intl.DateTimeFormat("zh-TW", {
      month: "numeric",
      day: "numeric",
      weekday: "short",
    }).format(date);
  }

  return new Intl.DateTimeFormat("zh-TW", {
    month: "numeric",
    day: "numeric",
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

function formatTimeOnly(value) {
  return new Intl.DateTimeFormat("zh-TW", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(value));
}

function formatDateOnly(value) {
  if (!value) {
    return "未設定";
  }
  const [year, month, day] = value.split("-");
  return `${year}/${month}/${day}`;
}

function formatDayLabel(value) {
  const date = new Date(`${value}T00:00`);
  return new Intl.DateTimeFormat("zh-TW", {
    month: "numeric",
    day: "numeric",
    weekday: "short",
  }).format(date);
}

function formatCurrency(value) {
  const absolute = new Intl.NumberFormat("zh-TW", {
    style: "currency",
    currency: "TWD",
    maximumFractionDigits: 0,
  }).format(Math.abs(value));

  return value < 0 ? `-${absolute}` : absolute;
}

function formatSignedAmount(entry) {
  if (entry.kind === "income") {
    return `+${formatCurrency(entry.amount)}`;
  }
  if (entry.kind === "expense") {
    return `-${formatCurrency(entry.amount)}`;
  }
  return formatCurrency(entry.amount);
}

function netToneClass(amount) {
  if (amount > 0) {
    return "is-positive";
  }
  if (amount < 0) {
    return "is-negative";
  }
  return "is-neutral";
}

function dueLabel(task) {
  if (!task.due_at) {
    return "未設定截止時間";
  }
  return `截止 ${formatDateTime(task.due_at)}`;
}

function eventWindowLabel(event) {
  if (event.all_day) {
    return "全天事件";
  }

  const sameDay = event.start_at.slice(0, 10) === event.end_at.slice(0, 10);
  if (sameDay) {
    return `${formatDateTime(event.start_at)} - ${formatTimeOnly(event.end_at)}`;
  }
  return `${formatDateTime(event.start_at)} - ${formatDateTime(event.end_at)}`;
}

function projectNameFor(projectId) {
  if (!projectId || !dashboard) {
    return "未指定專案";
  }
  const project = dashboard.projects.find((item) => item.id === projectId);
  return project ? project.title : "未指定專案";
}

function setActivePane(paneName) {
  paneButtons.forEach((button) => {
    button.classList.toggle("is-active", button.dataset.paneButton === paneName);
  });
  panes.forEach((pane) => {
    pane.classList.toggle("is-active", pane.dataset.pane === paneName);
  });
}

function fillProjectSelects(projects) {
  const options = [`<option value="">未指定</option>`]
    .concat(projects.map((project) => `<option value="${project.id}">${project.title}</option>`))
    .join("");

  taskProject.innerHTML = options;
  eventProject.innerHTML = options;
  cashflowProject.innerHTML = options;
}

function fillCalendarSelect(list) {
  if (!list.length) {
    calendarSelect.innerHTML = `<option value="">找不到可用行事曆</option>`;
    calendarSelect.disabled = true;
    importCalendarButton.disabled = true;
    return;
  }

  const preferred = list.includes("計劃安排") ? "計劃安排" : list[0];
  calendarSelect.innerHTML = list
    .map((calendar) => `<option value="${calendar}">${calendar}</option>`)
    .join("");
  calendarSelect.disabled = false;
  importCalendarButton.disabled = false;
  calendarSelect.value = preferred;
}

function applyAppMode(mode = {}) {
  appMode = {
    publicDemo: Boolean(mode.publicDemo),
    readOnly: Boolean(mode.readOnly),
  };
  document.body.classList.toggle("is-read-only", appMode.readOnly);

  if (demoBanner) {
    demoBanner.hidden = !appMode.publicDemo;
  }

  importCalendarButton.disabled = appMode.readOnly;
  calendarSelect.disabled = appMode.readOnly;

  document.querySelectorAll("form input, form textarea, form select, form button").forEach((element) => {
    element.disabled = appMode.readOnly;
  });

  document
    .querySelectorAll(
      [
        "[data-task-id]",
        "[data-task-delete-id]",
        "[data-requirement-id]",
        "[data-event-sync-id]",
        "[data-event-delete-id]",
        "[data-cashflow-id]",
        "[data-cashflow-delete-id]",
      ].join(",")
    )
    .forEach((element) => {
      element.disabled = appMode.readOnly;
      element.title = appMode.readOnly ? "Public demo is read-only." : "";
    });
}

function renderSnapshot(snapshot) {
  const items = [
    ["主線目標", snapshot.active_goals],
    ["未完成任務", snapshot.open_tasks],
    ["卡住專案", snapshot.blocked_projects],
    ["近期事件", snapshot.upcoming_events],
  ];

  snapshotGrid.innerHTML = items
    .map(
      ([label, value]) => `
        <article class="snap-card">
          <p>${label}</p>
          <strong>${value}</strong>
        </article>
      `
    )
    .join("");
}

function renderToday(today) {
  todaySummary.textContent = today.summary;

  todayTaskList.innerHTML = today.tasks.length
    ? today.tasks
        .map(
          (task) => `
            <article class="mini-card">
              <strong>${task.title}</strong>
              <span>${projectNameFor(task.project_id)} · ${task.due_at ? dueLabel(task) : `預估 ${task.estimate_minutes} 分鐘`}</span>
            </article>
          `
        )
        .join("")
    : `<p class="empty-state">今天沒有硬期限任務。</p>`;

  todayEventList.innerHTML = today.events.length
    ? today.events
        .map(
          (event) => `
            <article class="mini-card">
              <strong>${event.title}</strong>
              <span>${eventWindowLabel(event)}</span>
            </article>
          `
        )
        .join("")
    : `<p class="empty-state">今天沒有排定事件。</p>`;
}

function renderEmployee(brief) {
  employeeHeadline.textContent = brief.headline;
  employeeSummary.textContent = brief.summary;
  employeeActions.innerHTML = brief.actions
    .map(
      (action) => `
        <li>
          <strong>${action.title}</strong>
          <span>${action.reason}</span>
        </li>
      `
    )
    .join("");
}

function renderGoals(goals) {
  goalGrid.innerHTML = goals
    .map(
      (goal) => `
        <article class="goal-card">
          <div class="goal-copy">
            <div class="goal-meta">
              ${badge(goal.horizon)}
              ${badge(goal.priority, priorityClass[goal.priority])}
              ${goal.status ? badge(goal.status) : ""}
            </div>
            <h3>${goal.title}</h3>
            <p>${goal.why}</p>
          </div>
          <div class="goal-footer">
            <span>完成定義</span>
            <strong>${goal.success_definition}</strong>
            <span>目標日期 ${formatDateOnly(goal.target_date)}</span>
          </div>
        </article>
      `
    )
    .join("");
}

function renderTasks(tasks) {
  if (!tasks.length) {
    taskList.innerHTML = `<p class="empty-state">目前沒有待處理任務。</p>`;
    return;
  }

  taskList.innerHTML = tasks
    .map(
      (task) => `
        <article class="task-card ${task.status === "done" ? "is-done" : ""}">
          <div class="task-main">
            <div class="task-top">
              ${badge(task.priority, priorityClass[task.priority])}
              ${task.blocking ? badge("blocking", "pill-alert") : ""}
              ${badge(task.status)}
            </div>
            <h3>${task.title}</h3>
            <p>${projectNameFor(task.project_id)} · ${dueLabel(task)} · 預估 ${task.estimate_minutes} 分鐘</p>
          </div>
          <div class="task-actions">
            <button
              class="ghost-btn"
              data-task-id="${task.id}"
              data-next-status="${task.status === "done" ? "todo" : "done"}"
            >
              ${task.status === "done" ? "重新打開" : "標記完成"}
            </button>
            <button class="ghost-btn danger-btn" data-task-delete-id="${task.id}">刪除</button>
          </div>
        </article>
      `
    )
    .join("");
}

function requirementActionButton(requirement) {
  if (requirement.status === "met") {
    return `
      <button class="tiny-btn" data-requirement-id="${requirement.id}" data-next-status="in_progress">
        改成進行中
      </button>
    `;
  }

  return `
    <button class="tiny-btn" data-requirement-id="${requirement.id}" data-next-status="met">
      標記 met
    </button>
  `;
}

function renderProjects(projects) {
  projectGrid.innerHTML = projects
    .map((project) => {
      const metCount = project.requirements.filter((item) => item.status === "met").length;
      return `
        <article class="project-card">
          <div class="project-top">
            <div class="project-head">
              <div class="project-side">
                ${badge(project.stage)}
                ${badge(project.priority, priorityClass[project.priority])}
                ${badge(project.risk, project.risk === "stable" ? "pill-good" : "pill-alert")}
              </div>
              <h3>${project.title}</h3>
              <p class="project-summary">${project.summary}</p>
            </div>
            <div class="project-score">
              <strong>${project.readiness}%</strong>
              <span>readiness</span>
            </div>
          </div>

          <div class="project-meter">
            <span style="width:${project.readiness}%"></span>
          </div>

          <div class="project-meta-row">
            <span>${metCount}/${project.requirements.length} requirements met</span>
            <strong>Deadline ${formatDateOnly(project.deadline)}</strong>
          </div>

          <div class="project-gap-row">
            <span>Next gap</span>
            <strong>${project.next_gap}</strong>
          </div>

          <div class="requirement-list">
            ${project.requirements
              .map(
                (requirement) => `
                  <div class="requirement-item">
                    <div>
                      <strong>${requirement.title}</strong>
                      <p>${requirement.note || "無補充說明"}</p>
                    </div>
                    <div class="requirement-actions">
                      ${badge(requirement.status, requirement.status === "met" ? "pill-good" : "pill-alert")}
                      ${requirementActionButton(requirement)}
                    </div>
                  </div>
                `
              )
              .join("")}
          </div>
        </article>
      `;
    })
    .join("");
}

function renderCashflow(cashflow) {
  const summary = cashflow.summary;
  const summaryCards = [
    {
      label: `${summary.month_label} 收入`,
      value: formatCurrency(summary.month_income),
      note: "本月已入帳",
      tone: "is-positive",
    },
    {
      label: `${summary.month_label} 支出`,
      value: formatCurrency(summary.month_expense),
      note: "本月已花出",
      tone: "is-negative",
    },
    {
      label: `${summary.month_label} 淨流`,
      value: formatCurrency(summary.month_net),
      note: "收入減支出",
      tone: netToneClass(summary.month_net),
    },
    {
      label: "未來 30 天", 
      value: formatCurrency(summary.planned_net_30d),
      note: `收入 ${formatCurrency(summary.planned_income_30d)} / 支出 ${formatCurrency(summary.planned_expense_30d)}`,
      tone: netToneClass(summary.planned_net_30d),
    },
    {
      label: "資產快照",
      value: formatCurrency(summary.asset_total),
      note: `${summary.entry_count} 筆現金流紀錄`,
      tone: "is-neutral",
    },
  ];

  cashflowSummaryGrid.innerHTML = summaryCards
    .map(
      (item) => `
        <article class="cashflow-stat ${item.tone}">
          <p>${item.label}</p>
          <strong>${item.value}</strong>
          <span>${item.note}</span>
        </article>
      `
    )
    .join("");

  cashflowUpcomingList.innerHTML = cashflow.upcoming.length
    ? cashflow.upcoming
        .map(
          (entry) => `
            <article class="mini-card">
              <strong>${entry.title}</strong>
              <span>${formatDateOnly(entry.date)} · ${entry.category} · ${entry.kind}</span>
              <span class="cashflow-inline ${entry.kind === "income" ? "is-income" : "is-expense"}">${formatSignedAmount(entry)}</span>
            </article>
          `
        )
        .join("")
    : `<p class="empty-state">未來 30 天沒有已規劃款項。</p>`;

  cashflowAssetList.innerHTML = cashflow.asset_positions.length
    ? cashflow.asset_positions
        .map(
          (entry) => `
            <article class="mini-card">
              <strong>${entry.title}</strong>
              <span>${entry.category}${entry.account ? ` · ${entry.account}` : ""}</span>
              <span class="cashflow-inline is-asset">${formatCurrency(entry.amount)}</span>
            </article>
          `
        )
        .join("")
    : `<p class="empty-state">還沒有資產快照。</p>`;

  if (!cashflow.category_breakdown.length) {
    cashflowCategoryList.innerHTML = `<p class="empty-state">本月還沒有足夠的實際收支分類。</p>`;
  } else {
    const maxTotal = Math.max(...cashflow.category_breakdown.map((item) => item.total), 1);
    cashflowCategoryList.innerHTML = cashflow.category_breakdown
      .map(
        (item) => `
          <article class="category-row">
            <div class="category-copy">
              <div class="task-top">
                ${badge(item.kind, cashflowKindClass[item.kind])}
                <strong>${item.category}</strong>
              </div>
              <div class="category-meter">
                <span style="width:${Math.max(16, Math.round((item.total / maxTotal) * 100))}%"></span>
              </div>
            </div>
            <strong>${formatCurrency(item.total)}</strong>
          </article>
        `
      )
      .join("");
  }

  cashflowLedger.innerHTML = cashflow.recent.length
    ? cashflow.recent
        .map(
          (entry) => `
            <article class="ledger-row">
              <div class="ledger-date-block">
                <p class="eyebrow">${formatDateOnly(entry.date)}</p>
              </div>
              <div class="ledger-main">
                <div class="task-top">
                  ${badge(entry.kind, cashflowKindClass[entry.kind])}
                  ${badge(entry.status, entry.status === "actual" ? "pill-good" : "priority-low")}
                  ${entry.project_id ? badge(projectNameFor(entry.project_id)) : ""}
                </div>
                <h3>${entry.title}</h3>
                <p>${entry.category}${entry.account ? ` · ${entry.account}` : ""}${entry.note ? ` · ${entry.note}` : ""}</p>
              </div>
              <div class="ledger-side">
                <strong class="ledger-amount ${entry.kind === "income" ? "is-income" : entry.kind === "expense" ? "is-expense" : "is-asset"}">${formatSignedAmount(entry)}</strong>
                <div class="event-actions">
                  <button class="tiny-btn" data-cashflow-id="${entry.id}" data-cashflow-next-status="${entry.status === "actual" ? "planned" : "actual"}">
                    ${entry.status === "actual" ? "改成 planned" : "標成 actual"}
                  </button>
                  <button class="tiny-btn danger-btn" data-cashflow-delete-id="${entry.id}">刪除</button>
                </div>
              </div>
            </article>
          `
        )
        .join("")
    : `<p class="empty-state">目前還沒有現金流紀錄。</p>`;
}

function renderEvents(events) {
  if (!events.length) {
    eventList.innerHTML = `<p class="empty-state">目前沒有近期事件。</p>`;
    return;
  }

  eventList.innerHTML = events
    .map(
      (event) => `
        <article class="event-card">
          <div class="event-date">${event.all_day ? formatDateTime(event.start_at, true) : formatTimeOnly(event.start_at)}</div>
          <div class="event-body">
            <h3>${event.title}</h3>
            <p>${projectNameFor(event.project_id)} · ${eventWindowLabel(event)}</p>
            <span>${event.location || event.notes || "未填地點/備註"}</span>
            <div class="event-actions">
              ${
                event.apple_uid
                  ? `<span class="synced-note">已同步到 Apple Calendar${event.apple_calendar ? ` · ${event.apple_calendar}` : ""}</span>`
                  : `<button class="tiny-btn" data-event-sync-id="${event.id}">同步到 Apple Calendar</button>`
              }
              <button class="tiny-btn danger-btn" data-event-delete-id="${event.id}">刪除</button>
            </div>
          </div>
        </article>
      `
    )
    .join("");
}

function renderConflicts(conflicts) {
  if (!conflicts.length) {
    conflictList.innerHTML = `<p class="empty-state">目前沒有顯著衝突。</p>`;
    return;
  }

  conflictList.innerHTML = conflicts
    .map(
      (conflict) => `
        <article class="conflict-card">
          <div class="conflict-top">
            ${badge(conflict.kind)}
            ${badge(conflict.severity, "pill-alert")}
          </div>
          <h3>${conflict.title}</h3>
          <p>${conflict.detail}</p>
          <strong>${conflict.action}</strong>
        </article>
      `
    )
    .join("");
}

function renderReplan(plan) {
  if (!plan) {
    replanView.innerHTML = `<p class="empty-state">尚未產生本週重排建議。</p>`;
    return;
  }

  replanView.innerHTML = `
    <div class="replan-summary">
      <p>${plan.summary}</p>
    </div>

    <div class="replan-block">
      <h3>本週必做</h3>
      <div class="mini-list">
        ${
          plan.must_do.length
            ? plan.must_do
                .map(
                  (item) => `
                    <article class="mini-card">
                      <strong>${item.title}</strong>
                      <span>${item.reason}${item.due_at ? ` · ${formatDateTime(item.due_at)}` : ""}</span>
                    </article>
                  `
                )
                .join("")
            : `<p class="empty-state">本週沒有明顯硬截止的任務。</p>`
        }
      </div>
    </div>

    <div class="replan-days">
      ${plan.plan_days
        .map(
          (day) => `
            <article class="day-card">
              <div class="day-top">
                <strong>${formatDayLabel(day.date)}</strong>
                <span>${day.headline}</span>
              </div>
              <div class="mini-list">
                ${
                  day.items.length
                    ? day.items
                        .map(
                          (item) => `
                            <article class="mini-card">
                              <strong>${item.title}</strong>
                              <span>${item.kind} · ${item.time}</span>
                            </article>
                          `
                        )
                        .join("")
                    : `<p class="empty-state">留白日</p>`
                }
              </div>
            </article>
          `
        )
        .join("")}
    </div>
  `;
}

function renderAll(data) {
  dashboard = data;
  heroTheme.textContent = data.profile.life_theme;
  renderSnapshot(data.snapshot);
  renderToday(data.today);
  renderEmployee(data.employee_brief);
  renderGoals(data.goals);
  renderTasks(data.tasks);
  renderCashflow(data.cashflow);
  renderProjects(data.projects);
  renderEvents(data.events);
  renderConflicts(data.conflicts);
  fillProjectSelects(data.projects);
  applyAppMode(data.app_mode);
  document.body.classList.add("is-ready");
}

async function fetchJSON(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(detail || `HTTP ${response.status}`);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json();
}

function setCashflowDateDefault() {
  const input = document.getElementById("cashflowDate");
  if (!input.value) {
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, "0");
    const day = String(now.getDate()).padStart(2, "0");
    input.value = `${now.getFullYear()}-${month}-${day}`;
  }
}

function resetCashflowForm() {
  cashflowForm.reset();
  document.getElementById("cashflowKind").value = "expense";
  document.getElementById("cashflowStatus").value = "actual";
  setCashflowDateDefault();
}

async function refreshDashboard() {
  const data = await fetchJSON("/api/dashboard");
  renderAll(data);
  setStatus(`上次更新：${data.snapshot.generated_at}`, "success");
}

async function loadCalendars() {
  try {
    const response = await fetchJSON("/api/calendars");
    fillCalendarSelect(response.calendars);
  } catch (error) {
    if (appMode.readOnly) {
      fillCalendarSelect([]);
      setStatus("Public demo：Apple Calendar 已停用。", "neutral");
      return;
    }
    throw error;
  }
}

async function loadReplan() {
  const response = await fetchJSON("/api/replan-week");
  renderReplan(response);
}

async function handleTaskSubmit(event) {
  event.preventDefault();
  const formData = new FormData(taskForm);

  await fetchJSON("/api/tasks", {
    method: "POST",
    body: JSON.stringify({
      title: formData.get("title"),
      project_id: formData.get("project_id") || null,
      due_at: formData.get("due_at") || null,
      priority: formData.get("priority"),
      estimate_minutes: Number(formData.get("estimate_minutes") || 60),
      blocking: formData.get("blocking") === "on",
    }),
  });

  taskForm.reset();
  document.getElementById("taskPriority").value = "high";
  document.getElementById("taskEstimate").value = 60;
  await Promise.all([refreshDashboard(), loadReplan()]);
  setStatus("任務已加入。", "success");
}

async function handleCaptureSubmit(event) {
  event.preventDefault();
  const formData = new FormData(captureForm);

  const response = await fetchJSON("/api/capture", {
    method: "POST",
    body: JSON.stringify({ text: formData.get("text") }),
  });

  captureForm.reset();
  await Promise.all([refreshDashboard(), loadReplan()]);
  setStatus(`已快速匯入 ${response.created.length} 筆內容。`, "success");
}

async function handleEventSubmit(event) {
  event.preventDefault();
  const formData = new FormData(eventForm);

  await fetchJSON("/api/events", {
    method: "POST",
    body: JSON.stringify({
      title: formData.get("title"),
      project_id: formData.get("project_id") || null,
      start_at: formData.get("start_at"),
      end_at: formData.get("end_at"),
      location: formData.get("location") || "",
      all_day: false,
    }),
  });

  eventForm.reset();
  await Promise.all([refreshDashboard(), loadReplan()]);
  setStatus("事件已加入。", "success");
}

async function handleCashflowSubmit(event) {
  event.preventDefault();
  const formData = new FormData(cashflowForm);

  await fetchJSON("/api/cashflow/entries", {
    method: "POST",
    body: JSON.stringify({
      title: formData.get("title"),
      kind: formData.get("kind"),
      status: formData.get("status"),
      amount: Number(formData.get("amount") || 0),
      date: formData.get("date"),
      category: formData.get("category"),
      account: formData.get("account") || "",
      note: formData.get("note") || "",
      project_id: formData.get("project_id") || null,
    }),
  });

  resetCashflowForm();
  await refreshDashboard();
  setStatus("現金流已加入。", "success");
}

async function handleTaskAction(button) {
  await fetchJSON(`/api/tasks/${button.dataset.taskId}`, {
    method: "PATCH",
    body: JSON.stringify({ status: button.dataset.nextStatus }),
  });
  await Promise.all([refreshDashboard(), loadReplan()]);
  setStatus("任務狀態已更新。", "success");
}

async function handleRequirementAction(button) {
  await fetchJSON(`/api/requirements/${button.dataset.requirementId}`, {
    method: "PATCH",
    body: JSON.stringify({ status: button.dataset.nextStatus }),
  });
  await Promise.all([refreshDashboard(), loadReplan()]);
  setStatus("前置條件狀態已更新。", "success");
}

async function handleTaskDelete(button) {
  await fetchJSON(`/api/tasks/${button.dataset.taskDeleteId}`, { method: "DELETE" });
  await Promise.all([refreshDashboard(), loadReplan()]);
  setStatus("任務已刪除。", "success");
}

async function handleEventSync(button) {
  const calendarName = calendarSelect.value;
  if (!calendarName) {
    throw new Error("沒有可用的 Apple Calendar");
  }

  await fetchJSON(`/api/events/${button.dataset.eventSyncId}/sync-apple`, {
    method: "POST",
    body: JSON.stringify({ calendar_name: calendarName }),
  });
  await Promise.all([refreshDashboard(), loadReplan()]);
  setStatus(`事件已同步到 ${calendarName}。`, "success");
}

async function handleEventDelete(button) {
  await fetchJSON(`/api/events/${button.dataset.eventDeleteId}`, { method: "DELETE" });
  await Promise.all([refreshDashboard(), loadReplan()]);
  setStatus("事件已刪除。", "success");
}

async function handleCashflowStatus(button) {
  await fetchJSON(`/api/cashflow/entries/${button.dataset.cashflowId}`, {
    method: "PATCH",
    body: JSON.stringify({ status: button.dataset.cashflowNextStatus }),
  });
  await refreshDashboard();
  setStatus("現金流狀態已更新。", "success");
}

async function handleCashflowDelete(button) {
  await fetchJSON(`/api/cashflow/entries/${button.dataset.cashflowDeleteId}`, { method: "DELETE" });
  await refreshDashboard();
  setStatus("現金流已刪除。", "success");
}

async function handleCalendarImport() {
  const calendarName = calendarSelect.value;
  if (!calendarName) {
    throw new Error("沒有可用的 Apple Calendar");
  }

  const response = await fetchJSON("/api/calendars/import", {
    method: "POST",
    body: JSON.stringify({
      calendar_name: calendarName,
      days_before: 7,
      days_after: 30,
    }),
  });

  await Promise.all([refreshDashboard(), loadReplan()]);
  setStatus(
    `已從 ${calendarName} 匯入 ${response.imported_count} 筆，更新 ${response.updated_count} 筆，清掉 ${response.removed_count} 筆舊事件。`,
    "success"
  );
}

async function handleReplan() {
  await loadReplan();
  setStatus("已重新分析本週。", "success");
}

document.addEventListener("click", async (event) => {
  const paneButton = event.target.closest("[data-pane-button]");
  if (paneButton) {
    setActivePane(paneButton.dataset.paneButton);
    return;
  }

  const taskButton = event.target.closest("[data-task-id]");
  if (taskButton) {
    try {
      await handleTaskAction(taskButton);
    } catch (error) {
      console.error(error);
      setStatus(`更新任務失敗：${error.message}`, "error");
    }
    return;
  }

  const taskDeleteButton = event.target.closest("[data-task-delete-id]");
  if (taskDeleteButton) {
    try {
      await handleTaskDelete(taskDeleteButton);
    } catch (error) {
      console.error(error);
      setStatus(`刪除任務失敗：${error.message}`, "error");
    }
    return;
  }

  const requirementButton = event.target.closest("[data-requirement-id]");
  if (requirementButton) {
    try {
      await handleRequirementAction(requirementButton);
    } catch (error) {
      console.error(error);
      setStatus(`更新前置條件失敗：${error.message}`, "error");
    }
    return;
  }

  const eventSyncButton = event.target.closest("[data-event-sync-id]");
  if (eventSyncButton) {
    try {
      await handleEventSync(eventSyncButton);
    } catch (error) {
      console.error(error);
      setStatus(`同步 Apple Calendar 失敗：${error.message}`, "error");
    }
    return;
  }

  const eventDeleteButton = event.target.closest("[data-event-delete-id]");
  if (eventDeleteButton) {
    try {
      await handleEventDelete(eventDeleteButton);
    } catch (error) {
      console.error(error);
      setStatus(`刪除事件失敗：${error.message}`, "error");
    }
    return;
  }

  const cashflowButton = event.target.closest("[data-cashflow-id]");
  if (cashflowButton) {
    try {
      await handleCashflowStatus(cashflowButton);
    } catch (error) {
      console.error(error);
      setStatus(`更新現金流失敗：${error.message}`, "error");
    }
    return;
  }

  const cashflowDeleteButton = event.target.closest("[data-cashflow-delete-id]");
  if (cashflowDeleteButton) {
    try {
      await handleCashflowDelete(cashflowDeleteButton);
    } catch (error) {
      console.error(error);
      setStatus(`刪除現金流失敗：${error.message}`, "error");
    }
  }
});

taskForm.addEventListener("submit", async (event) => {
  try {
    await handleTaskSubmit(event);
  } catch (error) {
    console.error(error);
    setStatus(`新增任務失敗：${error.message}`, "error");
  }
});

captureForm.addEventListener("submit", async (event) => {
  try {
    await handleCaptureSubmit(event);
  } catch (error) {
    console.error(error);
    setStatus(`快速匯入失敗：${error.message}`, "error");
  }
});

eventForm.addEventListener("submit", async (event) => {
  try {
    await handleEventSubmit(event);
  } catch (error) {
    console.error(error);
    setStatus(`新增事件失敗：${error.message}`, "error");
  }
});

cashflowForm.addEventListener("submit", async (event) => {
  try {
    await handleCashflowSubmit(event);
  } catch (error) {
    console.error(error);
    setStatus(`新增現金流失敗：${error.message}`, "error");
  }
});

importCalendarButton.addEventListener("click", async () => {
  try {
    await handleCalendarImport();
  } catch (error) {
    console.error(error);
    setStatus(`匯入 Apple Calendar 失敗：${error.message}`, "error");
  }
});

replanButton.addEventListener("click", async () => {
  try {
    await handleReplan();
  } catch (error) {
    console.error(error);
    setStatus(`重排本週失敗：${error.message}`, "error");
  }
});

refreshDashboard()
  .then(() => Promise.all([loadCalendars(), loadReplan()]))
  .then(() => {
    setActivePane("capture");
    setCashflowDateDefault();
  })
  .catch((error) => {
    console.error(error);
    setStatus(`載入失敗：${error.message}`, "error");
  });
