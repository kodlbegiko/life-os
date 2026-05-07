#!/bin/bash
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && /bin/pwd)"
MODE="repair"
STORE="$HOME/Library/Application Support/LifeOSData.store"
APP_NAME="LifeOS"
BACKUP_DIR="$ROOT_DIR/backups/lifeos-store-$(/bin/date +%Y%m%d-%H%M%S)"

usage() {
  echo "usage: $0 [--check] [store-path]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|check)
      MODE="check"
      shift
      ;;
    --repair|repair)
      MODE="repair"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage
      exit 2
      ;;
    *)
      STORE="$1"
      shift
      ;;
  esac
done

if ! /usr/bin/command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is required but was not found." >&2
  exit 1
fi

if [[ ! -f "$STORE" ]]; then
  echo "SwiftData store not found: $STORE" >&2
  exit 1
fi

table_exists() {
  local table_name="$1"
  /usr/bin/sqlite3 "$STORE" "select count(*) from sqlite_master where type = 'table' and name = '$table_name';" | /usr/bin/tr -d '[:space:]'
}

scan_invalid_references() {
  /usr/bin/sqlite3 "$STORE" <<'SQL'
.headers off
.mode list
select 'ZTASKITEM.ZPROJECT', count(*) from ZTASKITEM t left join ZPROJECT p on t.ZPROJECT = p.Z_PK where t.ZPROJECT is not null and p.Z_PK is null;
select 'ZCALENDARITEM.ZPROJECT', count(*) from ZCALENDARITEM t left join ZPROJECT p on t.ZPROJECT = p.Z_PK where t.ZPROJECT is not null and p.Z_PK is null;
select 'ZLEDGERENTRY.ZPROJECT', count(*) from ZLEDGERENTRY t left join ZPROJECT p on t.ZPROJECT = p.Z_PK where t.ZPROJECT is not null and p.Z_PK is null;
select 'ZPLANNEDENTRY.ZPROJECT', count(*) from ZPLANNEDENTRY t left join ZPROJECT p on t.ZPROJECT = p.Z_PK where t.ZPROJECT is not null and p.Z_PK is null;
select 'ZPROJECT.ZGOAL', count(*) from ZPROJECT t left join ZGOAL p on t.ZGOAL = p.Z_PK where t.ZGOAL is not null and p.Z_PK is null;
select 'ZLEDGERENTRY.ZACCOUNT', count(*) from ZLEDGERENTRY t left join ZACCOUNT p on t.ZACCOUNT = p.Z_PK where t.ZACCOUNT is not null and p.Z_PK is null;
select 'ZLEDGERENTRY.ZCATEGORY', count(*) from ZLEDGERENTRY t left join ZCATEGORY p on t.ZCATEGORY = p.Z_PK where t.ZCATEGORY is not null and p.Z_PK is null;
select 'ZPLANNEDENTRY.ZACCOUNT', count(*) from ZPLANNEDENTRY t left join ZACCOUNT p on t.ZACCOUNT = p.Z_PK where t.ZACCOUNT is not null and p.Z_PK is null;
select 'ZPLANNEDENTRY.ZCATEGORY', count(*) from ZPLANNEDENTRY t left join ZCATEGORY p on t.ZCATEGORY = p.Z_PK where t.ZCATEGORY is not null and p.Z_PK is null;
select 'ZASSETSNAPSHOT.ZACCOUNT', count(*) from ZASSETSNAPSHOT t left join ZACCOUNT p on t.ZACCOUNT = p.Z_PK where t.ZACCOUNT is not null and p.Z_PK is null;
select 'ZASSETSNAPSHOT.ZCATEGORY', count(*) from ZASSETSNAPSHOT t left join ZCATEGORY p on t.ZCATEGORY = p.Z_PK where t.ZCATEGORY is not null and p.Z_PK is null;
SQL
  if [[ "$(table_exists ZDAILYPLANITEM)" == "1" ]]; then
    /usr/bin/sqlite3 "$STORE" <<'SQL'
.headers off
.mode list
select 'ZDAILYPLANITEM.ZTASK', count(*) from ZDAILYPLANITEM t left join ZTASKITEM p on t.ZTASK = p.Z_PK where t.ZTASK is not null and p.Z_PK is null;
select 'ZDAILYPLANITEM.ZCALENDARITEM', count(*) from ZDAILYPLANITEM t left join ZCALENDARITEM p on t.ZCALENDARITEM = p.Z_PK where t.ZCALENDARITEM is not null and p.Z_PK is null;
SQL
  else
    echo "ZDAILYPLANITEM.ZTASK|0"
    echo "ZDAILYPLANITEM.ZCALENDARITEM|0"
  fi
}

