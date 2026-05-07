from __future__ import annotations

import json
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Callable, Literal

from pydantic import BaseModel, Field

from .apple_calendar import AppleCalendarClient, AppleCalendarEventPayload
from .quick_capture import _infer_project_id, parse_capture_text


Priority = Literal["critical", "high", "medium", "low"]
Status = Literal["active", "planned", "done", "paused"]
RequirementStatus = Literal["met", "in_progress", "missing"]
TaskStatus = Literal["todo", "doing", "done"]
ProjectStage = Literal["capture", "definition", "execution", "foundation", "research"]
ConflictKind = Literal["schedule", "deadline", "blocker", "requirement"]
CashflowKind = Literal["income", "expense", "asset"]
CashflowStatus = Literal["actual", "planned"]


PRIORITY_RANK: dict[Priority, int] = {
    "critical": 0,
    "high": 1,
    "medium": 2,
    "low": 3,
}


class UserProfile(BaseModel):
    display_name: str
    home_base: str
    timezone: str = "Asia/Taipei"
    life_theme: str
    planning_mode: str


class Goal(BaseModel):
    id: str
    title: str
    horizon: str
    target_date: str | None = None
    status: Status = "active"
    priority: Priority = "medium"
    why: str
    success_definition: str
    constraints: list[str] = Field(default_factory=list)


class Project(BaseModel):
    id: str
    goal_ids: list[str]
    title: str
    stage: ProjectStage
    priority: Priority
    status: Status = "active"
    deadline: str | None = None
    summary: str


class Requirement(BaseModel):
    id: str
    project_id: str
    title: str
    kind: str
    status: RequirementStatus = "missing"
    note: str = ""


class Task(BaseModel):
    id: str
    project_id: str | None = None
    title: str
    status: TaskStatus = "todo"
    priority: Priority = "medium"
    due_at: str | None = None
    estimate_minutes: int = 60
    blocking: bool = False


class CalendarEvent(BaseModel):
    id: str
    project_id: str | None = None
    title: str
    start_at: str
    end_at: str
    location: str = ""
    notes: str = ""
    all_day: bool = False
    apple_uid: str | None = None
    apple_calendar: str | None = None
    synced_at: str | None = None


class CashflowEntry(BaseModel):
    id: str
    project_id: str | None = None
    title: str
    kind: CashflowKind
    status: CashflowStatus = "actual"
    amount: int = Field(ge=0)
    date: str
    category: str
    account: str = ""
    note: str = ""


class Review(BaseModel):
    id: str
    period: str
    summary: str
    keep: list[str] = Field(default_factory=list)
    cut: list[str] = Field(default_factory=list)
    next_focus: list[str] = Field(default_factory=list)


class LifeOSState(BaseModel):
    profile: UserProfile
    goals: list[Goal]
    projects: list[Project]
    requirements: list[Requirement]
    tasks: list[Task]
    events: list[CalendarEvent]
    cashflow: list[CashflowEntry] = Field(default_factory=list)
    reviews: list[Review] = Field(default_factory=list)


class TaskCreate(BaseModel):
    title: str
    project_id: str | None = None
    due_at: str | None = None
    priority: Priority = "medium"
    estimate_minutes: int = 60
    blocking: bool = False


class TaskUpdate(BaseModel):
    status: TaskStatus


class EventCreate(BaseModel):
    title: str
    project_id: str | None = None
    start_at: str
    end_at: str
    location: str = ""
    notes: str = ""
    all_day: bool = False


class CashflowEntryCreate(BaseModel):
    title: str
    kind: CashflowKind
    status: CashflowStatus = "actual"
    amount: int = Field(gt=0)
    date: str
    category: str
    account: str = ""
    note: str = ""
    project_id: str | None = None


class CashflowEntryUpdate(BaseModel):
    title: str | None = None
    kind: CashflowKind | None = None
    status: CashflowStatus | None = None
    amount: int | None = Field(default=None, gt=0)
    date: str | None = None
    category: str | None = None
    account: str | None = None
    note: str | None = None
    project_id: str | None = None


class RequirementUpdate(BaseModel):
    status: RequirementStatus


class CalendarSyncRequest(BaseModel):
    calendar_name: str = "計劃安排"


class QuickCaptureRequest(BaseModel):
    text: str


class CalendarImportRequest(BaseModel):
    calendar_name: str = "計劃安排"
    days_before: int = 7
    days_after: int = 30


