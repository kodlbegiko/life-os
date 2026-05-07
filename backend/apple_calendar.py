from __future__ import annotations

import subprocess
from dataclasses import dataclass


@dataclass
class AppleCalendarEventPayload:
    title: str
    start_at: str
    end_at: str
    location: str = ""
    notes: str = ""
    all_day: bool = False
    apple_uid: str | None = None


@dataclass
class AppleCalendarEventRecord:
    apple_uid: str
    title: str
    start_at: str
    end_at: str
    all_day: bool
    location: str = ""
    notes: str = ""


class AppleCalendarClient:
    def list_calendars(self) -> list[str]:
        output = self._run_applescript('tell application "Calendar" to get name of calendars')
        if not output.strip():
            return []
        return [item.strip() for item in output.split(",") if item.strip()]

    def upsert_event(self, calendar_name: str, payload: AppleCalendarEventPayload) -> str:
        lines = [
            'on buildDate(isoValue)',
            '    set y to (text 1 thru 4 of isoValue) as integer',
            '    set m to (text 6 thru 7 of isoValue) as integer',
            '    set d to (text 9 thru 10 of isoValue) as integer',
            '    set hh to (text 12 thru 13 of isoValue) as integer',
            '    set mm to (text 15 thru 16 of isoValue) as integer',
            '    set builtDate to current date',
            '    set year of builtDate to y',
            '    set month of builtDate to m',
            '    set day of builtDate to d',
            '    set time of builtDate to (hh * hours) + (mm * minutes)',
            '    return builtDate',
            'end buildDate',
            '',
            'tell application "Calendar"',
            f'    set targetCalendar to calendar "{self._escape(calendar_name)}"',
            f'    set startDate to my buildDate("{payload.start_at}")',
            f'    set endDate to my buildDate("{payload.end_at}")',
            '    set existingEvent to missing value',
        ]

        if payload.apple_uid:
            lines.extend(
                [
                    '    try',
                    f'        set existingEvent to first event of targetCalendar whose uid is "{self._escape(payload.apple_uid)}"',
                    '    end try',
                ]
            )

        lines.extend(
            [
                '    if existingEvent is missing value then',
                '        tell targetCalendar',
                (
                    f'            set existingEvent to make new event at end of events with properties '
                    f'{{summary:"{self._escape(payload.title)}", start date:startDate, end date:endDate, '
                    f'location:"{self._escape(payload.location)}", description:"{self._escape(payload.notes)}", '
                    f'allday event:{str(payload.all_day).lower()}}}'
                ),
                '        end tell',
                '    else',
                '        tell existingEvent',
                f'            set summary to "{self._escape(payload.title)}"',
                '            set end date to endDate',
                '            set start date to startDate',
                f'            set location to "{self._escape(payload.location)}"',
                f'            set description to "{self._escape(payload.notes)}"',
                f'            set allday event to {str(payload.all_day).lower()}',
                '        end tell',
                '    end if',
                '    return uid of existingEvent',
                'end tell',
            ]
        )
        script = "\n".join(lines)
        return self._run_applescript(script).strip()

    def list_events(
        self,
        calendar_name: str,
        range_start: str,
        range_end: str,
    ) -> list[AppleCalendarEventRecord]:
        lines = [
            'on pad2(n)',
            '    if n < 10 then',
            '        return "0" & n',
            '    end if',
            '    return n as text',
            'end pad2',
            '',
            'on isoText(d)',
            '    set y to year of d as integer',
            '    set m to my pad2(month of d as integer)',
            '    set dayValue to my pad2(day of d as integer)',
            '    set hh to my pad2(hours of d)',
            '    set mm to my pad2(minutes of d)',
            '    return (y as text) & "-" & m & "-" & dayValue & "T" & hh & ":" & mm',
            'end isoText',
            '',
            'tell application "Calendar"',
            f'    set targetCalendar to calendar "{self._escape(calendar_name)}"',
            f'    set rangeStart to date "{self._applescript_date(range_start)}"',
            f'    set rangeEnd to date "{self._applescript_date(range_end)}"',
            '    set rows to {}',
            '    repeat with e in (every event of targetCalendar whose end date >= rangeStart and start date <= rangeEnd)',
            '        set rowText to (uid of e) & tab & (summary of e) & tab & my isoText(start date of e) & tab & my isoText(end date of e) & tab & (allday event of e as text)',
            '        set end of rows to rowText',
            '    end repeat',
            '    if (count of rows) is 0 then',
            '        return ""',
            '    end if',
            '    set originalDelimiters to AppleScript\'s text item delimiters',
            '    set AppleScript\'s text item delimiters to linefeed',
            '    set outputText to rows as text',
            '    set AppleScript\'s text item delimiters to originalDelimiters',
            '    return outputText',
            'end tell',
        ]

        output = self._run_applescript("\n".join(lines))
        if not output.strip():
            return []

        records = []
        for row in output.splitlines():
            parts = row.split("\t")
            if len(parts) < 5:
                continue
            records.append(
                AppleCalendarEventRecord(
                    apple_uid=parts[0],
                    title=parts[1],
                    start_at=parts[2],
                    end_at=parts[3],
                    all_day=parts[4].lower() == "true",
                )
            )
        return sorted(records, key=lambda item: item.start_at)

    def _run_applescript(self, script: str) -> str:
        result = subprocess.run(
            ["osascript"],
            input=script,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "AppleScript failed")
        return result.stdout.strip()

    def _applescript_date(self, value: str) -> str:
        return value.replace("T", " ")

    def _escape(self, value: str) -> str:
        return value.replace("\\", "\\\\").replace('"', '\\"')