invalid_total() {
  scan_invalid_references | /usr/bin/awk -F'|' '{ total += $2 } END { print total + 0 }'
}

if [[ "$MODE" == "check" ]]; then
  echo "Invalid references:"
  scan_invalid_references
  remaining="$(invalid_total | /usr/bin/tr -d '[:space:]')"
  if [[ "$remaining" != "0" ]]; then
    echo "Store check failed. Invalid references: $remaining" >&2
    exit 1
  fi

  echo "Store check passed. Invalid references: 0"
  exit 0
fi

echo "Stopping $APP_NAME if it is running..."
/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
/bin/sleep 0.5

/bin/mkdir -p "$BACKUP_DIR"
for suffix in "" "-wal" "-shm"; do
  if [[ -e "$STORE$suffix" ]]; then
    /bin/cp -p "$STORE$suffix" "$BACKUP_DIR/"
  fi
done
echo "Backup created: $BACKUP_DIR"

echo "Invalid references before repair:"
scan_invalid_references

/usr/bin/sqlite3 "$STORE" >/dev/null <<'SQL'
pragma busy_timeout = 5000;
begin immediate;
update ZTASKITEM set ZPROJECT = null where ZPROJECT is not null and ZPROJECT not in (select Z_PK from ZPROJECT);
update ZCALENDARITEM set ZPROJECT = null where ZPROJECT is not null and ZPROJECT not in (select Z_PK from ZPROJECT);
update ZLEDGERENTRY set ZPROJECT = null where ZPROJECT is not null and ZPROJECT not in (select Z_PK from ZPROJECT);
update ZPLANNEDENTRY set ZPROJECT = null where ZPROJECT is not null and ZPROJECT not in (select Z_PK from ZPROJECT);
update ZPROJECT set ZGOAL = null where ZGOAL is not null and ZGOAL not in (select Z_PK from ZGOAL);
update ZLEDGERENTRY set ZACCOUNT = null where ZACCOUNT is not null and ZACCOUNT not in (select Z_PK from ZACCOUNT);
update ZLEDGERENTRY set ZCATEGORY = null where ZCATEGORY is not null and ZCATEGORY not in (select Z_PK from ZCATEGORY);
update ZPLANNEDENTRY set ZACCOUNT = null where ZACCOUNT is not null and ZACCOUNT not in (select Z_PK from ZACCOUNT);
update ZPLANNEDENTRY set ZCATEGORY = null where ZCATEGORY is not null and ZCATEGORY not in (select Z_PK from ZCATEGORY);
update ZASSETSNAPSHOT set ZACCOUNT = null where ZACCOUNT is not null and ZACCOUNT not in (select Z_PK from ZACCOUNT);
update ZASSETSNAPSHOT set ZCATEGORY = null where ZCATEGORY is not null and ZCATEGORY not in (select Z_PK from ZCATEGORY);
commit;
pragma wal_checkpoint(truncate);
SQL

if [[ "$(table_exists ZDAILYPLANITEM)" == "1" ]]; then
  /usr/bin/sqlite3 "$STORE" >/dev/null <<'SQL'
pragma busy_timeout = 5000;
begin immediate;
update ZDAILYPLANITEM set ZTASK = null where ZTASK is not null and ZTASK not in (select Z_PK from ZTASKITEM);
update ZDAILYPLANITEM set ZCALENDARITEM = null where ZCALENDARITEM is not null and ZCALENDARITEM not in (select Z_PK from ZCALENDARITEM);
commit;
pragma wal_checkpoint(truncate);
SQL
fi

echo "Invalid references after repair:"
scan_invalid_references

remaining="$(invalid_total | /usr/bin/tr -d '[:space:]')"
if [[ "$remaining" != "0" ]]; then
  echo "Repair incomplete. Remaining invalid references: $remaining" >&2
  exit 1
fi

echo "Store repair complete. Remaining invalid references: 0"
