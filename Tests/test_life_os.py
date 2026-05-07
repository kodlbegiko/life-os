from __future__ import annotations

from datetime import datetime

from backend.apple_calendar import AppleCalendarEventRecord
from backend.life_os import (
    CashflowEntryCreate,
    CashflowEntryUpdate,
    EventCreate,
    LifeOSStore,
    RequirementUpdate,
    TaskCreate,
    TaskUpdate,
)


FIXED_NOW = datetime(2026, 3, 28, 12, 0)


class FakeCalendarClient:
    def __init__(self) -> None:
        self.events = []
        self.import_records = [
            AppleCalendarEventRecord(
                apple_uid="apple-import-1",
                title="Apple 行事曆匯入測試",
                start_at="2026-03-30T09:00",
                end_at="2026-03-30T10:00",
                all_day=False,
                location="Demo City",
                notes="from fake calendar",
            )
        ]

    def list_calendars(self) -> list[str]:
        return ["計劃安排", "工作"]

    def upsert_event(self, calendar_name, payload) -> str:
        self.events.append((calendar_name, payload))
        return payload.apple_uid or "fake-apple-uid"

    def list_events(self, calendar_name, range_start, range_end):
        return self.import_records


def make_store(tmp_path) -> LifeOSStore:
    return LifeOSStore(
        tmp_path / "life_os.json",
        now_provider=lambda: FIXED_NOW,
        calendar_client=FakeCalendarClient(),
    )


def test_dashboard_exposes_seed_data(tmp_path) -> None:
    store = make_store(tmp_path)

    dashboard = store.get_dashboard()

    assert dashboard["profile"]["home_base"] == "Demo City"
    assert dashboard["snapshot"]["active_goals"] >= 4
    assert any(project["title"] == "Life OS MVP" for project in dashboard["projects"])
    assert any(task["blocking"] for task in dashboard["tasks"])
    assert "cashflow" in dashboard
    assert dashboard["cashflow"]["summary"]["month_income"] == 0


def test_blocker_conflicts_exist_near_fixed_deadlines(tmp_path) -> None:
    store = make_store(tmp_path)

    dashboard = store.get_dashboard()

    assert any(conflict["kind"] == "blocker" for conflict in dashboard["conflicts"])
    assert any(conflict["kind"] == "requirement" for conflict in dashboard["conflicts"])


def test_create_and_update_task(tmp_path) -> None:
    store = make_store(tmp_path)

    created = store.create_task(
        TaskCreate(
            title="整理 4 月每週回顧",
            project_id="project-life-os",
            due_at="2026-03-29T20:00",
            priority="high",
            estimate_minutes=45,
            blocking=False,
        )
    )
    updated = store.update_task(created["id"], TaskUpdate(status="done"))

    dashboard = store.get_dashboard()

    assert updated["status"] == "done"
    assert any(task["id"] == created["id"] and task["status"] == "done" for task in dashboard["tasks"])


def test_overlapping_events_are_reported(tmp_path) -> None:
    store = make_store(tmp_path)

    store.create_event(
        EventCreate(
            title="與文件衝突的測試事件",
            project_id="project-license",
            start_at="2026-04-02T10:00",
            end_at="2026-04-02T11:00",
            all_day=False,
        )
    )

    dashboard = store.get_dashboard()

    assert any(conflict["kind"] == "schedule" for conflict in dashboard["conflicts"])


def test_requirement_status_can_change(tmp_path) -> None:
    store = make_store(tmp_path)

    updated = store.update_requirement(
        "req-license-docs",
        RequirementUpdate(status="met"),
    )

    dashboard = store.get_dashboard()
    license_project = next(project for project in dashboard["projects"] if project["id"] == "project-license")

    assert updated["status"] == "met"
    assert license_project["readiness"] >= 50


def test_event_can_sync_to_apple_calendar(tmp_path) -> None:
    store = make_store(tmp_path)

    synced = store.sync_event_to_apple("event-architecture-session", "計劃安排")

    assert synced["apple_uid"] == "fake-apple-uid"
    assert synced["apple_calendar"] == "計劃安排"
    assert synced["synced_at"] == "2026-03-28T12:00:00"


def test_quick_capture_creates_events_and_tasks(tmp_path) -> None:
    store = make_store(tmp_path)

    created = store.quick_capture(
        "4/3 19:00-21:00 專注工作練習\n截止 4/1 20:00 確認行政文件證件\n整理seasonal work履歷"
    )

    assert len(created) == 3
    assert created[0]["kind"] == "event"
    assert created[0]["project_id"] == "project-license"
    assert created[1]["kind"] == "task"
    assert created[1]["due_at"] == "2026-04-01T20:00"
    assert created[2]["project_id"] == "project-seasonal"