class LifeOSStore:
    def __init__(
        self,
        path: Path,
        now_provider: Callable[[], datetime] | None = None,
        calendar_client: AppleCalendarClient | None = None,
    ) -> None:
        self.path = path
        self.now_provider = now_provider or datetime.now
        self.calendar_client = calendar_client or AppleCalendarClient()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            self.save(self._seed_state())

    def load(self) -> LifeOSState:
        raw = json.loads(self.path.read_text(encoding="utf-8"))
        return LifeOSState.model_validate(raw)

    def save(self, state: LifeOSState) -> None:
        self.path.write_text(
            json.dumps(state.model_dump(mode="json"), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def get_dashboard(self) -> dict:
        state = self.load()
        now = self.now_provider()

        requirements_by_project = self._group_requirements(state.requirements)
        tasks_by_project = self._group_tasks(state.tasks)
        cashflow_view = self._cashflow_dashboard(state.cashflow, now)

        project_cards = []
        blocked_projects = 0
        for project in state.projects:
            reqs = requirements_by_project.get(project.id, [])
            tasks = tasks_by_project.get(project.id, [])
            readiness = self._readiness(reqs)
            risk = self._project_risk(project, reqs, now)
            if risk in {"high", "critical"}:
                blocked_projects += 1
            missing = [req for req in reqs if req.status != "met"]
            project_cards.append(
                {
                    "id": project.id,
                    "title": project.title,
                    "stage": project.stage,
                    "priority": project.priority,
                    "status": project.status,
                    "deadline": project.deadline,
                    "summary": project.summary,
                    "readiness": readiness,
                    "risk": risk,
                    "next_gap": missing[0].title if missing else "主要前置條件已齊備",
                    "requirements": [req.model_dump(mode="json") for req in reqs],
                    "open_tasks": sum(1 for task in tasks if task.status != "done"),
                }
            )

        task_cards = self._sorted_open_tasks(state.tasks)
        upcoming_events = self._upcoming_events(state.events, now)
        conflicts = self._collect_conflicts(state, project_cards, now)

        employee_actions = self._employee_actions(task_cards, conflicts, project_cards)
        employee_summary = (
            "先把固定期限和會卡住後面所有目標的前置條件解掉，再談擴張。"
            if employee_actions
            else "目前沒有立即爆炸的衝突，接下來維持每週回顧與持續交付。"
        )

        return {
            "profile": state.profile.model_dump(mode="json"),
            "snapshot": {
                "generated_at": now.isoformat(timespec="minutes"),
                "active_goals": sum(1 for goal in state.goals if goal.status == "active"),
                "open_tasks": sum(1 for task in state.tasks if task.status != "done"),
                "blocked_projects": blocked_projects,
                "upcoming_events": len(upcoming_events),
            },
            "today": self._today_brief(state, now),
            "employee_brief": {
                "headline": "把近期硬期限穩住，系統才有空間承接長期目標。",
                "summary": employee_summary,
                "actions": employee_actions,
            },
            "goals": [goal.model_dump(mode="json") for goal in state.goals],
            "projects": project_cards,
            "tasks": [task.model_dump(mode="json") for task in task_cards],
            "events": upcoming_events,
            "cashflow": cashflow_view,
            "conflicts": conflicts,
            "reviews": [review.model_dump(mode="json") for review in state.reviews],
        }

    def create_task(self, payload: TaskCreate) -> dict:
        state = self.load()
        task = Task(
            id=self._next_id("task", [item.id for item in state.tasks]),
            title=payload.title.strip(),
            project_id=payload.project_id,
            due_at=payload.due_at,
            priority=payload.priority,
            estimate_minutes=payload.estimate_minutes,
            blocking=payload.blocking,
        )
        state.tasks.append(task)
        self.save(state)
        return task.model_dump(mode="json")

    def update_task(self, task_id: str, payload: TaskUpdate) -> dict:
        state = self.load()
        task = next((item for item in state.tasks if item.id == task_id), None)
        if task is None:
            raise KeyError(task_id)
        task.status = payload.status
        self.save(state)
        return task.model_dump(mode="json")

    def delete_task(self, task_id: str) -> None:
        state = self.load()
        original_count = len(state.tasks)
        state.tasks = [item for item in state.tasks if item.id != task_id]
        if len(state.tasks) == original_count:
            raise KeyError(task_id)
        self.save(state)

    def create_event(self, payload: EventCreate) -> dict:
        start_at = _parse_datetime(payload.start_at)
        end_at = _parse_datetime(payload.end_at)
        if end_at <= start_at:
            raise ValueError("end_at must be later than start_at")

        state = self.load()
        event = CalendarEvent(
            id=self._next_id("event", [item.id for item in state.events]),
            title=payload.title.strip(),
            project_id=payload.project_id,
            start_at=start_at.isoformat(timespec="minutes"),
            end_at=end_at.isoformat(timespec="minutes"),
            location=payload.location.strip(),
            notes=payload.notes.strip(),
            all_day=payload.all_day,
        )
        state.events.append(event)
        self.save(state)
        return event.model_dump(mode="json")

    def delete_event(self, event_id: str) -> None:
        state = self.load()
        original_count = len(state.events)
        state.events = [item for item in state.events if item.id != event_id]
        if len(state.events) == original_count:
            raise KeyError(event_id)
        self.save(state)

    def create_cashflow_entry(self, payload: CashflowEntryCreate) -> dict:
        state = self.load()
        entry = CashflowEntry(
            id=self._next_id("cashflow", [item.id for item in state.cashflow]),
            project_id=payload.project_id,
            title=payload.title.strip(),
            kind=payload.kind,
            status=payload.status,
            amount=payload.amount,
            date=_parse_date(payload.date).isoformat(),
            category=payload.category.strip() or self._default_cashflow_category(payload.kind),
            account=payload.account.strip(),
            note=payload.note.strip(),
        )
        state.cashflow.append(entry)
        self.save(state)
        return entry.model_dump(mode="json")

    def update_cashflow_entry(self, entry_id: str, payload: CashflowEntryUpdate) -> dict:
        state = self.load()
        entry = next((item for item in state.cashflow if item.id == entry_id), None)
        if entry is None:
            raise KeyError(entry_id)

        updates = payload.model_dump(exclude_unset=True)
        for field, value in updates.items():
            if field == "date" and value is not None:
                setattr(entry, field, _parse_date(value).isoformat())
            elif field in {"title", "category", "account", "note"} and value is not None:
                setattr(entry, field, value.strip())
            else:
                setattr(entry, field, value)

        if not entry.category:
            entry.category = self._default_cashflow_category(entry.kind)

        self.save(state)
        return entry.model_dump(mode="json")

    def delete_cashflow_entry(self, entry_id: str) -> None:
        state = self.load()
        original_count = len(state.cashflow)
        state.cashflow = [item for item in state.cashflow if item.id != entry_id]
        if len(state.cashflow) == original_count:
            raise KeyError(entry_id)
        self.save(state)

    def import_events_from_apple(
        self,
        calendar_name: str,
        days_before: int = 7,
        days_after: int = 30,
    ) -> dict:
        state = self.load()
        now = self.now_provider()
        range_start = (now - timedelta(days=days_before)).replace(hour=0, minute=0)
        range_end = (now + timedelta(days=days_after)).replace(hour=23, minute=59)

        imported = self.calendar_client.list_events(
            calendar_name=calendar_name,
            range_start=range_start.isoformat(timespec="minutes"),
            range_end=range_end.isoformat(timespec="minutes"),
        )
        existing_by_uid = {event.apple_uid: event for event in state.events if event.apple_uid}
        imported_uids = {record.apple_uid for record in imported}

        imported_count = 0
        updated_count = 0
        for record in imported:
            existing = existing_by_uid.get(record.apple_uid)
            if existing is None:
                state.events.append(
                    CalendarEvent(
                        id=self._next_id("event", [entry.id for entry in state.events]),
                        project_id=_infer_project_id(record.title),
                        title=record.title,
                        start_at=record.start_at,
                        end_at=record.end_at,
                        location=record.location,
                        notes=record.notes,
                        all_day=record.all_day,
                        apple_uid=record.apple_uid,
                        apple_calendar=calendar_name,
                        synced_at=now.isoformat(timespec="seconds"),
                    )
                )
                imported_count += 1
                continue

            existing.title = record.title
            existing.start_at = record.start_at
            existing.end_at = record.end_at
            existing.location = record.location
            existing.notes = record.notes
            existing.all_day = record.all_day
            existing.apple_calendar = calendar_name
            existing.synced_at = now.isoformat(timespec="seconds")
            updated_count += 1

        removed_count = 0
        retained_events: list[CalendarEvent] = []
        for event in state.events:
            if not (
                event.apple_uid
                and event.apple_calendar == calendar_name
                and _event_in_window(event, range_start, range_end)
                and event.apple_uid not in imported_uids
            ):
                retained_events.append(event)
                continue
            removed_count += 1

        state.events = retained_events

        self.save(state)
        return {
            "calendar_name": calendar_name,
            "imported_count": imported_count,
            "updated_count": updated_count,
            "removed_count": removed_count,
            "window": {
                "start_at": range_start.isoformat(timespec="minutes"),
                "end_at": range_end.isoformat(timespec="minutes"),
            },
        }

    def replan_week(self) -> dict:
        state = self.load()
        now = self.now_provider()
        week_start = now.date()
        week_end = week_start + timedelta(days=6)

        open_tasks = [task for task in self._sorted_open_tasks(state.tasks) if task.status != "done"]
        weekly_events = [
            event
            for event in state.events
            if week_start <= _parse_datetime(event.start_at).date() <= week_end
        ]
        weekly_events.sort(key=lambda event: event.start_at)

        must_do = []
        for task in open_tasks:
            due_date = _parse_datetime(task.due_at).date() if task.due_at else None
            if task.blocking or (due_date is not None and due_date <= week_end):
                must_do.append(task)

        schedule_map = {week_start + timedelta(days=index): [] for index in range(7)}
        for event in weekly_events:
            schedule_map[_parse_datetime(event.start_at).date()].append(
                {
                    "kind": "event",
                    "title": event.title,
                    "time": "全天" if event.all_day else _time_window(event.start_at, event.end_at),
                }
            )

        focus_queue = must_do[:]
        for day in schedule_map:
            event_count = len(schedule_map[day])
            capacity = 1 if event_count >= 2 else 2
            while focus_queue and capacity > 0:
                task = focus_queue.pop(0)
                schedule_map[day].append(
                    {
                        "kind": "task",
                        "title": task.title,
                        "time": f"建議保留 {task.estimate_minutes} 分鐘",
                    }
                )
                capacity -= 1

        backlog = [task for task in open_tasks if task not in must_do][:3]
        plan_days = []
        for day in schedule_map:
            items = schedule_map[day]
            if not items:
                headline = "保留空白，避免新的突發事件直接擠爆。"
            elif any(item["kind"] == "task" for item in items):
                headline = "這天要先把阻塞任務往前推。"
            else:
                headline = "這天主要承接既有事件。"

            plan_days.append(
                {
                    "date": day.isoformat(),
                    "headline": headline,
                    "items": items,
                }
            )

        summary = (
            "這週不要再擴張目標，先把有硬期限的任務和會卡住後面專案的前置條件處理掉。"
            if must_do
            else "這週沒有明顯爆點，可以把重點放在長期主線推進。"
        )

        return {
            "generated_at": now.isoformat(timespec="minutes"),
            "summary": summary,
            "must_do": [
                {
                    "title": task.title,
                    "due_at": task.due_at,
                    "priority": task.priority,
                    "reason": "阻塞任務" if task.blocking else "本週內到期",
                }
                for task in must_do[:5]
            ],
            "backlog": [
                {
                    "title": task.title,
                    "due_at": task.due_at,
                    "priority": task.priority,
                }
                for task in backlog
            ],
            "plan_days": plan_days,
        }

    def update_requirement(self, requirement_id: str, payload: RequirementUpdate) -> dict:
        state = self.load()
        requirement = next((item for item in state.requirements if item.id == requirement_id), None)
        if requirement is None:
            raise KeyError(requirement_id)
        requirement.status = payload.status
        self.save(state)
        return requirement.model_dump(mode="json")

    def list_calendars(self) -> list[str]:
        return self.calendar_client.list_calendars()

    def sync_event_to_apple(self, event_id: str, calendar_name: str) -> dict:
        state = self.load()
        event = next((item for item in state.events if item.id == event_id), None)
        if event is None:
            raise KeyError(event_id)

        apple_uid = self.calendar_client.upsert_event(
            calendar_name=calendar_name,
            payload=AppleCalendarEventPayload(
                title=event.title,
                start_at=event.start_at,
                end_at=event.end_at,
                location=event.location,
                notes=event.notes,
                all_day=event.all_day,
                apple_uid=event.apple_uid,
            ),
        )

        event.apple_uid = apple_uid
        event.apple_calendar = calendar_name
        event.synced_at = self.now_provider().isoformat(timespec="seconds")
        self.save(state)
        return event.model_dump(mode="json")

    def quick_capture(self, text: str) -> list[dict]:
        parsed_items = parse_capture_text(text, self.now_provider())
        state = self.load()
        created: list[dict] = []

        for item in parsed_items:
            if item.kind == "event":
                event = CalendarEvent(
                    id=self._next_id("event", [entry.id for entry in state.events]),
                    project_id=item.project_id,
                    title=item.title,
                    start_at=item.start_at or "",
                    end_at=item.end_at or "",
                    all_day=item.all_day,
                )
                state.events.append(event)
                created.append({"kind": "event", **event.model_dump(mode="json")})
                continue

            task = Task(
                id=self._next_id("task", [entry.id for entry in state.tasks]),
                project_id=item.project_id,
                title=item.title,
                due_at=item.due_at,
                priority="high" if item.project_id == "project-license" else "medium",
            )
            state.tasks.append(task)
            created.append({"kind": "task", **task.model_dump(mode="json")})

        self.save(state)
        return created

    def _seed_state(self) -> LifeOSState:
        return LifeOSState(
            profile=UserProfile(
                display_name="Life OS Operator",
                home_base="Demo City",
                life_theme="先穩住近期行政與系統，再往seasonal work、Skill Certification L1、長期academic track推進。",
                planning_mode="每週回顧 + 專案式推進 + 事件落地",
            ),
            goals=[
                Goal(
                    id="goal-stability",
                    title="90天內把生活行政與規劃系統穩定下來",
                    horizon="90天",
                    target_date="2026-06-30",
                    priority="critical",
                    why="沒有穩定節奏，文件、證照、seasonal work、學業都會互相擠壓。",
                    success_definition="固定行程、待辦、前置條件與每週回顧都在同一套系統內運作。",
                ),
                Goal(
                    id="goal-life-os",
                    title="做出能長期使用的 Life OS 網站",
                    horizon="1年",
                    target_date="2026-12-31",
                    priority="high",
                    why="這個 demo 展示目標、專案、任務與行程如何串接。",
                    success_definition="網站可以管理目標、專案、任務、行程與衝突，並給出下一步。",
                ),
                Goal(
                    id="goal-skill-seasonal",
                    title="建立 Skill Certification L1 與seasonal work的可執行路線",
                    horizon="1年",
                    target_date="2026-12-31",
                    priority="high",
                    why="這是公開 demo 的中期技能路線。",
                    success_definition="完成訓練與文件路線圖，知道缺口、成本與時程。",
                ),
                Goal(
                    id="goal-academic",
                    title="保留 長期academic track／學業主線",
                    horizon="長期",
                    target_date="2037-12-31",
                    priority="medium",
                    why="seasonal training與seasonal work不是唯一人生，長期職涯也要有主線。",
                    success_definition="學業/academic track方向被拆成里程碑，而不是只剩模糊願望。",
                ),
            ],
            projects=[
                Project(
                    id="project-license",
                    goal_ids=["goal-stability"],
                    title="行政文件管理",
                    stage="execution",
                    priority="critical",
                    deadline="2026-04-14",
                    summary="先處理明確日期的考試與證件，不讓基本行政拖垮節奏。",
                ),
                Project(
                    id="project-life-os",
                    goal_ids=["goal-stability", "goal-life-os"],
                    title="Life OS MVP",
                    stage="execution",
                    priority="high",
                    deadline="2026-04-20",
                    summary="先做出可用版，而不是一開始就追求全自動 AI 秘書。",
                ),
                Project(
                    id="project-casi",
                    goal_ids=["goal-skill-seasonal"],
                    title="Skill Certification L1 準備",
                    stage="foundation",
                    priority="high",
                    deadline="2026-12-31",
                    summary="先補中級滑行、理論、文件與預算，讓未來報考不被硬條件卡住。",
                ),
                Project(
                    id="project-seasonal",
                    goal_ids=["goal-skill-seasonal"],
                    title="seasonal work路線",
                    stage="research",
                    priority="high",
                    deadline="2027-06-30",
                    summary="把 seasonal employment、seasonal workplace求職、資金與履歷路線整理成能執行的方案。",
                ),
                Project(
                    id="project-academic",
                    goal_ids=["goal-academic"],
                    title="academic roadmap定義",
                    stage="definition",
                    priority="medium",
                    deadline="2026-06-30",
                    summary="先定義領域、學位與節點，不然長期目標只會變成壓力來源。",
                ),
            ],
            requirements=[
                Requirement(
                    id="req-license-car-date",
                    project_id="project-license",
                    title="行政文件 A 日期已確認",
                    kind="schedule",
                    status="met",
                    note="2026-04-02 已排入行事曆。",
                ),
                Requirement(
                    id="req-license-scooter-date",
                    project_id="project-license",
                    title="行政文件 B 日期已確認",
                    kind="schedule",
                    status="met",
                    note="2026-04-14 已排入行事曆。",
                ),
                Requirement(
                    id="req-license-docs",
                    project_id="project-license",
                    title="確認兩場考試的證件、地點與報到規則",
                    kind="prerequisite",
                    status="missing",
                    note="沒有這步，行事曆事件本身沒有完成價值。",
                ),
                Requirement(
                    id="req-license-buffer",
                    project_id="project-license",
                    title="考前留出睡眠與出發緩衝",
                    kind="risk-control",
                    status="missing",
                    note="避免前一晚或當天臨時被其他事情擠掉。",
                ),
                Requirement(
                    id="req-life-entity",
                    project_id="project-life-os",
                    title="定義 Goals / Projects / Requirements / Tasks / Events 資料模型",
                    kind="architecture",
                    status="in_progress",
                    note="這是整個系統的骨架。",
                ),
                Requirement(
                    id="req-life-mvp",
                    project_id="project-life-os",
                    title="定義 MVP 頁面與使用流程",
                    kind="product",
                    status="in_progress",
                    note="先做可用版，不做全自動。",
                ),
                Requirement(
                    id="req-life-dashboard",
                    project_id="project-life-os",
                    title="做出能管理目標、專案、任務、事件的第一版介面",
                    kind="deliverable",
                    status="missing",
                    note="沒有介面就還只是規劃文件。",
                ),
                Requirement(
                    id="req-life-conflict",
                    project_id="project-life-os",
                    title="加入衝突偵測與缺口提醒",
                    kind="logic",
                    status="missing",
                    note="這是你說的 AI 員工最先要成立的能力。",
                ),
                Requirement(
                    id="req-casi-skill",
                    project_id="project-casi",
                    title="建立完整中級滑行能力",
                    kind="skill",
                    status="missing",
                    note="沒有穩定滑行能力，Skill Certification L1 只是口號。",
                ),
                Requirement(
                    id="req-casi-budget",
                    project_id="project-casi",
                    title="預留 demo training budget",
                    kind="finance",
                    status="missing",
                    note="Demo 版用假資料展示預算缺口追蹤。",
                ),
                Requirement(
                    id="req-casi-theory",
                    project_id="project-casi",
                    title="整理理論文本、影片與文件包",
                    kind="study",
                    status="missing",
                    note="要有固定可回顧的材料，不要每次都重找。",
                ),
                Requirement(
                    id="req-seasonal-eligibility",
                    project_id="project-seasonal",
                    title="seasonal employment 基本資格已知",
                    kind="eligibility",
                    status="met",
                    note="Demo profile remains in the eligible range for this sample track.",
                ),
                Requirement(
                    id="req-seasonal-file-pack",
                    project_id="project-seasonal",
                    title="建立文件清單與申請時間線",
                    kind="prerequisite",
                    status="missing",
                    note="這會直接影響你能不能在正確時間出手。",
                ),
                Requirement(
                    id="req-seasonal-cv",
                    project_id="project-seasonal",
                    title="準備seasonal workplace求職履歷與技能敘述",
                    kind="career",
                    status="missing",
                    note="證照、滑行能力與自我介紹要能被雇主理解。",
                ),
                Requirement(
                    id="req-academic-field",
                    project_id="project-academic",
                    title="定義academic track/學業的領域與門檻",
                    kind="definition",
                    status="missing",
                    note="不先定義領域，就無法倒推出學位與作品要求。",
                ),
                Requirement(
                    id="req-academic-roadmap",
                    project_id="project-academic",
                    title="拆出到 長期的年度里程碑",
                    kind="roadmap",
                    status="missing",
                    note="長期目標要轉成年度節點。",
                ),
            ],
            tasks=[
                Task(
                    id="task-license-docs",
                    project_id="project-license",
                    title="確認行政文件所需證件、地點、報到時間",
                    priority="critical",
                    due_at="2026-03-30T20:00",
                    estimate_minutes=45,
                    blocking=True,
                ),
                Task(
                    id="task-90d-map",
                    project_id="project-life-os",
                    title="把未來 90 天的主線目標縮成 3 到 4 條",
                    priority="high",
                    due_at="2026-03-31T22:00",
                    estimate_minutes=90,
                    blocking=True,
                ),
                Task(
                    id="task-life-dashboard",
                    project_id="project-life-os",
                    title="交付 Life OS 第一版 dashboard",
                    priority="high",
                    due_at="2026-04-07T23:00",
                    estimate_minutes=180,
                    blocking=True,
                ),
                Task(
                    id="task-life-conflicts",
                    project_id="project-life-os",
                    title="加入衝突與缺口規則",
                    priority="high",
                    due_at="2026-04-10T23:00",
                    estimate_minutes=120,
                    blocking=True,
                ),
                Task(
                    id="task-casi-checklist",
                    project_id="project-casi",
                    title="整理 Skill Certification L1 的理論、文件與能力缺口清單",
                    priority="medium",
                    due_at="2026-04-20T21:00",
                    estimate_minutes=90,
                ),
                Task(
                    id="task-seasonal-file-pack",
                    project_id="project-seasonal",
                    title="整理seasonal work履歷與時間線初稿",
                    priority="medium",
                    due_at="2026-04-25T21:00",
                    estimate_minutes=120,
                ),
                Task(
                    id="task-academic-outline",
                    project_id="project-academic",
                    title="寫出academic roadmap的里程碑草圖",
                    priority="medium",
                    due_at="2026-05-15T21:00",
                    estimate_minutes=120,
                ),
            ],
            events=[
                CalendarEvent(
                    id="event-car-license",
                    project_id="project-license",
                    title="行政文件 A",
                    start_at="2026-04-02T00:00",
                    end_at="2026-04-02T23:59",
                    all_day=True,
                    notes="已同步到 Apple Calendar。",
                    apple_calendar="計劃安排",
                ),
                CalendarEvent(
                    id="event-scooter-license",
                    project_id="project-license",
                    title="行政文件 B",
                    start_at="2026-04-14T00:00",
                    end_at="2026-04-14T23:59",
                    all_day=True,
                    notes="已同步到 Apple Calendar。",
                    apple_calendar="計劃安排",
                ),
                CalendarEvent(
                    id="event-architecture-session",
                    project_id="project-life-os",
                    title="Life OS 架構整理",
                    start_at="2026-03-29T19:00",
                    end_at="2026-03-29T21:30",
                ),
                CalendarEvent(
                    id="event-weekly-review",
                    project_id="project-life-os",
                    title="每週回顧與重排",
                    start_at="2026-03-29T22:00",
                    end_at="2026-03-29T23:00",
                ),
            ],
            reviews=[
                Review(
                    id="review-week-13",
                    period="2026-W13",
                    summary="目前最大的風險不是目標太多，而是缺少統一的規劃與回顧系統。",
                    keep=["先處理有硬期限的事情", "把人生目標當專案拆解"],
                    cut=["臨時想到就硬塞進同一天", "同時推太多方向卻沒有排序"],
                    next_focus=["完成 Life OS MVP", "確認兩場文件前置條件", "把 90 天主線縮小"],
                )
            ],
        )

    def _group_requirements(self, items: list[Requirement]) -> dict[str, list[Requirement]]:
        grouped: dict[str, list[Requirement]] = {}
        for item in items:
            grouped.setdefault(item.project_id, []).append(item)
        return grouped

    def _group_tasks(self, items: list[Task]) -> dict[str, list[Task]]:
        grouped: dict[str, list[Task]] = {}
        for item in items:
            if item.project_id is None:
                continue
            grouped.setdefault(item.project_id, []).append(item)
        return grouped

    def _cashflow_dashboard(self, entries: list[CashflowEntry], now: datetime) -> dict:
        today = now.date()
        month_start = today.replace(day=1)
        if month_start.month == 12:
            month_end = date(month_start.year + 1, 1, 1) - timedelta(days=1)
        else:
            month_end = date(month_start.year, month_start.month + 1, 1) - timedelta(days=1)
        plan_end = today + timedelta(days=30)

        month_actual = [
            entry
            for entry in entries
            if entry.status == "actual"
            and entry.kind in {"income", "expense"}
            and month_start <= _parse_date(entry.date) <= month_end
        ]
        planned_window = [
            entry
            for entry in entries
            if entry.status == "planned"
            and entry.kind in {"income", "expense"}
            and today <= _parse_date(entry.date) <= plan_end
        ]

        month_income = sum(entry.amount for entry in month_actual if entry.kind == "income")
        month_expense = sum(entry.amount for entry in month_actual if entry.kind == "expense")
        planned_income = sum(entry.amount for entry in planned_window if entry.kind == "income")
        planned_expense = sum(entry.amount for entry in planned_window if entry.kind == "expense")

        asset_positions = self._asset_positions(entries, today)
        category_breakdown = self._cashflow_category_breakdown(month_actual)

        return {
            "summary": {
                "month_label": f"{month_start.year}-{month_start.month:02d}",
                "month_income": month_income,
                "month_expense": month_expense,
                "month_net": month_income - month_expense,
                "planned_income_30d": planned_income,
                "planned_expense_30d": planned_expense,
                "planned_net_30d": planned_income - planned_expense,
                "asset_total": sum(item["amount"] for item in asset_positions),
                "entry_count": len(entries),
            },
            "upcoming": [entry.model_dump(mode="json") for entry in self._upcoming_cashflow(entries, today, plan_end)],
            "recent": [entry.model_dump(mode="json") for entry in self._sorted_cashflow_entries(entries)[:16]],
            "category_breakdown": category_breakdown,
            "asset_positions": asset_positions,
        }

    def _default_cashflow_category(self, kind: CashflowKind) -> str:
        defaults = {
            "income": "收入",
            "expense": "支出",
            "asset": "資產",
        }
        return defaults[kind]

    def _sorted_cashflow_entries(self, entries: list[CashflowEntry]) -> list[CashflowEntry]:
        status_rank = {"actual": 0, "planned": 1}
        kind_rank = {"income": 0, "expense": 1, "asset": 2}
        return sorted(
            entries,
            key=lambda item: (
                -_parse_date(item.date).toordinal(),
                status_rank[item.status],
                kind_rank[item.kind],
                item.title,
            ),
        )

    def _upcoming_cashflow(
        self,
        entries: list[CashflowEntry],
        window_start: date,
        window_end: date,
    ) -> list[CashflowEntry]:
        upcoming = [
            entry
            for entry in entries
            if entry.status == "planned"
            and entry.kind in {"income", "expense"}
            and window_start <= _parse_date(entry.date) <= window_end
        ]
        return sorted(upcoming, key=lambda item: (item.date, item.kind, item.title))[:8]

    def _asset_positions(self, entries: list[CashflowEntry], today: date) -> list[dict]:
        latest_by_key: dict[str, CashflowEntry] = {}
        for entry in entries:
            if entry.kind != "asset" or _parse_date(entry.date) > today:
                continue
            key = f"{entry.account}|{entry.title}"
            existing = latest_by_key.get(key)
            if existing is None or entry.date >= existing.date:
                latest_by_key[key] = entry

        latest_entries = sorted(
            latest_by_key.values(),
            key=lambda item: (-item.amount, item.title),
        )
        return [entry.model_dump(mode="json") for entry in latest_entries[:8]]

    def _cashflow_category_breakdown(self, entries: list[CashflowEntry]) -> list[dict]:
        grouped: dict[tuple[str, str], int] = {}
        for entry in entries:
            if entry.kind not in {"income", "expense"}:
                continue
            key = (entry.kind, entry.category)
            grouped[key] = grouped.get(key, 0) + entry.amount

        breakdown = [
            {"kind": kind, "category": category, "total": total}
            for (kind, category), total in grouped.items()
        ]
        breakdown.sort(key=lambda item: (-item["total"], item["category"]))
        return breakdown[:6]

    def _readiness(self, requirements: list[Requirement]) -> int:
        if not requirements:
            return 100
        met = sum(1 for item in requirements if item.status == "met")
        progress = sum(1 for item in requirements if item.status == "in_progress")
        score = (met + progress * 0.5) / len(requirements)
        return int(round(score * 100))

    def _project_risk(
        self,
        project: Project,
        requirements: list[Requirement],
        now: datetime,
    ) -> str:
        readiness = self._readiness(requirements)
        days_to_deadline = _days_until(project.deadline, now.date())
        if days_to_deadline is not None and days_to_deadline <= 21 and readiness < 70:
            return "critical"
        if days_to_deadline is not None and days_to_deadline <= 60 and readiness < 60:
            return "high"
        if readiness < 60:
            return "medium"
        return "stable"

    def _sorted_open_tasks(self, tasks: list[Task]) -> list[Task]:
        return sorted(
            tasks,
            key=lambda item: (
                item.status == "done",
                item.due_at or "9999-12-31T23:59",
                not item.blocking,
                PRIORITY_RANK[item.priority],
            ),
        )

    def _upcoming_events(self, events: list[CalendarEvent], now: datetime) -> list[dict]:
        future = []
        for event in events:
            end_at = _parse_datetime(event.end_at)
            if end_at >= now:
                future.append(event)
        future.sort(key=lambda item: item.start_at)
        return [event.model_dump(mode="json") for event in future[:10]]

    def _today_brief(self, state: LifeOSState, now: datetime) -> dict:
        today = now.date()
        today_events = [
            event.model_dump(mode="json")
            for event in sorted(state.events, key=lambda item: item.start_at)
            if _event_touches_day(event, today)
        ]
        today_tasks = []
        for task in self._sorted_open_tasks(state.tasks):
            if task.status == "done":
                continue
            due_date = _parse_datetime(task.due_at).date() if task.due_at else None
            if task.blocking or due_date == today:
                today_tasks.append(task.model_dump(mode="json"))

        if today_tasks or today_events:
            summary = "今天先處理硬期限與阻塞任務，其餘事情不要再往今天塞。"
        else:
            summary = "今天沒有硬排滿，保留空白去推進長期主線。"

        return {
            "date": today.isoformat(),
            "summary": summary,
            "tasks": today_tasks[:5],
            "events": today_events[:5],
        }

    def _collect_conflicts(
        self,
        state: LifeOSState,
        project_cards: list[dict],
        now: datetime,
    ) -> list[dict]:
        conflicts: list[dict] = []
        conflicts.extend(self._schedule_conflicts(state.events))

        for task in state.tasks:
            if task.status == "done" or task.due_at is None:
                continue
            due_at = _parse_datetime(task.due_at)
            if due_at < now:
                conflicts.append(
                    {
                        "id": f"conflict-overdue-{task.id}",
                        "kind": "deadline",
                        "severity": "high",
                        "title": f"任務逾期：{task.title}",
                        "detail": f"原定於 {task.due_at} 完成，現在已經過期。",
                        "action": "先決定是今天做完、延後，還是砍掉。",
                    }
                )
            elif task.blocking and (due_at - now).days <= 3:
                conflicts.append(
                    {
                        "id": f"conflict-blocking-{task.id}",
                        "kind": "blocker",
                        "severity": "high",
                        "title": f"阻塞中的前置任務：{task.title}",
                        "detail": f"這件事會影響後續專案，且截止時間接近 {task.due_at}。",
                        "action": "把它提升成近期最高優先，避免拖累整條主線。",
                    }
                )

        for project in project_cards:
            if project["risk"] not in {"high", "critical"}:
                continue
            conflicts.append(
                {
                    "id": f"conflict-project-{project['id']}",
                    "kind": "requirement",
                    "severity": project["risk"],
                    "title": f"專案缺口偏大：{project['title']}",
                    "detail": f"目前 readiness {project['readiness']}%，下一個缺口是「{project['next_gap']}」。",
                    "action": "不要再加新事情，先把前置條件補到可執行。",
                }
            )

        severity_rank = {"critical": 0, "high": 1, "medium": 2, "low": 3}
        conflicts.sort(key=lambda item: severity_rank.get(item["severity"], 9))
        return conflicts[:8]

    def _schedule_conflicts(self, events: list[CalendarEvent]) -> list[dict]:
        scheduled = sorted(events, key=lambda item: item.start_at)
        conflicts: list[dict] = []
        for current, nxt in zip(scheduled, scheduled[1:]):
            current_end = _parse_datetime(current.end_at)
            next_start = _parse_datetime(nxt.start_at)
            if next_start < current_end:
                conflicts.append(
                    {
                        "id": f"conflict-schedule-{current.id}-{nxt.id}",
                        "kind": "schedule",
                        "severity": "high",
                        "title": f"時間衝突：{current.title} / {nxt.title}",
                        "detail": f"{current.start_at} - {current.end_at} 與 {nxt.start_at} - {nxt.end_at} 重疊。",
                        "action": "二選一、調整時間，或把其中一個改成任務而不是事件。",
                    }
                )
        return conflicts

    def _employee_actions(
        self,
        tasks: list[Task],
        conflicts: list[dict],
        projects: list[dict],
    ) -> list[dict]:
        actions: list[dict] = []
        for conflict in conflicts[:2]:
            actions.append(
                {
                    "title": conflict["title"],
                    "reason": conflict["action"],
                }
            )

        for task in tasks:
            if task.status == "done":
                continue
            actions.append(
                {
                    "title": task.title,
                    "reason": f"優先級 {task.priority}，預估 {task.estimate_minutes} 分鐘。",
                }
            )
            if len(actions) >= 4:
                break

        if len(actions) < 4:
            for project in projects:
                if project["readiness"] >= 70:
                    continue
                actions.append(
                    {
                        "title": f"補齊「{project['title']}」的缺口",
                        "reason": project["next_gap"],
                    }
                )
                if len(actions) >= 4:
                    break

        return actions

    def _next_id(self, prefix: str, existing_ids: list[str]) -> str:
        indices = []
        for item_id in existing_ids:
            if not item_id.startswith(f"{prefix}-"):
                continue
            suffix = item_id.split("-")[-1]
            if suffix.isdigit():
                indices.append(int(suffix))
        return f"{prefix}-{(max(indices) + 1) if indices else 1}"


def _parse_datetime(value: str) -> datetime:
    return datetime.fromisoformat(value)


def _parse_date(value: str) -> date:
    return date.fromisoformat(value)


def _days_until(value: str | None, today: date) -> int | None:
    if value is None:
        return None
    return (date.fromisoformat(value) - today).days


def _time_window(start_at: str, end_at: str) -> str:
    return f"{_parse_datetime(start_at).strftime('%H:%M')} - {_parse_datetime(end_at).strftime('%H:%M')}"


def _event_touches_day(event: CalendarEvent, target_day: date) -> bool:
    start_day = _parse_datetime(event.start_at).date()
    end_day = _parse_datetime(event.end_at).date()
    return start_day <= target_day <= end_day


def _event_in_window(event: CalendarEvent, range_start: datetime, range_end: datetime) -> bool:
    event_start = _parse_datetime(event.start_at)
    event_end = _parse_datetime(event.end_at)
    return event_end >= range_start and event_start <= range_end
