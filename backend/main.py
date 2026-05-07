from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles

from .life_os import (
    CalendarImportRequest,
    CalendarSyncRequest,
    CashflowEntryCreate,
    CashflowEntryUpdate,
    EventCreate,
    LifeOSStore,
    QuickCaptureRequest,
    RequirementUpdate,
    TaskCreate,
    TaskUpdate,
)


BASE_DIR = Path(__file__).resolve().parent.parent
FRONTEND_DIR = BASE_DIR / "frontend"
PUBLIC_DEMO = os.getenv("LIFE_OS_PUBLIC_DEMO", "0") == "1"
DATA_PATH = Path(os.getenv("LIFE_OS_DATA_PATH", "/tmp/life_os_public_demo.json" if PUBLIC_DEMO else str(BASE_DIR / "data" / "life_os.json")))

store = LifeOSStore(DATA_PATH)

app = FastAPI(
    title="Life OS Public Demo",
    description="Read-only public demo for Life OS goals, projects, tasks, calendar signals, and cashflow.",
    version="0.3.0",
)

app.mount("/assets", StaticFiles(directory=FRONTEND_DIR), name="assets")


def ensure_writable() -> None:
    if PUBLIC_DEMO:
        raise HTTPException(status_code=403, detail="Public demo is read-only.")


def with_app_mode(payload: dict) -> dict:
    payload["app_mode"] = {"publicDemo": PUBLIC_DEMO, "readOnly": PUBLIC_DEMO}
    return payload


@app.get("/")
def index() -> FileResponse:
    return FileResponse(FRONTEND_DIR / "index.html")


@app.get("/favicon.ico")
def favicon() -> FileResponse:
    return FileResponse(FRONTEND_DIR / "favicon.svg", media_type="image/svg+xml")


@app.get("/health")
def health() -> dict[str, str | bool]:
    return {"status": "ok", "publicDemo": PUBLIC_DEMO, "readOnly": PUBLIC_DEMO}


@app.get("/api/dashboard")
def dashboard() -> dict:
    return with_app_mode(store.get_dashboard())


@app.get("/api/calendars")
def list_calendars() -> dict[str, list[str]]:
    ensure_writable()
    return {"calendars": store.list_calendars()}


@app.post("/api/calendars/import")
def import_calendar(payload: CalendarImportRequest) -> dict:
    ensure_writable()
    return store.import_events_from_apple(
        calendar_name=payload.calendar_name,
        days_before=payload.days_before,
        days_after=payload.days_after,
    )


@app.post("/api/tasks")
def create_task(payload: TaskCreate) -> dict:
    ensure_writable()
    return store.create_task(payload)


@app.delete("/api/tasks/{task_id}", status_code=204)
def delete_task(task_id: str) -> Response:
    ensure_writable()
    try:
        store.delete_task(task_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown task: {task_id}") from exc
    return Response(status_code=204)


@app.post("/api/capture")
def quick_capture(payload: QuickCaptureRequest) -> dict[str, list[dict]]:
    ensure_writable()
    return {"created": store.quick_capture(payload.text)}


@app.get("/api/replan-week")
def replan_week() -> dict:
    return store.replan_week()


@app.patch("/api/tasks/{task_id}")
def update_task(task_id: str, payload: TaskUpdate) -> dict:
    ensure_writable()
    try:
        return store.update_task(task_id, payload)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown task: {task_id}") from exc


@app.post("/api/events")
def create_event(payload: EventCreate) -> dict:
    ensure_writable()
    try:
        return store.create_event(payload)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.delete("/api/events/{event_id}", status_code=204)
def delete_event(event_id: str) -> Response:
    ensure_writable()
    try:
        store.delete_event(event_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown event: {event_id}") from exc
    return Response(status_code=204)


@app.post("/api/cashflow/entries")
def create_cashflow_entry(payload: CashflowEntryCreate) -> dict:
    ensure_writable()
    return store.create_cashflow_entry(payload)


@app.patch("/api/cashflow/entries/{entry_id}")
def update_cashflow_entry(entry_id: str, payload: CashflowEntryUpdate) -> dict:
    ensure_writable()
    try:
        return store.update_cashflow_entry(entry_id, payload)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown cashflow entry: {entry_id}") from exc


@app.delete("/api/cashflow/entries/{entry_id}", status_code=204)
def delete_cashflow_entry(entry_id: str) -> Response:
    ensure_writable()
    try:
        store.delete_cashflow_entry(entry_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown cashflow entry: {entry_id}") from exc
    return Response(status_code=204)


@app.post("/api/events/{event_id}/sync-apple")
def sync_event_to_apple(event_id: str, payload: CalendarSyncRequest) -> dict:
    ensure_writable()
    try:
        return store.sync_event_to_apple(event_id, payload.calendar_name)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown event: {event_id}") from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.patch("/api/requirements/{requirement_id}")
def update_requirement(requirement_id: str, payload: RequirementUpdate) -> dict:
    ensure_writable()
    try:
        return store.update_requirement(requirement_id, payload)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown requirement: {requirement_id}") from exc
