from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime
from typing import Literal


CaptureKind = Literal["task", "event"]

RANGE_PATTERNS = [
    re.compile(
        r"^\s*(?P<date>\d{4}-\d{1,2}-\d{1,2}|\d{1,2}/\d{1,2})\s+"
        r"(?P<start>\d{1,2}:\d{2})\s*(?:-|~|到)\s*(?P<end>\d{1,2}:\d{2})\s+"
        r"(?P<title>.+?)\s*$"
    ),
]
DATE_PATTERNS = [
    re.compile(r"^\s*(?P<date>\d{4}-\d{1,2}-\d{1,2}|\d{1,2}/\d{1,2})\s+(?P<title>.+?)\s*$"),
]
TASK_DUE_PATTERNS = [
    re.compile(
        r"^\s*(?:截止|due)\s*(?P<date>\d{4}-\d{1,2}-\d{1,2}|\d{1,2}/\d{1,2})"
        r"(?:\s+(?P<time>\d{1,2}:\d{2}))?\s+(?P<title>.+?)\s*$",
        re.IGNORECASE,
    ),
]


@dataclass
class ParsedCapture:
    kind: CaptureKind
    title: str
    project_id: str | None = None
    start_at: str | None = None
    end_at: str | None = None
    all_day: bool = False
    due_at: str | None = None


def parse_capture_text(text: str, now: datetime) -> list[ParsedCapture]:
    items: list[ParsedCapture] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        items.append(_parse_line(line, now))
    return items


def _parse_line(line: str, now: datetime) -> ParsedCapture:
    for pattern in RANGE_PATTERNS:
        match = pattern.match(line)
        if match:
            date_value = _normalize_date(match.group("date"), now)
            return ParsedCapture(
                kind="event",
                title=_clean_title(match.group("title")),
                project_id=_infer_project_id(match.group("title")),
                start_at=f"{date_value}T{match.group('start')}",
                end_at=f"{date_value}T{match.group('end')}",
            )

    for pattern in TASK_DUE_PATTERNS:
        match = pattern.match(line)
        if match:
            date_value = _normalize_date(match.group("date"), now)
            due_at = f"{date_value}T{match.group('time') or '21:00'}"
            return ParsedCapture(
                kind="task",
                title=_clean_title(match.group("title")),
                project_id=_infer_project_id(match.group("title")),
                due_at=due_at,
            )

    for pattern in DATE_PATTERNS:
        match = pattern.match(line)
        if match:
            date_value = _normalize_date(match.group("date"), now)
            return ParsedCapture(
                kind="event",
                title=_clean_title(match.group("title")),
                project_id=_infer_project_id(match.group("title")),
                start_at=f"{date_value}T00:00",
                end_at=f"{date_value}T23:59",
                all_day=True,
            )

    title = _clean_title(line.removeprefix("任務:").removeprefix("任務："))
    return ParsedCapture(
        kind="task",
        title=title,
        project_id=_infer_project_id(title),
    )


def _normalize_date(value: str, now: datetime) -> str:
    if "-" in value:
        parsed = datetime.strptime(value, "%Y-%m-%d")
        return parsed.date().isoformat()
    month, day = value.split("/")
    return datetime(now.year, int(month), int(day)).date().isoformat()


def _clean_title(value: str) -> str:
    return value.strip()


def _infer_project_id(title: str) -> str | None:
    normalized = title.lower()
    if any(keyword in normalized for keyword in ("life os", "dashboard", "網站", "系統", "calendar")):
        return "project-life-os"
    if any(keyword in title for keyword in ("casi", "seasonal training", "單板", "snowboard", "ski")):
        return "project-casi"
    if any(keyword in title for keyword in ("seasonal work", "seasonal workplace", "履歷")):
        return "project-seasonal"
    if any(keyword in title for keyword in ("行政文件", "證件", "專注工作", "通勤工具", "汽車")):
        return "project-license"
    if any(keyword in title for keyword in ("學術", "academic track", "學業", "研究所", "論文")):
        return "project-academic"
    return None