def test_apple_calendar_import_creates_or_updates_events(tmp_path) -> None:
    store = make_store(tmp_path)

    result = store.import_events_from_apple("計劃安排", days_before=3, days_after=10)
    dashboard = store.get_dashboard()

    assert result["imported_count"] == 1
    assert result["removed_count"] == 0
    assert any(event["apple_uid"] == "apple-import-1" for event in dashboard["events"])


def test_weekly_replan_returns_plan_days_and_must_do(tmp_path) -> None:
    store = make_store(tmp_path)

    plan = store.replan_week()

    assert "summary" in plan
    assert len(plan["plan_days"]) == 7
    assert any(item["reason"] == "阻塞任務" for item in plan["must_do"])


def test_dashboard_includes_today_brief(tmp_path) -> None:
    store = make_store(tmp_path)

    dashboard = store.get_dashboard()

    assert dashboard["today"]["date"] == "2026-03-28"
    assert "summary" in dashboard["today"]


def test_delete_task_and_event(tmp_path) -> None:
    store = make_store(tmp_path)

    task = store.create_task(TaskCreate(title="刪除測試任務"))
    event = store.create_event(
        EventCreate(
            title="刪除測試事件",
            start_at="2026-03-29T09:00",
            end_at="2026-03-29T10:00",
        )
    )

    store.delete_task(task["id"])
    store.delete_event(event["id"])
    dashboard = store.get_dashboard()

    assert all(item["id"] != task["id"] for item in dashboard["tasks"])
    assert all(item["id"] != event["id"] for item in dashboard["events"])


def test_apple_calendar_import_removes_stale_synced_events(tmp_path) -> None:
    store = make_store(tmp_path)

    store.sync_event_to_apple("event-architecture-session", "計劃安排")
    result = store.import_events_from_apple("計劃安排", days_before=3, days_after=10)
    dashboard = store.get_dashboard()

    assert result["removed_count"] == 1
    assert all(event["title"] != "Life OS 架構整理" for event in dashboard["events"])


def test_create_update_and_delete_cashflow_entry(tmp_path) -> None:
    store = make_store(tmp_path)

    created = store.create_cashflow_entry(
        CashflowEntryCreate(
            title="Part-time收入",
            kind="income",
            status="planned",
            amount=1200,
            date="2026-04-01",
            category="Part-time",
            account="現金",
            project_id="project-income",
        )
    )
    updated = store.update_cashflow_entry(
        created["id"],
        CashflowEntryUpdate(status="actual", note="已收到"),
    )
    dashboard = store.get_dashboard()

    assert updated["status"] == "actual"
    assert dashboard["cashflow"]["summary"]["planned_income_30d"] == 0

    store.delete_cashflow_entry(created["id"])
    dashboard_after_delete = store.get_dashboard()
    assert all(entry["id"] != created["id"] for entry in dashboard_after_delete["cashflow"]["recent"])


def test_cashflow_summary_and_assets(tmp_path) -> None:
    store = make_store(tmp_path)

    store.create_cashflow_entry(
        CashflowEntryCreate(
            title="Part-time收入",
            kind="income",
            status="actual",
            amount=1200,
            date="2026-03-28",
            category="Part-time",
        )
    )
    store.create_cashflow_entry(
        CashflowEntryCreate(
            title="午餐",
            kind="expense",
            status="actual",
            amount=150,
            date="2026-03-28",
            category="飲食",
        )
    )
    store.create_cashflow_entry(
        CashflowEntryCreate(
            title="2330",
            kind="asset",
            status="actual",
            amount=12345,
            date="2026-03-28",
            category="投資",
            account="Demo Bank",
        )
    )
    store.create_cashflow_entry(
        CashflowEntryCreate(
            title="比賽報名交通",
            kind="expense",
            status="planned",
            amount=300,
            date="2026-04-10",
            category="比賽",
        )
    )

    dashboard = store.get_dashboard()

    assert dashboard["cashflow"]["summary"]["month_income"] == 1200
    assert dashboard["cashflow"]["summary"]["month_expense"] == 150
    assert dashboard["cashflow"]["summary"]["month_net"] == 1050
    assert dashboard["cashflow"]["summary"]["planned_expense_30d"] == 300
    assert dashboard["cashflow"]["summary"]["asset_total"] == 12345
    assert dashboard["cashflow"]["asset_positions"][0]["title"] == "2330"
